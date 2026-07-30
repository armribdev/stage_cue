import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/audio/audio_file_validation.dart';
import '../../../../core/audio/audio_load_log.dart';
import '../../../../core/audio/local_sound_probe.dart';
import '../../../../core/database/database.dart' as db;
import '../../../../core/sync/audio_cache_manager.dart';
import '../../../../core/sync/drive_account_profile.dart';
import '../../../../core/sync/drive_client.dart';
import '../../../../core/sync/drive_models.dart';
import '../../../../core/sync/google_drive_client.dart';
import '../../../../core/sync/saf_drive_owner_resolver.dart';
import '../../../../core/sync/library_sound_paths.dart';
import '../../../../core/sync/library_sync_service.dart';
import '../../../../core/sync/local_availability_probe.dart' as probe;
import '../../../../core/sync/reconcile_path_matcher.dart';
import '../../../../core/sync/snapshot_store.dart';
import '../../../../core/utils/bounded_concurrency.dart';
import '../../../../core/utils/file_utils.dart' show isAudioFile;
import '../../../../core/utils/path_unicode.dart';
import '../../domain/entities/library.dart';
import '../../domain/entities/sound.dart';
import '../datasources/local_library_datasource.dart';
import '../datasources/local_sound_datasource.dart';
import '../models/indexing_progress.dart';

/// Nombre de fichiers reflétés en base par transaction lors de l'indexation
/// Drive. Compromis entre le coût par commit (qui plaide pour un lot unique) et
/// la fluidité de la progression affichée (qui plaide pour des lots courts).
const int _indexBatchSize = 250;

/// Listings Drive simultanés pendant le parcours de l'arborescence.
///
/// Volontairement modeste : au-delà, on ne gagne plus grand-chose (le parcours
/// se fait niveau par niveau, la profondeur borne déjà le parallélisme utile) et
/// on se rapproche des quotas Drive. Les 429 restent absorbés par le réessai
/// exponentiel de `GoogleDriveClient._guardRetry`, mais mieux vaut ne pas les
/// provoquer : chaque réessai coûte plus cher que la requête économisée.
const int _driveListingConcurrency = 5;

/// Levée quand un son de bibliothèque n'est pas accessible localement sans
/// déclencher un téléchargement (utilisé pendant le chargement des pads).
class SoundNotAvailableLocallyException implements Exception {
  /// true = appareil hors-ligne, false = fichier non encore téléchargé.
  final bool isOffline;
  const SoundNotAvailableLocallyException({required this.isOffline});

  @override
  String toString() =>
      isOffline ? 'Son indisponible hors-ligne' : 'Son non téléchargé';
}

/// Résultat de l'initialisation d'un dossier Drive nouvellement lié.
class DriveFolderLinkInitResult {
  final bool hadRemoteSnapshot;
  final int indexedNewFiles;

  const DriveFolderLinkInitResult({
    required this.hadRemoteSnapshot,
    required this.indexedNewFiles,
  });

  /// Upload si la BDD distante n'existait pas ou si de nouveaux fichiers ont été indexés.
  bool get shouldUpload => !hadRemoteSnapshot || indexedNewFiles > 0;
}

/// Résultat d'un scan complet d'un dossier Drive.
class DriveIndexResult {
  /// Nombre de nouveaux fichiers indexés (lignes `sounds` créées).
  final int newFileCount;

  /// IDs Drive de TOUS les fichiers audio vus lors de ce scan complet. Source
  /// de vérité pour l'existence : sert à élaguer les sons disparus, y compris
  /// après un pull de snapshot périmé qui aurait pu en réinsérer un (cf.
  /// [LibraryRepository.pruneSoundsAbsentFromDrive]).
  final Set<String> presentDriveFileIds;

  const DriveIndexResult({
    required this.newFileCount,
    required this.presentDriveFileIds,
  });
}

/// Orchestration des bibliothèques portables : relie l'authentification Drive
/// (infra `core/sync`) à la persistance locale (table Libraries).
///
/// Conserve la session Drive active ([activeClient]) pour les opérations de
/// synchronisation ultérieures (snapshot DB, cache audio).
class LibraryRepository extends ChangeNotifier {
  final LocalLibraryDataSource _dataSource;
  final DriveAuthenticator _authenticator;
  final LibrarySyncService _syncService;
  final AudioCacheManager _cacheManager;
  final LocalSoundDataSource _soundDataSource;

  DriveClient? _activeClient;

  /// Vrai après un 401 : bloque la reconnexion silencieuse jusqu'à un OAuth
  /// interactif réussi (sinon [connectSilently] recrée un client périmé).
  bool _requiresInteractiveReconnect = false;

  /// Vrai une fois le pull de lancement terminé (quel que soit son issue :
  /// succès, hors-ligne, aucune bibliothèque). Tant qu'il est faux, un plateau
  /// vide peut n'être que transitoire — la synchro de démarrage n'a pas encore
  /// fini de fusionner les boards distants — donc on n'auto-crée pas de « Scène
  /// 1 » fantôme. Posé par [AutoSyncCoordinator], jamais remis à false.
  bool _initialSyncSettled = false;

  /// Bibliothèques dont une passe de téléchargement est en cours : garantit
  /// qu'une seule tourne à la fois par bibliothèque (le bouton manuel « Tout
  /// télécharger » et le pré-téléchargement auto partagent [downloadAllLibraryAudio]).
  final Set<int> _downloadingLibraries = {};

  /// Bibliothèques dont l'utilisateur a demandé l'annulation du téléchargement.
  /// Consommé (et vidé) par [downloadAllLibraryAudio].
  final Set<int> _cancelledDownloads = {};

  /// Progression de téléchargement PAR bibliothèque, publiée via [notifyListeners].
  /// Vit dans le repository (durée de vie longue) et non dans l'écran Paramètres :
  /// fermer/rouvrir l'écran ré-attache l'UI à la progression réelle en cours,
  /// au lieu de la perdre. Absent = aucune passe connue.
  final Map<int, IndexingProgress> _downloadProgress = {};

  /// Progression de téléchargement courante d'une bibliothèque (null si aucune).
  IndexingProgress? libraryDownloadProgress(int libraryId) =>
      _downloadProgress[libraryId];

  /// Demande l'annulation de la passe de téléchargement d'une bibliothèque.
  /// Sans effet si aucune passe n'est en cours.
  void cancelLibraryDownload(int libraryId) {
    if (_downloadingLibraries.contains(libraryId)) {
      _cancelledDownloads.add(libraryId);
    }
  }

  void _publishDownloadProgress(int libraryId, IndexingProgress progress) {
    _downloadProgress[libraryId] = progress;
    notifyListeners();
  }

  /// Plateau actuellement affiché, renseigné par le `SamplerNotifier` à chaque
  /// changement de scène. Ses sons sont épinglés dans le cache audio : ils ne
  /// doivent jamais être évincés pendant qu'on joue dessus.
  int? activeBoardId;

  LibraryRepository(
    this._dataSource,
    this._authenticator,
    this._syncService,
    this._cacheManager,
    this._soundDataSource,
  );

  /// Assemble le repository avec ses dépendances Drive par défaut.
  factory LibraryRepository.fromDatabase(db.AppDatabase database) {
    final soundDataSource = LocalSoundDataSource(database);
    // Le plateau actif n'est connu qu'à l'exécution : la closure le relit à
    // chaque éviction, ce qui évite au cache de connaître le repository
    // autrement que par cette référence différée.
    late final LibraryRepository repository;
    repository = LibraryRepository(
      LocalLibraryDataSource(database),
      GoogleDriveAuthenticator(),
      LibrarySyncService(DriftSnapshotStore(database)),
      AudioCacheManager(
        // Épinglés, donc jamais évincés : les favoris (peu lus mais voulus sous
        // la main) ET les sons du plateau actif. La « protection implicite par
        // récence » ne suffit pas — un téléchargement massif rebat l'ordre LRU
        // et rend les sons de la scène en cours plus anciens que le reste.
        pinnedPaths: (library) async {
          final favorites =
              await soundDataSource.getFavoriteRelativePaths(library.id);
          final boardId = repository.activeBoardId;
          if (boardId == null) return favorites;
          return {
            ...favorites,
            ...await soundDataSource.getBoardRelativePaths(boardId),
          };
        },
      ),
      soundDataSource,
    );
    return repository;
  }

