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
import '../../../../core/sync/sync_log.dart';
import '../../../../core/utils/bounded_concurrency.dart';
import '../../../../core/utils/file_utils.dart' show isAudioFile;
import '../../../../core/utils/path_unicode.dart';
import '../../domain/entities/library.dart';
import '../../domain/entities/sound.dart';
import '../datasources/local_library_datasource.dart';
import '../datasources/local_sound_datasource.dart';
import '../models/indexing_progress.dart';

part 'drive_sync_outcome.dart';
part 'library_repository_results.dart';
part 'library_repository_drive_session.dart';
part 'library_repository_libraries.dart';
part 'library_repository_push_pull.dart';
part 'library_repository_playback.dart';
part 'library_repository_downloads.dart';
part 'library_repository_drive_changes.dart';
part 'library_repository_drive_index.dart';
part 'library_repository_path_reconcile.dart';

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

/// Téléchargements simultanés lors d'une passe de masse (« Tout télécharger »,
/// pré-téléchargement auto).
///
/// Plus bas que la concurrence de listing : un listing est borné par la latence
/// (le réseau dort en l'attendant), un téléchargement par la bande passante —
/// au-delà d'un certain point on ne fait que se partager le même tuyau, en
/// ajoutant des connexions et du risque de quota. Ces 4 s'ajoutent par ailleurs
/// aux 2 de `DownloadQueue`, qui sert les pads déclenchés depuis l'UI.
const int _bulkDownloadConcurrency = 4;

/// Intervalle maximal entre deux scans COMPLETS de l'arborescence Drive.
///
/// Le parcours incrémental n'élague que ce que Drive lui signale explicitement :
/// il ne peut pas constater qu'il a manqué quelque chose. Ce rescan périodique
/// borne la dérive accumulée — c'est le filet, pas l'exception.
const Duration _fullScanInterval = Duration(days: 7);

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
  ///
  /// Les trois paramètres optionnels ne servent qu'aux tests : ils permettent
  /// de provoquer une éviction LRU sans remplir un vrai disque, et donc de
  /// vérifier que l'épinglage construit ici est réellement branché (mode de
  /// régression signalé par la décision 0010). En production, aucun appelant ne
  /// les fournit et les défauts d'[AudioCacheManager] s'appliquent.
  factory LibraryRepository.fromDatabase(
    db.AppDatabase database, {
    @visibleForTesting
    int minFreeDiskBytes = AudioCacheManager.kDefaultMinFreeDiskBytes,
    @visibleForTesting
    Future<int?> Function(String rootPath)? availableDiskBytes,
    @visibleForTesting int Function()? clock,
  }) {
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
        minFreeDiskBytes: minFreeDiskBytes,
        availableDiskBytes: availableDiskBytes,
        clock: clock,
        // Épinglés, donc jamais évincés : les favoris (peu lus mais voulus sous
        // la main) ET les sons du plateau actif. La « protection implicite par
        // récence » ne suffit pas — un téléchargement massif rebat l'ordre LRU
        // et rend les sons de la scène en cours plus anciens que le reste.
        pinnedPaths: (library) async {
          final favorites = await soundDataSource.getFavoriteRelativePaths(
            library.id,
          );
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

  /// Cache audio assemblé par [fromDatabase].
  ///
  /// Exposé pour que les tests puissent vérifier que son épinglage anti-éviction
  /// est réellement branché : sans callback, l'éviction redevient purement LRU
  /// *sans avertissement* (décision 0010). Ne pas s'en servir en production —
  /// le repository est la seule façade attendue sur le cache.
  @visibleForTesting
  AudioCacheManager get cacheManager => _cacheManager;

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

  Future<List<Library>> getLibraries() => _dataSource.getAllLibraries();

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

  /// Token expiré ou révoqué : libère la session et exige un OAuth interactif.
  Future<void> invalidateAuthSession() async {
    _requiresInteractiveReconnect = true;
    await releaseDriveSession();
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

  /// Tente d'appliquer les changements Drive survenus depuis le dernier passage,
  /// sans reparcourir l'arborescence.
  ///
  /// Retourne [DriveSyncNeedsFullScan] dès que le delta n'est pas exploitable
  /// avec certitude — l'appelant doit alors passer par [indexDriveFolder]. Le
  /// déséquilibre est VOULU : un scan complet de trop coûte quelques secondes,
  /// un delta appliqué de travers coûte des sons.
  ///
  /// Exception : la **création** d'un dossier dont le parent est déjà dans le
  /// cadre local est greffée par un listing ciblé du sous-arbre (pas de scan
  /// complet, pas d'élagage). Renommage / déplacement / suppression d'un
  /// dossier connu restent en [DriveSyncNeedsFullScan].
  ///
  /// Cette méthode n'appelle JAMAIS [pruneSoundsAbsentFromDrive] : elle ne
  /// connaît pas l'ensemble des fichiers présents sur Drive, seulement les
  /// disparitions que Drive lui a signalées. Élaguer par différence d'ensembles
  /// depuis un delta reviendrait à supprimer tout ce qui n'a pas bougé.
  Future<DriveSyncOutcome> applyDriveChanges({required Library library}) {
    if (library.driveFolderId == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }
    return _withDriveClient(
      (client) => _applyDriveChanges(client: client, library: library),
    );
  }

  /// Élague les sons dont le fichier a disparu de Drive, d'après l'ensemble
  /// [presentDriveFileIds] d'un scan RÉUSSI, et évince leur fichier du cache
  /// local. Sert à redonner le dernier mot au scan live après un pull de
  /// snapshot : un snapshot distant périmé (poussé par un appareil qui n'a pas
  /// encore rescanné) peut réinsérer un son pointant vers un fichier déjà
  /// supprimé — cet appel le retire à nouveau.
  /// Retourne le nombre de sons élagués — utile au bilan de fin d'indexation,
  /// où c'est le chiffre à surveiller : un élagage inattendu est le symptôme d'un
  /// scan qui a vu moins que la réalité.
  Future<int> pruneSoundsAbsentFromDrive({
    required Library library,
    required Set<String> presentDriveFileIds,
  }) async {
    final prunedPaths = await _soundDataSource
        .pruneLibrarySoundsAbsentFromDrive(
          libraryId: library.id,
          keptDriveFileIds: presentDriveFileIds,
        );
    // La ligne en base disparaît : le fichier téléchargé ne doit pas subsister.
    for (final relativePath in prunedPaths) {
      await _cacheManager.evictCachedFile(library, relativePath);
    }
    if (prunedPaths.isNotEmpty) {
      SyncLog.trace('${library.name} : élagués — ${prunedPaths.join(', ')}');
    }
    return prunedPaths.length;
  }
}
