import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/audio/audio_file_validation.dart';
import '../../../../core/audio/audio_load_log.dart';
import '../../../../core/database/database.dart' as db;
import '../../../../core/sync/audio_cache_manager.dart';
import '../../../../core/sync/drive_account_profile.dart';
import '../../../../core/sync/drive_client.dart';
import '../../../../core/sync/drive_models.dart';
import '../../../../core/sync/google_drive_client.dart';
import '../../../../core/sync/saf_drive_owner_resolver.dart';
import '../../../../core/sync/library_sound_paths.dart';
import '../../../../core/sync/library_sync_service.dart';
import '../../../../core/sync/snapshot_store.dart';
import '../../../../core/utils/file_utils.dart' show isAudioFile;
import '../../domain/entities/library.dart';
import '../../domain/entities/sound.dart';
import '../datasources/local_library_datasource.dart';
import '../datasources/local_sound_datasource.dart';
import '../models/indexing_progress.dart';

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

/// Orchestration des bibliothèques portables : relie l'authentification Drive
/// (infra `core/sync`) à la persistance locale (table Libraries).
///
/// Conserve la session Drive active ([activeClient]) pour les opérations de
/// synchronisation ultérieures (snapshot DB, cache audio).
class LibraryRepository {
  final LocalLibraryDataSource _dataSource;
  final DriveAuthenticator _authenticator;
  final LibrarySyncService _syncService;
  final AudioCacheManager _cacheManager;
  final LocalSoundDataSource _soundDataSource;

