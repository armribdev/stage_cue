import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database.dart' as db;
import '../../../../core/sync/audio_cache_manager.dart';
import '../../../../core/sync/drive_client.dart';
import '../../../../core/sync/drive_models.dart';
import '../../../../core/sync/google_drive_client.dart';
import '../../../../core/sync/library_sync_service.dart';
import '../../../../core/sync/snapshot_store.dart';
import '../../domain/entities/library.dart';
import '../../domain/entities/sound.dart';
import '../datasources/local_library_datasource.dart';
import '../datasources/local_sound_datasource.dart';

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
    return LibraryRepository(
      LocalLibraryDataSource(database),
      GoogleDriveAuthenticator(),
      LibrarySyncService(DriftSnapshotStore(database)),
      AudioCacheManager(),
      LocalSoundDataSource(database),
    );
  }

  DriveClient? get activeClient => _activeClient;
  String? get connectedAccountEmail => _authenticator.accountEmail;
  bool get isConnected => _activeClient != null;

  Future<List<Library>> getLibraries() => _dataSource.getAllLibraries();

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
    );
  }

  /// Reconnexion silencieuse au démarrage (réutilise une session existante).
  /// Retourne true si une session a pu être rétablie.
  Future<bool> reconnectSilently() async {
    final client = await _authenticator.connectSilently();
    if (client == null) return false;
    _activeClient = client;
    return true;
  }

  /// Liste le contenu distant d'une bibliothèque connectée à Drive.
  Future<List<DriveFile>> listLibraryContents(Library library) async {
    final client = _activeClient;
    final folderId = library.driveFolderId;
    if (client == null || folderId == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }
    return client.listFolder(folderId);
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

  /// Télécharge le snapshot distant de [library] s'il est plus récent. Un
  /// snapshot tiré est appliqué au prochain démarrage de l'application.
  Future<PullOutcome> pullLibrary(Library library) async {
    final client = _activeClient;
    final folderId = library.driveFolderId;
    if (client == null || folderId == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }
    final outcome = await _syncService.pull(
      client: client,
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

  /// Résout le chemin local jouable d'un son.
  ///
  /// - Son legacy (hors bibliothèque) : renvoie directement [Sound.filePath].
  /// - Son de bibliothèque : matérialise le fichier dans le cache (download
  ///   Drive à la demande) et renvoie le chemin local. Hors-ligne, renvoie le
  ///   fichier en cache s'il existe, sinon lève une erreur.
  Future<String> resolvePlayablePath(Sound sound) async {
    final libraryId = sound.libraryId;
    final relativePath = sound.relativePath;
    if (libraryId == null || relativePath == null) {
      return sound.filePath;
    }

    final library = await _dataSource.getLibraryById(libraryId);
    if (library == null) return sound.filePath;

    final client = _activeClient;
    if (client == null) {
      // Hors-ligne : on ne peut servir que ce qui est déjà en cache.
      final localPath = _cacheManager.localPathFor(library, relativePath);
      if (await File(localPath).exists()) return localPath;
      throw StateError(
        'Son indisponible hors-ligne (non mis en cache) : $relativePath',
      );
    }

    return _cacheManager.ensureCached(
      client: client,
      library: library,
      relativePath: relativePath,
    );
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

  /// Ajoute des fichiers audio à une bibliothèque : upload Drive + cache local +
  /// indexation en sons de bibliothèque (synchronisables). Retourne le nombre de
  /// nouveaux sons créés. [onProgress] rapporte l'avancement (index, total).
  Future<int> addSoundsToLibrary({
    required Library library,
    required List<File> sources,
    void Function(int current, int total)? onProgress,
  }) async {
    if (_activeClient == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }

    var created = 0;
    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      onProgress?.call(i + 1, sources.length);

      // Chemin portable sous `sounds/`, basé sur le nom de fichier.
      final relativePath = 'sounds/${p.basename(source.path)}';
      final imported = await importAudioToLibrary(
        library: library,
        source: source,
        relativePath: relativePath,
      );

      // Le fichier est désormais matérialisé dans le cache local.
      final localPath = _cacheManager.localPathFor(
        library,
        imported.relativePath,
      );
      final isNew = await _soundDataSource.indexLibraryAudioFile(
        File(localPath),
        libraryId: library.id,
        relativePath: imported.relativePath,
      );
      if (isNew) created++;
    }
    return created;
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