  DriveClient? get activeClient => _activeClient;
  String? get connectedAccountEmail => _authenticator.accountEmail;
  DriveAccountProfile? get connectedAccountProfile =>
      _authenticator.accountProfile;
  bool get isDriveSignedIn => _authenticator.accountProfile != null;
  bool get isConnected => _activeClient != null;

  /// Session utilisable pour les appels API (pas seulement un client en cache).
  bool get hasUsableDriveSession =>
      _activeClient != null && !_requiresInteractiveReconnect;

  /// OAuth interactif requis (token révoqué ou expiré).
  bool get requiresInteractiveReconnect => _requiresInteractiveReconnect;

  /// Le pull de lancement a-t-il fini sa passe (voir [_initialSyncSettled]) ?
  bool get initialSyncSettled => _initialSyncSettled;

  /// Signale la fin du pull de lancement — appelé par [AutoSyncCoordinator]
  /// sur tous les chemins de sortie (succès, hors-ligne, erreur, usage local).
  void markInitialSyncSettled() => _initialSyncSettled = true;

  void _notifyDriveSessionChanged() => notifyListeners();

  /// Identifiant Drive d'un dossier choisi via le sélecteur SAF Android.
  ///
  /// SAF expose parfois l'ID directement ; sinon on le déduit via l'API Drive
  /// (chemin relatif ou nom du dossier).
  Future<String?> resolveSafDriveFolderId({
    required String? driveFileId,
    required String folderName,
    String? relativeDrivePath,
  }) async {
    if (driveFileId != null && driveFileId.isNotEmpty) {
      return driveFileId;
    }

    final client = await _ensureDriveClient();
    if (client == null) {
      return null;
    }

    final path = relativeDrivePath?.trim() ?? '';
    if (path.isNotEmpty) {
      final byPath = await client.findFolderByRelativePath(path);
      if (byPath != null) {
        return byPath;
      }
    }

    return client.findFolderIdByName(folderName);
  }

  /// Résout l'e-mail propriétaire d'un dossier Drive choisi via SAF.
  ///
  /// Réutilise [activeClient] (session Bibliothèque Drive) si déjà connecté.
  Future<String?> resolveSafFolderOwnerEmail({
    required String? driveFileId,
    required String folderName,
  }) async {
    if (_authenticator is! GoogleDriveAuthenticator) {
      return null;
    }

    final client = await _ensureDriveClient();
    if (client == null) {
      return null;
    }

    return SafDriveOwnerResolver(_authenticator).resolveOwnerEmail(
      driveFileId: driveFileId,
      folderName: folderName,
      existingClient: client,
    );
  }

  /// Client Drive actif ou reconnexion silencieuse (sans nouveau consentement).
  Future<GoogleDriveClient?> _ensureDriveClient() async {
    if (_requiresInteractiveReconnect) {
      return null;
    }
    if (_activeClient is GoogleDriveClient) {
      return _activeClient as GoogleDriveClient;
    }

    final client = await _authenticator.connectSilently();
    if (client is GoogleDriveClient) {
      _activeClient = client;
      _notifyDriveSessionChanged();
      return client;
    }

    return null;
  }

  /// Exécute [action] avec le client Drive actif ; sur 401 (token périmé),
  /// renouvelle silencieusement la session une fois et réessaie.
  ///
  /// Couvre le cas d'une session ouverte depuis > 1 h : le client en cache
  /// porte un token expiré, [connectSilently] (avec `clearAuthCache`) en émet
  /// un frais. Un second 401 malgré le renouvellement = session réellement
  /// invalide → exige un OAuth interactif.
  Future<T> _withDriveClient<T>(
    Future<T> Function(DriveClient client) action,
  ) async {
    final client = _activeClient;
    if (client == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }
    try {
      return await action(client);
    } on DriveAuthException {
      final refreshed = await _remintDriveClientSilently();
      if (refreshed != null) {
        try {
          return await action(refreshed);
        } on DriveAuthException {
          // Deuxième 401 : le token frais est lui aussi rejeté.
        }
      }
      _requiresInteractiveReconnect = true;
      _notifyDriveSessionChanged();
      rethrow;
    }
  }

  /// Renouvelle silencieusement le client Drive (nouveau token). Null si aucune
  /// session ne peut être rétablie sans consentement interactif.
  Future<DriveClient?> _remintDriveClientSilently() async {
    if (_requiresInteractiveReconnect) {
      return null;
    }
    final fresh = await _authenticator.connectSilently();
    if (fresh == null) {
      return null;
    }
    _activeClient?.dispose();
    _activeClient = fresh;
    _notifyDriveSessionChanged();
    return fresh;
  }

  Future<List<Library>> getLibraries() => _dataSource.getAllLibraries();

  /// Ids des sons dont le fichier est déjà présent localement.
  ///
  /// Sonde de masse destinée à la recherche : voir
  /// [probeLocallyAvailableSoundIds] pour pourquoi elle ne passe pas par
  /// [resolvePlayablePath].
  Future<Set<int>> probeLocallyAvailableSoundIds(Iterable<Sound> sounds) async {
    final libraries = await getLibraries();
    return probe.probeLocallyAvailableSoundIds(
      sounds: sounds,
      libraryRootPaths: {
        for (final library in libraries) library.id: library.localRootPath,
      },
    );
  }

  /// Bibliothèque Drive unique liée, si une seule est configurée.
  Future<int?> singleConnectedLibraryId() async {
    final libraries = await getLibraries();
    final connected =
        libraries.where((library) => library.isConnectedToDrive).toList();
    if (connected.length != 1) return null;
    return connected.first.id;
  }

  /// Établit une session Drive (silencieuse puis interactive si besoin).
  /// Retourne false si l'utilisateur annule la connexion.
  ///
  /// Le refresh silencieux est toujours tenté, même si [_activeClient] est
  /// déjà défini : les tokens Google expirent après ~1 h et l'API renverrait
  /// un 401 si on réutilisait un token périmé sans le renouveler.
  Future<bool> ensureDriveConnected() async {
    if (_requiresInteractiveReconnect) {
      if (_activeClient != null) {
        _activeClient!.dispose();
        _activeClient = null;
      }
      final client = await _authenticator.connect();
      if (client == null) {
        _notifyDriveSessionChanged();
        return false;
      }
      _activeClient = client;
      _requiresInteractiveReconnect = false;
      await _authenticator.refreshAccountProfile();
      _notifyDriveSessionChanged();
      return true;
    }

    final fresh = await _authenticator.connectSilently();
    if (fresh != null) {
      _activeClient?.dispose();
      _activeClient = fresh;
      _requiresInteractiveReconnect = false;
      await _authenticator.refreshAccountProfile();
      _notifyDriveSessionChanged();
      return true;
    }

    // Le refresh silencieux a échoué (session révoquée ou inexistante).
    if (_activeClient != null) {
      _activeClient!.dispose();
      _activeClient = null;
    }

    final client = await _authenticator.connect();
    if (client == null) {
      _notifyDriveSessionChanged();
      return false;
    }
    _activeClient = client;
    _requiresInteractiveReconnect = false;
    _notifyDriveSessionChanged();
    await _authenticator.refreshAccountProfile();
    _notifyDriveSessionChanged();
    return true;
  }

  /// Drives d'équipe accessibles par l'utilisateur connecté.
  Future<List<DriveSharedDrive>> listDriveSharedDrives() {
    return _withDriveClient((client) => client.listSharedDrives());
  }

