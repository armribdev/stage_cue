import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'drive_client.dart';
import 'drive_models.dart';
import 'snapshot_store.dart';
import 'sync_manifest.dart';

const String _stageFolderName = '.stagecue';
const String _dbFileName = 'library.db';
const String _manifestFileName = 'manifest.json';
const String _sqliteMimeType = 'application/x-sqlite3';
const String _jsonMimeType = 'application/json';

/// Résultat d'un push de snapshot.
sealed class PushOutcome {
  const PushOutcome();
}

/// Push réussi : le snapshot et le manifest ont été poussés à [revision].
class PushSuccess extends PushOutcome {
  final int revision;
  const PushSuccess(this.revision);
}

/// Conflit : la révision distante a changé depuis la dernière synchro connue
/// (un autre appareil a poussé). À résoudre avant de réécraser (cf. étape 5).
class PushConflict extends PushOutcome {
  final SyncManifest remote;
  const PushConflict(this.remote);
}

/// Résultat d'un pull de snapshot.
sealed class PullOutcome {
  const PullOutcome();
}

/// Rien de plus récent côté distant : la base locale est déjà à jour.
class PullUpToDate extends PullOutcome {
  const PullUpToDate();
}

/// Un snapshot plus récent a été téléchargé et fusionné en-place dans la base.
class PullStaged extends PullOutcome {
  final int revision;
  const PullStaged(this.revision);
}

/// Orchestration push/pull du snapshot DB d'une bibliothèque, par-dessus un
/// [DriveClient] et un [SnapshotStore]. Aucune dépendance directe au SDK Google
/// ni à la base : entièrement testable avec des mocks.
class LibrarySyncService {
  final SnapshotStore _snapshotStore;
  final String? _deviceIdOverride;
  final Directory? _tempDirOverride;

  LibrarySyncService(
    this._snapshotStore, {
    String? deviceId,
    Directory? tempDir,
  })  : _deviceIdOverride = deviceId,
        _tempDirOverride = tempDir;

  /// Pousse l'état local vers Drive si aucun conflit de révision n'est détecté.
  Future<PushOutcome> push({
    required DriveClient client,
    required int libraryId,
    required String libraryFolderId,
    required int knownRevision,
    bool force = false,
  }) {
    return _pushSnapshot(
      client: client,
      remoteFolderId: libraryFolderId,
      knownRevision: knownRevision,
      force: force,
      exportSnapshot: (path) =>
          _snapshotStore.exportLibrarySnapshot(libraryId, path),
    );
  }

  /// Variante par-dossier : pousse le snapshot du nœud [folderId] dans le
  /// `.stagecue` co-localisé au dossier Drive [folderDriveId]. Chaque dossier a
  /// sa propre révision → emplacement de BDD déterministe et partagé.
  Future<PushOutcome> pushFolder({
    required DriveClient client,
    required int folderId,
    required String folderDriveId,
    required int knownRevision,
    bool force = false,
  }) {
    return _pushSnapshot(
      client: client,
      remoteFolderId: folderDriveId,
      knownRevision: knownRevision,
      force: force,
      exportSnapshot: (path) =>
          _snapshotStore.exportFolderSnapshot(folderId, path),
    );
  }

  Future<PushOutcome> _pushSnapshot({
    required DriveClient client,
    required String remoteFolderId,
    required int knownRevision,
    required Future<int> Function(String path) exportSnapshot,
    bool force = false,
  }) async {
    final stageId = await _ensureStageFolder(client, remoteFolderId);

    final remoteManifest = await _readManifest(client, stageId);
    // `force` (résolution de conflit « garder le local ») : on adopte la
    // révision distante pour l'écraser au lieu de signaler un conflit.
    if (!force &&
        remoteManifest != null &&
        remoteManifest.revision != knownRevision) {
      return PushConflict(remoteManifest);
    }

    final tempDir = await _resolveTempDir();
    final snapshotPath = p.join(tempDir.path, 'library-push.db');
    final length = await exportSnapshot(snapshotPath);

    try {
      await _putFile(
        client: client,
        parentId: stageId,
        name: _dbFileName,
        data: File(snapshotPath).openRead(),
        length: length,
        mimeType: _sqliteMimeType,
      );

      final newRevision = (remoteManifest?.revision ?? knownRevision) + 1;
      final manifest = SyncManifest(
        revision: newRevision,
        deviceId: await _resolveDeviceId(),
        updatedAt: DateTime.now().toUtc(),
        schemaVersion: _snapshotStore.schemaVersion,
      );
      await _writeManifest(client, stageId, manifest);
      return PushSuccess(newRevision);
    } finally {
      await _safeDelete(snapshotPath);
    }
  }

  /// Indique si un snapshot BDD (`.stagecue/library.db`) existe sur Drive.
  Future<bool> hasRemoteSnapshot({
    required DriveClient client,
    required String libraryFolderId,
  }) async {
    final stage = await _findInFolder(client, libraryFolderId, _stageFolderName);
    if (stage == null) return false;
    final dbFile = await client.findInFolder(
      parentId: stage.id,
      name: _dbFileName,
    );
    return dbFile != null;
  }