  DriveClient? _activeClient;

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
    return LibraryRepository(
      LocalLibraryDataSource(database),
      GoogleDriveAuthenticator(),
      LibrarySyncService(DriftSnapshotStore(database)),
      AudioCacheManager(
        // Épingle les favoris : jamais évincés du cache, même peu lus.
        pinnedPaths: (library) =>
            soundDataSource.getFavoriteRelativePaths(library.id),
      ),
      soundDataSource,
    );
  }

  DriveClient? get activeClient => _activeClient;
  String? get connectedAccountEmail => _authenticator.accountEmail;
  DriveAccountProfile? get connectedAccountProfile =>
      isConnected ? _authenticator.accountProfile : null;
  bool get isConnected => _activeClient != null;

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
    if (_activeClient is GoogleDriveClient) {
      return _activeClient as GoogleDriveClient;
    }

    final client = await _authenticator.connectSilently();
    if (client is GoogleDriveClient) {
      _activeClient = client;
      return client;
    }

    return null;
  }

  Future<List<Library>> getLibraries() => _dataSource.getAllLibraries();

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
    final fresh = await _authenticator.connectSilently();
    if (fresh != null) {
      _activeClient?.dispose();
      _activeClient = fresh;
      return true;
    }

    // Le refresh silencieux a échoué (session révoquée ou inexistante).
    if (_activeClient != null) {
      _activeClient!.dispose();
      _activeClient = null;
    }

    final client = await _authenticator.connect();
    if (client == null) return false;
    _activeClient = client;
    return true;
  }

  /// Drives d'équipe accessibles par l'utilisateur connecté.
  Future<List<DriveSharedDrive>> listDriveSharedDrives() async {
    final client = _activeClient;
    if (client == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }
    return client.listSharedDrives();
  }

  /// Dossiers du filtre « Partagés avec moi ».
  Future<List<DriveFile>> listDriveSharedWithMeFolders() async {
    final client = _activeClient;
    if (client == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }
    final folders = await client.listSharedWithMeFolders();
    return folders
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
  }

  /// Liste les sous-dossiers d'un dossier Drive (triés par nom).
  Future<List<DriveFile>> listDriveChildFolders(
    String parentId, {
    String? sharedDriveId,
  }) async {
    final client = _activeClient;
    if (client == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }

    final children = await client.listFolder(
      parentId,
      sharedDriveId: sharedDriveId,
    );
    return children.where((file) => file.isFolder).toList()
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
  }

  /// Lie un dossier Drive existant (sans le créer) et enregistre la bibliothèque.
  Future<Library> linkDriveFolder({
    required String driveFolderId,
    required String name,
    String? drivePath,
    String? ownerEmail,
    String? sharedDriveId,
  }) async {
    final client = _activeClient;
    if (client == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }

    final folder = await client.getFile(
      driveFolderId,
      sharedDriveId: sharedDriveId,
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
    );
  }

  /// Lance le consentement OAuth puis crée une bibliothèque : dossier Drive
  /// (réutilisé s'il existe déjà) + dossier de cache local + ligne en base.
  /// Retourne null si l'utilisateur annule la connexion.
  Future<Library?> connectAndCreateLibrary({required String name}) async {
    final client = await _authenticator.connect();
    if (client == null) return null;
    _activeClient = client;

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
    );
  }

  /// Reconnexion silencieuse au démarrage (réutilise une session existante).
  /// Retourne true si une session a pu être rétablie.
  Future<bool> reconnectSilently() async {
    final client = await _authenticator.connectSilently();
    if (client == null) return false;
    _activeClient = client;
    await refreshLibraryOwnerEmails();
    return true;
  }

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
        debugPrint(
          'Refresh propriétaire Drive échoué pour ${library.name}: $e',
        );
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
  }) async {
    final client = _activeClient;
    final folderId = library.driveFolderId;
    if (client == null || folderId == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }
    final outcome = await _syncService.push(
      client: client,
      libraryId: library.id,
      libraryFolderId: folderId,
      knownRevision: overrideKnownRevision ?? library.lastSyncedRevision,
    );
    if (outcome is PushSuccess) {
      await _dataSource.updateSyncState(
        id: library.id,
        lastSyncedRevision: outcome.revision,
        lastSyncedAt: DateTime.now(),
      );
    }
    return outcome;
  }

  /// Télécharge et fusionne le snapshot distant de [library] s'il est plus récent.
  Future<PullOutcome> pullLibrary(Library library) async {
    final client = _activeClient;
    final folderId = library.driveFolderId;
    if (client == null || folderId == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }
    final outcome = await _syncService.pull(
      client: client,
      libraryId: library.id,
      libraryFolderId: folderId,
      knownRevision: library.lastSyncedRevision,
    );
    if (outcome is PullStaged) {
      await _dataSource.updateSyncState(
        id: library.id,
        lastSyncedRevision: outcome.revision,
        lastSyncedAt: DateTime.now(),
      );
    }
    return outcome;
  }

  Future<Library?> getLibraryById(int id) => _dataSource.getLibraryById(id);

  /// Indique si le dossier Drive possède déjà un snapshot `.stagecue/library.db`.
  Future<bool> hasRemoteSnapshot(Library library) async {
    final client = _activeClient;
    final folderId = library.driveFolderId;
    if (client == null || folderId == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }
    return _syncService.hasRemoteSnapshot(
      client: client,
      libraryFolderId: folderId,
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
      indexedNewFiles: indexed,
    );
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
      final localFile = File(localPath);

      if (await localFile.exists()) {
        if (await isPlausibleAudioFile(localFile)) {
          await _soundDataSource.syncLibrarySoundLocalPath(sound.id, localPath);
        if (sound.contentHash == null) {
          await _refreshSoundMetadata(sound, localFile);
        }
        clearUnloadablePath(localPath);
        return p.normalize(localFile.absolute.path);
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

      final resolvedLocalPath = await _cacheManager.ensureCached(
        client: client,
        library: library,
        relativePath: relativePath,
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
      await _refreshSoundMetadata(sound, downloaded);
      clearUnloadablePath(resolvedLocalPath);
      return p.normalize(downloaded.absolute.path);
    }

    final legacyFile = File(sound.filePath);
    if (!await legacyFile.exists()) {
      throw SoundNotAvailableLocallyException(isOffline: false);
    }
    final length = await legacyFile.length();
    if (length <= 0) {
      throw SoundNotAvailableLocallyException(isOffline: false);
    }
    return p.normalize(legacyFile.absolute.path);
  }

  Future<void> _refreshSoundMetadata(Sound sound, File file) async {
    try {
      await _soundDataSource.refreshSoundMetadata(soundId: sound.id, file: file);
    } catch (e) {
      debugPrint('Échec mise à jour métadonnées ${sound.title}: $e');
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

  /// Télécharge tous les fichiers audio non encore présents dans le cache local.
  ///
  /// Appelle [onProgress] après chaque fichier. [isCancelled] permet
  /// d'interrompre proprement entre deux téléchargements.
  Future<int> downloadAllLibraryAudio({
    required Library library,
    void Function(IndexingProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final client = await _ensureDriveClient();
    if (client == null) throw StateError('Bibliothèque non connectée à Drive');

    final sounds = await _soundDataSource.getSoundsForLibrary(library.id);
    final total = sounds.length;

    onProgress?.call(
      IndexingProgress(
        path: library.name,
        current: 0,
        total: total,
        isComplete: false,
      ),
    );

    var downloaded = 0;
    var failed = 0;

    for (var i = 0; i < sounds.length; i++) {
      if (isCancelled?.call() == true) break;

      final sound = sounds[i];
      final relativePath = sound.relativePath!;
      final localPath = _cacheManager.localPathFor(library, relativePath);

      try {
        if (!await File(localPath).exists()) {
          await _cacheManager.ensureCached(
            client: client,
            library: library,
            relativePath: relativePath,
          );
          unawaited(
            _soundDataSource.syncLibrarySoundLocalPath(sound.id, localPath),
          );
          if (sound.contentHash == null) {
            unawaited(_refreshSoundMetadata(sound, File(localPath)));
          }
          downloaded++;
        }
      } catch (e) {
        failed++;
        debugPrint('Téléchargement échoué pour ${sound.title}: $e');
      }

      onProgress?.call(
        IndexingProgress(
          path: library.name,
          current: i + 1,
          total: total,
          isComplete: false,
        ),
      );
    }

    onProgress?.call(
      IndexingProgress(
        path: library.name,
        current: total,
        total: total,
        isComplete: true,
        error: failed > 0 ? '$failed fichier(s) ignoré(s)' : null,
      ),
    );

    return downloaded;
  }

  /// Indexe récursivement les fichiers audio d'un dossier Drive (bibliothèque).
  Future<int> indexDriveFolder({
    required Library library,
    void Function(IndexingProgress)? onProgress,
  }) async {
    final client = _activeClient;
    final folderId = library.driveFolderId;
    if (client == null || folderId == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }

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

      for (final audio in audioFiles) {
        processedCount++;
        final localPath = _cacheManager.localPathFor(library, audio.relativePath);
        final isNew = await _soundDataSource.syncLibrarySoundFromDriveIndex(
          libraryId: library.id,
          relativePath: audio.relativePath,
          localPath: localPath,
        );
        if (isNew) indexedCount++;

        onProgress?.call(
          IndexingProgress(
            path: library.name,
            current: processedCount,
            total: audioFiles.length,
            isComplete: false,
          ),
        );
      }

      await _reconcileOrphanedSoundPaths(
        library: library,
        driveRelativePaths: audioFiles.map((e) => e.relativePath).toList(),
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

      return indexedCount;
    } catch (e) {
      onProgress?.call(
        IndexingProgress(
          path: library.name,
          current: 0,
          total: 0,
          isComplete: true,
          error: e.toString(),
        ),
      );
      rethrow;
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

  Future<List<({String relativePath})>> _collectDriveAudioFiles(
    DriveClient client,
    String folderId,
    String relativePrefix, {
    String? sharedDriveId,
  }) async {
    final results = <({String relativePath})>[];
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
        results.addAll(
          await _collectDriveAudioFiles(
            client,
            child.id,
            subPrefix,
            sharedDriveId: sharedDriveId,
          ),
        );
      } else if (isAudioFile(child.name)) {
        final relativePath = relativePrefix.isEmpty
            ? child.name
            : '$relativePrefix/${child.name}';
        results.add((relativePath: relativePath));
      }
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
      if (candidates == null || candidates.length != 1) continue;

      final corrected = candidates.single;
      await _soundDataSource.updateSoundRelativePath(
        soundId: sound.id,
        relativePath: corrected,
        localPath: _cacheManager.localPathFor(library, corrected),
      );
    }
  }

  /// Ferme la session Drive et révoque la connexion du compte.
  Future<void> disconnect() async {
    _activeClient?.dispose();
    _activeClient = null;
    await _authenticator.signOut();
  }

  Future<String> _createLocalRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'libraries', const Uuid().v4()));
    await dir.create(recursive: true);
    return dir.path;
  }
}