  /// Dossiers du filtre « Partagés avec moi ».
  Future<List<DriveFile>> listDriveSharedWithMeFolders() {
    return _withDriveClient((client) async {
      final folders = await client.listSharedWithMeFolders();
      return folders
        ..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    });
  }

  /// Liste les sous-dossiers d'un dossier Drive (triés par nom).
  Future<List<DriveFile>> listDriveChildFolders(
    String parentId, {
    String? sharedDriveId,
  }) {
    return _withDriveClient((client) async {
      final children = await client.listFolder(
        parentId,
        sharedDriveId: sharedDriveId,
      );
      return children.where((file) => file.isFolder).toList()
        ..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    });
  }

  /// Lie un dossier Drive existant (sans le créer) et enregistre la bibliothèque.
  Future<Library> linkDriveFolder({
    required String driveFolderId,
    required String name,
    String? drivePath,
    String? ownerEmail,
    String? sharedDriveId,
    bool autoDownload = false,
  }) async {
    final folder = await _withDriveClient(
      (client) => client.getFile(driveFolderId, sharedDriveId: sharedDriveId),
    );
    if (folder == null || !folder.isFolder) {
      throw ArgumentError('Dossier Drive introuvable');
    }

    final localRoot = await _createLocalRoot();
    final resolvedOwner = await _resolveOwnerEmailForFolder(
      driveFolderId,
      explicitOwnerEmail: ownerEmail,
    );
    return _dataSource.insertLibrary(
      name: name,
      localRootPath: localRoot,
      driveFolderId: driveFolderId,
      drivePath: drivePath,
      ownerEmail: resolvedOwner,
      sharedDriveId: sharedDriveId,
      autoDownload: autoDownload,
    );
  }

  /// Lance le consentement OAuth puis crée une bibliothèque : dossier Drive
  /// (réutilisé s'il existe déjà) + dossier de cache local + ligne en base.
  /// Retourne null si l'utilisateur annule la connexion.
  Future<Library?> connectAndCreateLibrary({
    required String name,
    bool autoDownload = false,
  }) async {
    final client = await _authenticator.connect();
    if (client == null) return null;
    _activeClient = client;
    _notifyDriveSessionChanged();

    // Réutilise un dossier homonyme créé précédemment par l'app, sinon crée-le.
    var folder = await client.findInFolder(parentId: 'root', name: name);
    folder ??= await client.createFolder(name: name);

    final localRoot = await _createLocalRoot();
    return _dataSource.insertLibrary(
      name: name,
      localRootPath: localRoot,
      driveFolderId: folder.id,
      drivePath: name,
      ownerEmail: _authenticator.accountEmail,
      autoDownload: autoDownload,
    );
  }

  /// Reconnexion silencieuse au démarrage (réutilise une session existante).
  /// Retourne true si une session a pu être rétablie.
  ///
  /// Tente toujours [connectSilently] pour renouveler un access token expiré :
  /// un [_activeClient] en cache ne garantit pas un token encore valide.
  Future<bool> reconnectSilently() async {
    if (_requiresInteractiveReconnect) {
      if (_activeClient != null) {
        _activeClient!.dispose();
        _activeClient = null;
      }
      await _authenticator.restoreAccountProfile();
      _notifyDriveSessionChanged();
      return false;
    }

    final previous = _activeClient;
    final client = await _authenticator.connectSilently();
    if (client != null) {
      if (!identical(previous, client)) {
        previous?.dispose();
      }
      _activeClient = client;
      _notifyDriveSessionChanged();
      return true;
    }

    if (_activeClient != null) {
      _activeClient!.dispose();
      _activeClient = null;
    }
    // Pas de session HTTP : restaurer au moins le profil (email, avatar).
    await _authenticator.restoreAccountProfile();
    _notifyDriveSessionChanged();
    return false;
  }

  /// Ferme la session HTTP active sans révoquer les tokens Google stockés.
  Future<void> releaseDriveSession() async {
    _activeClient?.dispose();
    _activeClient = null;
    _notifyDriveSessionChanged();
  }

  /// Recharge le profil Google (photo, nom) après reconnexion OAuth.
  Future<void> refreshConnectedAccountProfile() async {
    await _authenticator.refreshAccountProfile();
    _notifyDriveSessionChanged();
  }

  /// Token expiré ou révoqué : libère la session et exige un OAuth interactif.
  Future<void> invalidateAuthSession() async {
    _requiresInteractiveReconnect = true;
    await releaseDriveSession();
  }

  static final Set<String> _driveOwnerRefreshLogged = {};

  /// Met à jour [ownerEmail] des bibliothèques Drive depuis l'API (propriétaire
  /// réel, y compris dossiers partagés).
  Future<void> refreshLibraryOwnerEmails() async {
    final client = await _ensureDriveClient();
    if (client == null) return;

    final libraries = await getLibraries();
    for (final library in libraries) {
      final folderId = library.driveFolderId;
      if (folderId == null) continue;

      try {
        final owner = await client.getFolderOwnerEmail(folderId);
        if (owner == null || owner.trim().isEmpty) continue;
        final trimmed = owner.trim();
        if (trimmed == library.ownerEmail?.trim()) continue;
        await _dataSource.updateOwnerEmail(library.id, trimmed);
      } catch (e) {
        final message = e.toString();
        // Session expirée ou non connecté — cas attendu, pas de log.
        if (message.contains('invalid_token')) continue;
        if (_driveOwnerRefreshLogged.add(library.name)) {
          debugPrint(
            'Refresh propriétaire Drive échoué pour ${library.name}: $e',
          );
        }
      }
    }
  }

  /// E-mail propriétaire d'un dossier Drive (via l'API).
  Future<String?> resolveDriveFolderOwnerEmail(String driveFolderId) async {
    final client = await _ensureDriveClient();
    if (client == null) return null;
    return client.getFolderOwnerEmail(driveFolderId);
  }

  Future<String?> _resolveOwnerEmailForFolder(
    String driveFolderId, {
    String? explicitOwnerEmail,
  }) async {
    final explicit = explicitOwnerEmail?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final fromDrive = await resolveDriveFolderOwnerEmail(driveFolderId);
    if (fromDrive != null && fromDrive.trim().isNotEmpty) {
      return fromDrive.trim();
    }
    return _authenticator.accountEmail;
  }

  /// Liste le contenu distant d'une bibliothèque connectée à Drive.
  Future<List<DriveFile>> listLibraryContents(Library library) async {
    final client = _activeClient;
    final folderId = library.driveFolderId;
    if (client == null || folderId == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }
    return client.listFolder(
      folderId,
      sharedDriveId: library.sharedDriveId,
    );
  }

  /// Pousse l'état local de [library] vers Drive. En cas de succès, met à jour
  /// la révision et l'horodatage de synchro en base.
  ///
  /// [overrideKnownRevision] force la révision de référence (résolution de
  /// conflit « garder le local » : on adopte la révision distante pour passer
  /// la garde, ce qui écrase la version distante).
  Future<PushOutcome> pushLibrary(
    Library library, {
    int? overrideKnownRevision,
  }) {
    final rootFolderId = library.driveFolderId;
    if (rootFolderId == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }
    return _withDriveClient(
      (client) => _pushLibrary(
        client: client,
        library: library,
        rootFolderId: rootFolderId,
        overrideKnownRevision: overrideKnownRevision,
      ),
    );
  }