  /// Télécharge le snapshot distant s'il est plus récent et le fusionne
  /// immédiatement dans la base locale (périmètre : [libraryId]).
  Future<PullOutcome> pull({
    required DriveClient client,
    required int libraryId,
    required String libraryFolderId,
    required int knownRevision,
  }) {
    return _pullSnapshot(
      client: client,
      remoteFolderId: libraryFolderId,
      knownRevision: knownRevision,
      mergeSnapshot: (path) => _snapshotStore.mergeLibrarySnapshot(
        libraryId,
        path,
        driveFolderId: libraryFolderId,
      ),
    );
  }

  /// Variante par-dossier : tire le snapshot du `.stagecue` co-localisé au
  /// dossier Drive [folderDriveId] et le fusionne dans le nœud [folderId].
  Future<PullOutcome> pullFolder({
    required DriveClient client,
    required int folderId,
    required String folderDriveId,
    required int knownRevision,
  }) {
    return _pullSnapshot(
      client: client,
      remoteFolderId: folderDriveId,
      knownRevision: knownRevision,
      mergeSnapshot: (path) =>
          _snapshotStore.mergeFolderSnapshot(folderId, path),
    );
  }

  Future<PullOutcome> _pullSnapshot({
    required DriveClient client,
    required String remoteFolderId,
    required int knownRevision,
    required Future<void> Function(String path) mergeSnapshot,
  }) async {
    final stage = await _findInFolder(client, remoteFolderId, _stageFolderName);
    if (stage == null) return const PullUpToDate();

    final remoteManifest = await _readManifest(client, stage.id);
    if (remoteManifest == null || remoteManifest.revision <= knownRevision) {
      return const PullUpToDate();
    }

    final dbFile = await client.findInFolder(
      parentId: stage.id,
      name: _dbFileName,
    );
    if (dbFile == null) return const PullUpToDate();

    final tempDir = await _resolveTempDir();
    final downloadPath = p.join(tempDir.path, 'library-pull.db');
    try {
      await client.downloadToFile(
        fileId: dbFile.id,
        destinationPath: downloadPath,
      );
      await mergeSnapshot(downloadPath);
      return PullStaged(remoteManifest.revision);
    } finally {
      await _safeDelete(downloadPath);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<String> _ensureStageFolder(
    DriveClient client,
    String libraryFolderId,
  ) async {
    final existing = await _findInFolder(
      client,
      libraryFolderId,
      _stageFolderName,
    );
    if (existing != null) return existing.id;
    final created = await client.createFolder(
      name: _stageFolderName,
      parentId: libraryFolderId,
    );
    return created.id;
  }

  Future<DriveFile?> _findInFolder(
    DriveClient client,
    String parentId,
    String name,
  ) =>
      client.findInFolder(parentId: parentId, name: name);

  Future<SyncManifest?> _readManifest(DriveClient client, String stageId) async {
    final file = await client.findInFolder(
      parentId: stageId,
      name: _manifestFileName,
    );
    if (file == null) return null;
    final bytes = await client.downloadBytes(file.id);
    return SyncManifest.decode(utf8.decode(bytes));
  }

  Future<void> _writeManifest(
    DriveClient client,
    String stageId,
    SyncManifest manifest,
  ) async {
    final bytes = utf8.encode(manifest.encode());
    await _putFile(
      client: client,
      parentId: stageId,
      name: _manifestFileName,
      data: Stream.value(bytes),
      length: bytes.length,
      mimeType: _jsonMimeType,
    );
  }

  /// Crée le fichier ou remplace son contenu s'il existe déjà.
  Future<void> _putFile({
    required DriveClient client,
    required String parentId,
    required String name,
    required Stream<List<int>> data,
    required int length,
    required String mimeType,
  }) async {
    final existing = await client.findInFolder(parentId: parentId, name: name);
    if (existing != null) {
      await client.updateFileContent(
        fileId: existing.id,
        data: data,
        length: length,
        mimeType: mimeType,
      );
    } else {
      await client.uploadFile(
        name: name,
        parentId: parentId,
        data: data,
        length: length,
        mimeType: mimeType,
      );
    }
  }

  Future<Directory> _resolveTempDir() async {
    if (_tempDirOverride != null) return _tempDirOverride;
    return getTemporaryDirectory();
  }

  /// Identifiant d'appareil stable, persisté dans un fichier sous documents.
  Future<String> _resolveDeviceId() async {
    if (_deviceIdOverride != null) return _deviceIdOverride;
    final docs = await getApplicationSupportDirectory();
    final file = File(p.join(docs.path, 'device_id.txt'));
    if (await file.exists()) {
      final value = (await file.readAsString()).trim();
      if (value.isNotEmpty) return value;
    }
    final id = const Uuid().v4();
    await file.writeAsString(id);
    return id;
  }

  Future<void> _safeDelete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Nettoyage best-effort : un fichier temporaire résiduel n'est pas grave.
    }
  }
}