  Future<PushOutcome> _pushLibrary({
    required DriveClient client,
    required Library library,
    required String rootFolderId,
    int? overrideKnownRevision,
  }) async {
    final force = overrideKnownRevision != null;
    {
      // 1. Chaque nœud dossier pousse ses sons dans SON `.stagecue` co-localisé.
      final folders = await _dataSource.getFoldersForLibrary(library.id);
      for (final folder in folders) {
        final outcome = await _syncService.pushFolder(
          client: client,
          folderId: folder.id,
          folderDriveId: folder.driveFolderId,
          knownRevision: folder.lastSyncedRevision,
          force: force,
        );
        if (outcome is PushSuccess) {
          await _dataSource.updateFolderSyncState(
            id: folder.id,
            lastSyncedRevision: outcome.revision,
            lastSyncedAt: DateTime.now(),
          );
        } else if (outcome is PushConflict) {
          return outcome; // conflit remonté au niveau bibliothèque
        }
      }

      // 2. Snapshot racine (boards + pads référençant les sons par driveFileId).
      final rootOutcome = await _syncService.push(
        client: client,
        libraryId: library.id,
        libraryFolderId: rootFolderId,
        knownRevision: overrideKnownRevision ?? library.lastSyncedRevision,
        force: force,
      );
      if (rootOutcome is PushSuccess) {
        await _dataSource.updateSyncState(
          id: library.id,
          lastSyncedRevision: rootOutcome.revision,
          lastSyncedAt: DateTime.now(),
        );
      }
      return rootOutcome;
    }
  }

  /// Télécharge et fusionne le snapshot distant de [library] s'il est plus récent.
  ///
  /// Ordre important : on tire d'abord les nœuds dossier (les SONS), puis le
  /// snapshot racine (les BOARDS), qui recâble les pads sur les sons par
  /// driveFileId — les sons doivent donc déjà exister localement.
  Future<PullOutcome> pullLibrary(Library library) {
    final rootFolderId = library.driveFolderId;
    if (rootFolderId == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }
    return _withDriveClient(
      (client) => _pullLibrary(
        client: client,
        library: library,
        rootFolderId: rootFolderId,
      ),
    );
  }

  Future<PullOutcome> _pullLibrary({
    required DriveClient client,
    required Library library,
    required String rootFolderId,
  }) async {
    {
      var staged = false;
      // Révision réellement atteinte par le pull (et non celle d'avant), pour
      // que l'appelant ne reçoive pas une valeur périmée.
      var stagedRevision = library.lastSyncedRevision;

      // 1. Nœuds dossier (sons). Les nœuds locaux proviennent de l'indexation ;
      //    un appareil vierge les crée via indexDriveFolder avant que ceci ne
      //    remonte des métadonnées synchronisées.
      final folders = await _dataSource.getFoldersForLibrary(library.id);
      // Passe GROUPÉE : les sondes `.stagecue` et manifest de tous les nœuds
      // sont rassemblées, au lieu de deux allers-retours par dossier avant même
      // de savoir s'il y a quelque chose à tirer.
      final results = await _syncService.pullFolders(
        client: client,
        folders: [
          for (final folder in folders)
            FolderPullTarget(
              folderId: folder.id,
              folderDriveId: folder.driveFolderId,
              knownRevision: folder.lastSyncedRevision,
              knownProbeToken: folder.manifestProbeToken,
            ),
        ],
      );
      for (final folder in folders) {
        final result = results[folder.id];
        if (result == null) continue;

        final outcome = result.outcome;
        if (outcome is PullStaged) {
          staged = true;
          stagedRevision = outcome.revision;
          await _dataSource.updateFolderSyncState(
            id: folder.id,
            lastSyncedRevision: outcome.revision,
            lastSyncedAt: DateTime.now(),
          );
        }
        // Rafraîchit la sonde APRÈS la fusion : une passe interrompue avant ce
        // point laisse le cache tel quel, donc le prochain pull resondera au
        // lieu de croire à tort que le nœud est à jour.
        await _dataSource.updateFolderManifestProbe(
          id: folder.id,
          probeToken: result.probeToken,
        );
      }

      // 2. Snapshot racine (boards → recâblage par driveFileId).
      final rootOutcome = await _syncService.pull(
        client: client,
        libraryId: library.id,
        libraryFolderId: rootFolderId,
        knownRevision: library.lastSyncedRevision,
      );
      if (rootOutcome is PullStaged) {
        staged = true;
        stagedRevision = rootOutcome.revision;
        await _dataSource.updateSyncState(
          id: library.id,
          lastSyncedRevision: rootOutcome.revision,
          lastSyncedAt: DateTime.now(),
        );
      }

      if (staged) return PullStaged(stagedRevision);
      // Rien n'a été fusionné : c'est le snapshot RACINE (les boards) qui fait
      // foi pour dire si le distant est à jour ou simplement vide. Les nœuds
      // dossier, eux, peuvent légitimement n'avoir jamais été poussés.
      return rootOutcome is PullNoRemoteSnapshot
          ? const PullNoRemoteSnapshot()
          : const PullUpToDate();
    }
  }

  /// Nettoie les téléchargements interrompus de toutes les bibliothèques.
  ///
  /// À appeler au lancement, indépendamment du réseau : ces résidus sont un
  /// problème d'espace disque local, pas de synchro.
  Future<void> cleanupPartialDownloads() async {
    final libraries = await getLibraries();
    for (final library in libraries) {
      await _cacheManager.cleanupPartialDownloads(library);
    }
  }

  Future<Library?> getLibraryById(int id) => _dataSource.getLibraryById(id);

  /// Indique si le dossier Drive possède déjà un snapshot `.stagecue/library.db`.
  Future<bool> hasRemoteSnapshot(Library library) {
    final folderId = library.driveFolderId;
    if (folderId == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }
    return _withDriveClient(
      (client) => _syncService.hasRemoteSnapshot(
        client: client,
        libraryFolderId: folderId,
      ),
    );
  }

  /// Après liaison d'un dossier Drive : pull si BDD distante, indexation des
  /// nouveaux fichiers audio, puis [DriveFolderLinkInitResult.shouldUpload]
  /// indique s'il faut pousser les changements.
  Future<DriveFolderLinkInitResult> initializeLinkedDriveFolder({
    required Library library,
    void Function(IndexingProgress)? onProgress,
  }) async {
    final hasRemote = await hasRemoteSnapshot(library);
    var current = library;

    if (hasRemote) {
      await pullLibrary(current);
      current = await _dataSource.getLibraryById(library.id) ?? current;
    }

    final indexed = await indexDriveFolder(
      library: current,
      onProgress: onProgress,
    );

    return DriveFolderLinkInitResult(
      hadRemoteSnapshot: hasRemote,
      indexedNewFiles: indexed.newFileCount,
    );
  }

  /// Efface les marqueurs de blocage local pour un son de bibliothèque (retry).
  Future<void> clearPlaybackBlockForSound(Sound sound) async {
    final libraryId = sound.libraryId;
    final rawRelativePath = sound.relativePath;
    if (libraryId == null ||
        rawRelativePath == null ||
        rawRelativePath.isEmpty) {
      return;
    }
    final relativePath =
        LibrarySoundPaths.normalizeRelativePath(rawRelativePath);
    final library = await _dataSource.getLibraryById(libraryId);
    if (library == null) return;

    final localPath = _cacheManager.localPathFor(library, relativePath);
    clearUnloadablePath(localPath);
    try {
      final stalePath =
          await PathUnicode.canonicalizeLocalPath(localPath) ?? localPath;
      final stale = File(stalePath);
      if (await stale.exists() && !await isPlausibleAudioFile(stale)) {
        await stale.delete();
      }
    } catch (_) {}
  }

  /// Sonde disque rapide — sans SoLoud, sans réseau, sans modifier le cache.
  Future<LocalSoundProbeResult> probeLocalCache(Sound sound) async {
    final libraryId = sound.libraryId;
    final rawRelativePath = sound.relativePath;
    if (libraryId == null ||
        rawRelativePath == null ||
        rawRelativePath.isEmpty) {
      return LocalSoundProbeResult.needsDownload;
    }

    final relativePath =
        LibrarySoundPaths.normalizeRelativePath(rawRelativePath);
    final library = await _dataSource.getLibraryById(libraryId);
    if (library == null) {
      return LocalSoundProbeResult.needsDownload;
    }

    final localPath = _cacheManager.localPathFor(library, relativePath);
    if (isKnownUnloadablePath(localPath)) {
      // Cache corrompu ou échec précédent : autoriser un nouveau téléchargement
      // si Drive est joignable plutôt que de bloquer définitivement le pad.
      final client = await _ensureDriveClient();
      if (client != null) {
        clearUnloadablePath(localPath);
        try {
          final stalePath =
              await PathUnicode.canonicalizeLocalPath(localPath) ?? localPath;
          final stale = File(stalePath);
          if (await stale.exists()) await stale.delete();
        } catch (_) {}
        return LocalSoundProbeResult.needsDownload;
      }
      return LocalSoundProbeResult.missingFile;
    }

    final cachedPath =
        await PathUnicode.canonicalizeLocalPath(localPath) ?? localPath;
    final localFile = File(cachedPath);
    if (await isPlausibleAudioFile(localFile)) {
      return LocalSoundProbeResult.cached;
    }
    if (await localFile.exists()) {
      return LocalSoundProbeResult.needsDownload;
    }

    final client = await _ensureDriveClient();
    if (client == null) {
      return LocalSoundProbeResult.offline;
    }
    return LocalSoundProbeResult.needsDownload;
  }

  /// Vérifie la présence distante d'un son de bibliothèque.
  ///
  /// - `true` : fichier trouvé sur Drive ;
  /// - `false` : Drive joignable mais fichier absent ;
  /// - `null` : son hors bibliothèque ou Drive inaccessible.
  Future<bool?> probeRemotePresence(Sound sound) async {
    final libraryId = sound.libraryId;
    final rawRelativePath = sound.relativePath;
    if (libraryId == null ||
        rawRelativePath == null ||
        rawRelativePath.isEmpty) {
      return null;
    }

    // Renouvelle le token si besoin — évite un client périmé en cache mémoire.
    if (!await ensureDriveConnected()) return null;

    final client = await _ensureDriveClient();
    if (client == null) return null;

    final library = await _dataSource.getLibraryById(libraryId);
    if (library == null) return null;

    final relativePath =
        LibrarySoundPaths.normalizeRelativePath(rawRelativePath);
    try {
      return await _cacheManager
          .existsOnDrive(
            client: client,
            library: library,
            relativePath: relativePath,
            driveFileId: sound.driveFileId,
          )
          .timeout(const Duration(seconds: 10));
    } on DriveAuthException {
      await invalidateAuthSession();
      return null;
    } catch (e, stack) {
      AudioLoadLog.severe(
        'Sonde Drive échouée pour ${sound.displayName ?? sound.title}',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// Résout le chemin local jouable d'un son.
  ///
  /// - Son legacy (hors bibliothèque) : renvoie directement [Sound.filePath].
  /// - Son de bibliothèque en cache : renvoie le chemin local.
  /// - Son de bibliothèque non encore téléchargé avec [downloadIfNeeded] false :
  ///   lève [SoundNotAvailableLocallyException].
  /// - Son de bibliothèque non encore téléchargé avec [downloadIfNeeded] true :
  ///   télécharge depuis Drive et renvoie le chemin local.
  Future<String> resolvePlayablePath(
    Sound sound, {
    bool downloadIfNeeded = true,
  }) async {
    final libraryId = sound.libraryId;
    final rawRelativePath = sound.relativePath;

    if (libraryId != null) {
      if (rawRelativePath == null || rawRelativePath.isEmpty) {
        throw SoundNotAvailableLocallyException(isOffline: false);
      }

      final relativePath =
          LibrarySoundPaths.normalizeRelativePath(rawRelativePath);
      if (relativePath != rawRelativePath) {
        final libraryForUpdate = await _dataSource.getLibraryById(libraryId);
        if (libraryForUpdate != null) {
          await _soundDataSource.updateSoundRelativePath(
            soundId: sound.id,
            relativePath: relativePath,
            localPath: _cacheManager.localPathFor(libraryForUpdate, relativePath),
          );
        }
      }

      final library = await _dataSource.getLibraryById(libraryId);
      if (library == null) {
        throw SoundNotAvailableLocallyException(isOffline: false);
      }

      final localPath = _cacheManager.localPathFor(library, relativePath);
      final cachedPath =
          await PathUnicode.canonicalizeLocalPath(localPath) ?? localPath;
      final localFile = File(cachedPath);

      if (await localFile.exists()) {
        if (await isPlausibleAudioFile(localFile)) {
          final resolvedPath = p.normalize(localFile.absolute.path);
          await _soundDataSource.syncLibrarySoundLocalPath(sound.id, resolvedPath);
          // Fire-and-forget : le backfill (hash/waveform) est un best-effort qui
          // ne doit jamais bloquer la résolution du chemin — une simple sonde de
          // disponibilité (recherche) ne doit pas attendre un décodage natif lent
          // ou en échec sur potentiellement des centaines de sons.
          unawaited(_materializeSoundFileMetadataIfNeeded(sound, localFile));
          clearUnloadablePath(localPath);
          return resolvedPath;
        }

        final corruptSize = await localFile.length();
        AudioLoadLog.corruptCacheFile(path: localPath, bytes: corruptSize);
        try {
          await localFile.delete();
        } catch (_) {}
        markPathUnloadable(localPath);
        if (!downloadIfNeeded) {
          throw SoundNotAvailableLocallyException(isOffline: false);
        }
      }

      // Fichier absent du cache.
      var client = await _ensureDriveClient();
      if (client == null && downloadIfNeeded) {
        if (!await ensureDriveConnected()) {
          throw SoundNotAvailableLocallyException(isOffline: true);
        }
        client = await _ensureDriveClient();
      }
      if (client == null) {
        throw SoundNotAvailableLocallyException(isOffline: true);
      }
      if (!downloadIfNeeded) {
        throw SoundNotAvailableLocallyException(isOffline: false);
      }

      // Identité forte : si l'ID Drive est connu, on télécharge directement par
      // ID (robuste aux accents/renommages) sans réconciliation par nom.
      final driveFileId = sound.driveFileId;
      try {
        final reconciledPath = driveFileId != null
            ? relativePath
            : await _reconcileSoundRelativePathFromDrive(
                client: client,
                library: library,
                sound: sound,
                relativePath: relativePath,
              );

        final resolvedLocalPath = await _cacheManager.ensureCached(
          client: client,
          library: library,
          relativePath: reconciledPath,
          driveFileId: driveFileId,
        );
        final downloaded = File(resolvedLocalPath);
        if (!await downloaded.exists() ||
            !await isPlausibleAudioFile(downloaded)) {
          throw SoundNotAvailableLocallyException(isOffline: false);
        }
        final effectiveRelative = p
            .relative(
              p.normalize(resolvedLocalPath),
              from: p.normalize(library.localRootPath),
            )
            .replaceAll('\\', '/');
        if (effectiveRelative != relativePath) {
          await _soundDataSource.updateSoundRelativePath(
            soundId: sound.id,
            relativePath: effectiveRelative,
            localPath: resolvedLocalPath,
          );
        } else {
          await _soundDataSource.syncLibrarySoundLocalPath(
            sound.id,
            resolvedLocalPath,
          );
        }
        await _materializeSoundFileMetadataIfNeeded(sound, downloaded);
        clearUnloadablePath(resolvedLocalPath);
        return p.normalize(downloaded.absolute.path);
      } on DriveAuthException {
        // Token révoqué/expiré : libère la session (force un OAuth interactif au
        // prochain accès) et signale une indisponibilité, jamais un `missingFile`
        // — ce dernier passerait par `_blockSoundDriveRetry` côté sampler et
        // bloquerait le son *définitivement*, même après reconnexion.
        await invalidateAuthSession();
        throw SoundNotAvailableLocallyException(isOffline: true);
      }
    }

    final legacyPath =
        await PathUnicode.canonicalizeLocalPath(sound.filePath) ?? sound.filePath;
    final legacyFile = File(legacyPath);
    if (!await legacyFile.exists()) {
      throw SoundNotAvailableLocallyException(isOffline: false);
    }
    final length = await legacyFile.length();
    if (length <= 0) {
      throw SoundNotAvailableLocallyException(isOffline: false);
    }
    return p.normalize(legacyFile.absolute.path);
  }

  Future<void> _materializeSoundFileMetadataIfNeeded(
    Sound sound,
    File file,
  ) async {
    try {
      await _soundDataSource.materializeSoundFileMetadata(
        soundId: sound.id,
        file: file,
      );
    } catch (e) {
      debugPrint('Échec matérialisation métadonnées ${sound.title}: $e');
    }
  }

  /// Importe un fichier audio local dans une bibliothèque (upload Drive + cache)
  /// et renvoie son emplacement relatif + l'id Drive.
  Future<ImportedAudio> importAudioToLibrary({
    required Library library,
    required File source,
    required String relativePath,
  }) async {
    final client = _activeClient;
    if (client == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }
    return _cacheManager.importFile(
      client: client,
      library: library,
      source: source,
      relativePath: relativePath,
    );
  }

  /// Active ou désactive le téléchargement automatique des nouveaux fichiers.
  Future<void> setAutoDownload(Library library, {required bool value}) async {
    await _dataSource.setAutoDownload(library.id, value: value);
  }

  /// Compte les sons de la bibliothèque déjà disponibles hors ligne (fichier
  /// présent dans le cache local) sur le total. Sert d'indicateur d'état dans
  /// les paramètres — même critère de présence que [downloadAllLibraryAudio].
  Future<({int available, int total})> countDownloadedSounds(
    Library library,
  ) async {
    final sounds = await _soundDataSource.getSoundsForLibrary(library.id);
    var available = 0;
    for (final sound in sounds) {
      final relativePath = sound.relativePath;
      if (relativePath == null) continue;
      final localPath = _cacheManager.localPathFor(library, relativePath);
      if (await File(localPath).exists()) available++;
    }
    return (available: available, total: sounds.length);
  }

  /// Télécharge tous les fichiers audio non encore présents dans le cache local.
  ///
  /// La progression est publiée via [notifyListeners] ([libraryDownloadProgress])
  /// et aussi relayée à [onProgress] si fourni. L'annulation passe par
  /// [cancelLibraryDownload] (ou le [isCancelled] optionnel).
  ///
  /// Une seule passe tourne à la fois par bibliothèque : un appel concurrent (p.
  /// ex. bouton manuel pendant un pré-téléchargement auto) est un no-op — la passe
  /// en cours prendra les fichiers manquants.
  Future<int> downloadAllLibraryAudio({
    required Library library,
    void Function(IndexingProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!_downloadingLibraries.add(library.id)) return 0;
    _cancelledDownloads.remove(library.id);

    void report(IndexingProgress progress) {
      _publishDownloadProgress(library.id, progress);
      onProgress?.call(progress);
    }

    bool cancelled() =>
        isCancelled?.call() == true || _cancelledDownloads.contains(library.id);

    try {
      final client = await _ensureDriveClient();
      if (client == null) throw StateError('Bibliothèque non connectée à Drive');

      final sounds = await _soundDataSource.getSoundsForLibrary(library.id);
      final total = sounds.length;

      report(
        IndexingProgress(
          path: library.name,
          current: 0,
          total: total,
          isComplete: false,
        ),
      );

      var downloaded = 0;
      var failed = 0;
      var authExpired = false;

      for (var i = 0; i < sounds.length; i++) {
        if (cancelled()) break;

        final sound = sounds[i];
        final relativePath = sound.relativePath;

        try {
          if (relativePath == null) {
            throw StateError('Aucun chemin Drive associé');
          }
          final localPath = _cacheManager.localPathFor(library, relativePath);
          if (!await File(localPath).exists()) {
            final resolvedLocalPath = await _cacheManager.ensureCached(
              client: client,
              library: library,
              relativePath: relativePath,
              driveFileId: sound.driveFileId,
            );
            unawaited(
              _soundDataSource.syncLibrarySoundLocalPath(
                sound.id,
                resolvedLocalPath,
              ),
            );
            unawaited(
              _materializeSoundFileMetadataIfNeeded(
                sound,
                File(resolvedLocalPath),
              ),
            );
            downloaded++;
          }
        } on DriveAuthException {
          // Token révoqué/expiré : les fichiers suivants échoueraient de la même
          // façon — on arrête la passe plutôt que de les marquer un par un en échec.
          authExpired = true;
          await invalidateAuthSession();
          break;
        } catch (e) {
          failed++;
          debugPrint('Téléchargement échoué pour ${sound.title}: $e');
        }

        report(
          IndexingProgress(
            path: library.name,
            current: i + 1,
            total: total,
            isComplete: false,
          ),
        );
      }

      report(
        IndexingProgress(
          path: library.name,
          current: total,
          total: total,
          isComplete: true,
          error: authExpired
              ? 'Session Google expirée — reconnexion requise.'
              : (failed > 0 ? '$failed fichier(s) ignoré(s)' : null),
        ),
      );

      return downloaded;
    } finally {
      _downloadingLibraries.remove(library.id);
      _cancelledDownloads.remove(library.id);
    }
  }

  /// Indexe récursivement les fichiers audio d'un dossier Drive (bibliothèque).
  ///
  /// Passe par [_withDriveClient] : un token périmé en cours d'indexation est
  /// renouvelé silencieusement et l'opération réessayée (idempotente, upsert
  /// par driveFileId), sans forcer de reconnexion interactive.
  Future<DriveIndexResult> indexDriveFolder({
    required Library library,
    void Function(IndexingProgress)? onProgress,
  }) {
    final folderId = library.driveFolderId;
    if (folderId == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }
    return _withDriveClient(
      (client) => _indexDriveFolder(
        client: client,
        library: library,
        folderId: folderId,
        onProgress: onProgress,
      ),
    );
  }

  /// Élague les sons dont le fichier a disparu de Drive, d'après l'ensemble
  /// [presentDriveFileIds] d'un scan RÉUSSI, et évince leur fichier du cache
  /// local. Sert à redonner le dernier mot au scan live après un pull de
  /// snapshot : un snapshot distant périmé (poussé par un appareil qui n'a pas
  /// encore rescanné) peut réinsérer un son pointant vers un fichier déjà
  /// supprimé — cet appel le retire à nouveau.
  Future<void> pruneSoundsAbsentFromDrive({
    required Library library,
    required Set<String> presentDriveFileIds,
  }) async {
    final prunedPaths = await _soundDataSource.pruneLibrarySoundsAbsentFromDrive(
      libraryId: library.id,
      keptDriveFileIds: presentDriveFileIds,
    );
    // La ligne en base disparaît : le fichier téléchargé ne doit pas subsister.
    for (final relativePath in prunedPaths) {
      await _cacheManager.evictCachedFile(library, relativePath);
    }
  }

  Future<DriveIndexResult> _indexDriveFolder({
    required DriveClient client,
    required Library library,
    required String folderId,
    void Function(IndexingProgress)? onProgress,
  }) async {
    try {
      onProgress?.call(
        IndexingProgress(
          path: library.name,
          current: 0,
          total: 0,
          isComplete: false,
        ),
      );

      final audioFiles = await _collectDriveAudioFiles(
        client,
        folderId,
        '',
        sharedDriveId: library.sharedDriveId,
      );
      onProgress?.call(
        IndexingProgress(
          path: library.name,
          current: 0,
          total: audioFiles.length,
          isComplete: false,
        ),
      );

      var processedCount = 0;
      var indexedCount = 0;

      // Réaligne d'abord les chemins des sons legacy (sans driveFileId) dont le
      // fichier a bougé sur Drive : ainsi la boucle les réidentifie par chemin
      // et leur adopte l'ID Drive, au lieu de créer un doublon. L'identité forte
      // (driveFileId) prend ensuite le relais pour tous les scans suivants.
      await _reconcileOrphanedSoundPaths(
        library: library,
        driveRelativePaths: audioFiles.map((e) => e.relativePath).toList(),
      );

      // Nœuds dossier propriétaires (leurs fichiers directs) : unité
      // d'appartenance et de snapshot par-dossier. Résolus en UNE fois pour tout
      // le scan — ils se comptent en dizaines quand les fichiers se comptent en
      // milliers.
      final folderIds = await _dataSource.ensureFolders(
        libraryId: library.id,
        folders: [
          for (final audio in audioFiles)
            (
              driveFolderId: audio.folderDriveId,
              relativePath: audio.folderRelativePath,
            ),
        ],
      );

      // VUE PARTAGÉE : rattache CETTE bibliothèque aux nœuds, qu'elle en soit
      // propriétaire ou simplement « invitée » (son lien recouvre un dossier
      // possédé par une autre bibliothèque). Elle voit alors les sons partagés
      // sans les dupliquer.
      await _dataSource.ensureMemberships(
        libraryId: library.id,
        folderIds: folderIds.values,
      );

      // Indexation = MÉTADONNÉES uniquement. On ne télécharge JAMAIS le fichier
      // ici : sinon un gros dossier Drive (des milliers de sons) plafonne sur le
      // timeout de lancement (cf. AutoSyncCoordinator) et seuls les premiers
      // fichiers sont indexés. Le son est inséré avec `type = null` tant que le
      // fichier n'est pas local ; le téléchargement (et le backfill du type via
      // materializeSoundFileMetadata) est découplé, lancé en arrière-plan après
      // la boucle pour les bibliothèques en téléchargement auto.
      //
      // Écriture par LOTS : un lot = une transaction. Le tout-en-un serait plus
      // rapide encore, mais laisserait la progression figée sur une grosse
      // bibliothèque, et le mode d'échec reste celui d'avant (un scan
      // interrompu laisse un index partiel, que `AutoSyncCoordinator` traite
      // déjà en sautant le pull — cf. décision 0005).
      for (var start = 0; start < audioFiles.length; start += _indexBatchSize) {
        final end = math.min(start + _indexBatchSize, audioFiles.length);
        final chunk = audioFiles.sublist(start, end);

        final result = await _soundDataSource.syncLibrarySoundsFromDriveIndex(
          libraryId: library.id,
          entries: [
            for (final audio in chunk)
              DriveIndexEntry(
                relativePath: audio.relativePath,
                localPath:
                    _cacheManager.localPathFor(library, audio.relativePath),
                driveFileId: audio.driveFileId,
                driveMd5: audio.driveMd5,
                folderId: folderIds[audio.folderDriveId],
              ),
          ],
        );
        indexedCount += result.createdCount;

        // Édition « en place » sur Drive (contenu écrasé à ID constant) : le
        // fichier de cache local est périmé. La waveform et le contentHash ont
        // déjà été réinitialisés en base ; on évince le fichier pour forcer un
        // re-téléchargement. Celui-ci est découplé : il aura lieu en arrière-plan
        // (téléchargement auto ci-dessous, le fichier n'existant plus) ou à la
        // demande — jamais inline, pour ne pas plafonner l'indexation.
        for (final relativePath in result.contentChangedPaths) {
          await _cacheManager.evictCachedFile(library, relativePath);
        }

        processedCount = end;
        onProgress?.call(
          IndexingProgress(
            path: library.name,
            current: processedCount,
            total: audioFiles.length,
            isComplete: false,
          ),
        );
      }

      // Élagage symétrique de l'ajout : le scan ci-dessus est complet (listFolder
      // pagine intégralement) et n'a pu être atteint qu'après un parcours sans
      // erreur — sûr donc pour supprimer les sons dont le fichier a été retiré
      // directement sur Drive (identité forte absente du scan). Les sons legacy
      // sans driveFileId sont épargnés (réalignés par chemin, jamais élagués).
      final seenDriveIds = audioFiles.map((e) => e.driveFileId).toSet();
      await pruneSoundsAbsentFromDrive(
        library: library,
        presentDriveFileIds: seenDriveIds,
      );

      onProgress?.call(
        IndexingProgress(
          path: library.name,
          current: processedCount,
          total: audioFiles.length,
          isComplete: true,
          error: null,
        ),
      );

      // Métadonnées de TOUS les fichiers désormais en base (les sons sont visibles
      // immédiatement). Si la bibliothèque est en téléchargement auto, on
      // matérialise les fichiers en ARRIÈRE-PLAN — sans bloquer ni plafonner
      // l'indexation. Le type de chaque son est renseigné à la volée par
      // materializeSoundFileMetadata au fil des téléchargements.
      if (library.autoDownload) {
        unawaited(_prefetchLibraryAudioInBackground(library));
      }

      return DriveIndexResult(
        newFileCount: indexedCount,
        presentDriveFileIds: seenDriveIds,
      );
    } catch (e) {
      // Une erreur d'auth est gérée par [_withDriveClient] (renouvellement +
      // réessai) : ne pas afficher d'état d'erreur qui clignoterait avant le
      // réessai réussi.
      if (e is! DriveAuthException) {
        onProgress?.call(
          IndexingProgress(
            path: library.name,
            current: 0,
            total: 0,
            isComplete: true,
            error: e.toString(),
          ),
        );
      }
      rethrow;
    }
  }

  /// Pré-télécharge en arrière-plan les fichiers audio manquants d'une
  /// bibliothèque en téléchargement auto, après une indexation métadonnées-only.
  /// Best-effort : découplé de l'indexation (jamais inline), il ne doit ni la
  /// bloquer ni la faire échouer. Idempotent — [downloadAllLibraryAudio] saute
  /// les fichiers déjà présents et garantit une seule passe par bibliothèque.
  Future<void> _prefetchLibraryAudioInBackground(Library library) async {
    try {
      await downloadAllLibraryAudio(library: library);
    } catch (e) {
      debugPrint(
        'Pré-téléchargement en arrière-plan échoué (${library.name}): $e',
      );
    }
  }

  /// Retire une bibliothèque Drive indexée, ses sons et son cache local.
  Future<void> removeLibrary(Library library) async {
    await _soundDataSource.deleteSoundsByLibraryId(library.id);
    await _dataSource.deleteLibrary(library.id);

    try {
      final cacheDir = Directory(library.localRootPath);
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (_) {
      // Le cache local est optionnel à la suppression.
    }
  }

  /// Parcourt l'arborescence Drive et retourne tous les fichiers audio.
  ///
  /// Parcours en LARGEUR, un niveau à la fois, avec au plus [_driveListingConcurrency]
  /// listings en vol. La version antérieure descendait en profondeur d'abord et
  /// attendait chaque dossier avant de passer au suivant : sur une bibliothèque
  /// à quelques dizaines de dossiers, c'était autant d'allers-retours Drive mis
  /// bout à bout, soit l'essentiel du budget de lancement passé à attendre le
  /// réseau.
  ///
  /// **Complet ou rien.** Toute erreur de listing remonte et fait échouer le
  /// scan entier — propriété dont dépend l'élagage : `_indexDriveFolder` déduit
  /// « ce fichier n'existe plus sur Drive » de son absence du résultat, puis
  /// supprime le son ET son fichier de cache. Un parcours qui avalerait l'échec
  /// d'un dossier ne rendrait pas moins de sons : il en ferait supprimer. C'est
  /// aussi ce qui permet à `AutoSyncCoordinator` de sauter le pull d'une
  /// bibliothèque mal indexée (cf. décision 0005).
  Future<
      List<
          ({
            String relativePath,
            String driveFileId,
            String? driveMd5,
            String folderDriveId,
            String folderRelativePath,
          })>> _collectDriveAudioFiles(
    DriveClient client,
    String rootFolderId,
    String rootPrefix, {
    String? sharedDriveId,
  }) async {
    final results = <({
      String relativePath,
      String driveFileId,
      String? driveMd5,
      String folderDriveId,
      String folderRelativePath,
    })>[];

    var level = <({String id, String prefix})>[
      (id: rootFolderId, prefix: rootPrefix),
    ];

    while (level.isNotEmpty) {
      // Un listing par dossier du niveau, en parallèle borné. `listFolder` est
      // idempotent : son réessai sur erreur transitoire est déjà assuré par
      // `_guardRetry` côté client Drive (cf. décision 0012).
      final listings = await mapBounded(
        level,
        (folder) => client.listFolder(folder.id, sharedDriveId: sharedDriveId),
        concurrency: _driveListingConcurrency,
      );

      final next = <({String id, String prefix})>[];
      for (var i = 0; i < level.length; i++) {
        final folder = level[i];
        for (final child in listings[i]) {
          // Normalise le nom en NFC dès la source : Drive peut renvoyer du NFD
          // (fichiers créés sous macOS). On stocke toujours en NFC (titre,
          // relative_path, dossier, chemin local restent cohérents — cf.
          // LibrarySoundPaths).
          final childName = PathUnicode.toNfc(child.name);
          final childPath = folder.prefix.isEmpty
              ? childName
              : '${folder.prefix}/$childName';

          if (child.isFolder) {
            if (childName == '.stagecue') continue;
            next.add((id: child.id, prefix: childPath));
          } else if (isAudioFile(childName)) {
            // On conserve l'ID Drive du fichier (identité forte) ET celui de son
            // dossier parent direct (nœud propriétaire du modèle par-dossier).
            results.add((
              relativePath: childPath,
              driveFileId: child.id,
              driveMd5: child.md5Checksum,
              folderDriveId: folder.id,
              folderRelativePath: folder.prefix,
            ));
          }
        }
      }
      level = next;
    }

    return results;
  }

  /// Réaligne les chemins issus d'un snapshot sur les fichiers réellement
  /// présents sur Drive (déplacement, renommage, préfixe legacy `sounds/`).
  Future<void> _reconcileOrphanedSoundPaths({
    required Library library,
    required List<String> driveRelativePaths,
  }) async {
    final drivePaths = driveRelativePaths
        .map(LibrarySoundPaths.normalizeRelativePath)
        .toSet();
    final byBasename = <String, List<String>>{};
    for (final path in drivePaths) {
      final key = p.basename(path).toLowerCase();
      byBasename.putIfAbsent(key, () => []).add(path);
    }

    final sounds = await _soundDataSource.getSoundsForLibrary(library.id);
    for (final sound in sounds) {
      final raw = sound.relativePath;
      if (raw == null || raw.isEmpty) continue;

      final current = LibrarySoundPaths.normalizeRelativePath(raw);
      if (drivePaths.contains(current)) continue;

      final candidates = byBasename[p.basename(current).toLowerCase()];
      if (candidates == null || candidates.isEmpty) continue;

      final corrected =
          ReconcilePathMatcher.pickBestCandidate(current, candidates);
      if (corrected == null) continue;
      await _soundDataSource.updateSoundRelativePath(
        soundId: sound.id,
        relativePath: corrected,
        localPath: _cacheManager.localPathFor(library, corrected),
      );
    }
  }

  /// Réaligne le chemin relatif d'un son sur Drive avant téléchargement.
  Future<String> _reconcileSoundRelativePathFromDrive({
    required DriveClient client,
    required Library library,
    required Sound sound,
    required String relativePath,
  }) async {
    final remoteAtPath = await _resolveRemoteOnDrive(
      client: client,
      library: library,
      relativePath: relativePath,
    );
    if (remoteAtPath != null) return relativePath;

    final basename = p.basename(relativePath);
    final matches = await _collectDriveFilesByBasename(
      client: client,
      library: library,
      basename: basename,
    );
    if (matches.isEmpty) return relativePath;

    final corrected =
        ReconcilePathMatcher.pickBestCandidate(relativePath, matches);
    if (corrected == null || corrected == relativePath) return relativePath;

    await _soundDataSource.updateSoundRelativePath(
      soundId: sound.id,
      relativePath: corrected,
      localPath: _cacheManager.localPathFor(library, corrected),
    );
    return corrected;
  }

  Future<DriveFile?> _resolveRemoteOnDrive({
    required DriveClient client,
    required Library library,
    required String relativePath,
  }) async {
    final segments = relativePath.split('/');
    final rootId = library.driveFolderId;
    if (rootId == null) return null;
    var parentId = rootId;
    for (var i = 0; i < segments.length - 1; i++) {
      final folder = await _findDriveChildCaseInsensitive(
        client,
        parentId: parentId,
        name: segments[i],
        sharedDriveId: library.sharedDriveId,
      );
      if (folder == null || !folder.isFolder) return null;
      parentId = folder.id;
    }
    return _findDriveChildCaseInsensitive(
      client,
      parentId: parentId,
      name: segments.last,
      sharedDriveId: library.sharedDriveId,
    );
  }

  Future<DriveFile?> _findDriveChildCaseInsensitive(
    DriveClient client, {
    required String parentId,
    required String name,
    String? sharedDriveId,
  }) async {
    final exact = await client.findInFolder(
      parentId: parentId,
      name: name,
      sharedDriveId: sharedDriveId,
    );
    if (exact != null) return exact;

    final children = await client.listFolder(
      parentId,
      sharedDriveId: sharedDriveId,
    );
    for (final child in children) {
      if (PathUnicode.sameName(
        child.name.toLowerCase(),
        name.toLowerCase(),
      )) {
        return child;
      }
    }
    return null;
  }

  Future<List<String>> _collectDriveFilesByBasename({
    required DriveClient client,
    required Library library,
    required String basename,
  }) async {
    final folderId = library.driveFolderId;
    if (folderId == null) return const [];

    final matches = <String>[];
    final target = basename.toLowerCase();
    await _collectBasenameMatches(
      client,
      folderId,
      '',
      target,
      matches,
      sharedDriveId: library.sharedDriveId,
    );
    return matches;
  }

  Future<void> _collectBasenameMatches(
    DriveClient client,
    String folderId,
    String relativePrefix,
    String basenameLower,
    List<String> matches, {
    String? sharedDriveId,
  }) async {
    final children = await client.listFolder(
      folderId,
      sharedDriveId: sharedDriveId,
    );
    for (final child in children) {
      if (child.isFolder) {
        if (child.name == '.stagecue') continue;
        final subPrefix = relativePrefix.isEmpty
            ? child.name
            : '$relativePrefix/${child.name}';
        await _collectBasenameMatches(
          client,
          child.id,
          subPrefix,
          basenameLower,
          matches,
          sharedDriveId: sharedDriveId,
        );
      } else if (PathUnicode.sameName(
        child.name.toLowerCase(),
        basenameLower,
      )) {
        matches.add(
          relativePrefix.isEmpty ? child.name : '$relativePrefix/${child.name}',
        );
      }
    }
  }

  /// Ferme la session Drive et révoque la connexion du compte.
  Future<void> disconnect() async {
    _activeClient?.dispose();
    _activeClient = null;
    _requiresInteractiveReconnect = false;
    await _authenticator.signOut();
    _notifyDriveSessionChanged();
  }

  Future<String> _createLocalRoot() async {
    final docs = await getApplicationSupportDirectory();
    final dir = Directory(p.join(docs.path, 'libraries', const Uuid().v4()));
    await dir.create(recursive: true);
    return dir.path;
  }
}
