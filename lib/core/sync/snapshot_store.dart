import '../database/database.dart' as db;
import 'library_snapshot_store.dart';

/// Abstraction d'export/import d'un snapshot de bibliothèque Drive.
abstract class SnapshotStore {
  /// Version de schéma courante (inscrite dans le manifest).
  int get schemaVersion;

  /// Exporte les données liées à [libraryId] vers [targetPath].
  Future<int> exportLibrarySnapshot(int libraryId, String targetPath);

  /// Fusionne un snapshot distant dans la base locale pour [libraryId].
  Future<void> mergeLibrarySnapshot(
    int libraryId,
    String sourcePath, {
    String? driveFolderId,
  });

  /// Exporte les sons (chemins folder-relative) du nœud dossier [folderId].
  Future<int> exportFolderSnapshot(int folderId, String targetPath);

  /// Fusionne (upsert par driveFileId) le snapshot du dossier [folderId].
  Future<void> mergeFolderSnapshot(int folderId, String sourcePath);
}

/// Implémentation adossée à la base Drift de l'application.
class DriftSnapshotStore implements SnapshotStore {
  final db.AppDatabase _database;
  late final LibrarySnapshotStore _libraryStore;

  DriftSnapshotStore(this._database) {
    _libraryStore = LibrarySnapshotStore(_database);
  }

  @override
  int get schemaVersion => _database.schemaVersion;

  @override
  Future<int> exportLibrarySnapshot(int libraryId, String targetPath) {
    return _libraryStore.exportLibrarySnapshot(libraryId, targetPath);
  }

  @override
  Future<void> mergeLibrarySnapshot(
    int libraryId,
    String sourcePath, {
    String? driveFolderId,
  }) {
    return _libraryStore.mergeLibrarySnapshot(
      libraryId,
      sourcePath,
      driveFolderId: driveFolderId,
    );
  }

  @override
  Future<int> exportFolderSnapshot(int folderId, String targetPath) {
    return _libraryStore.exportFolderSnapshot(folderId, targetPath);
  }

  @override
  Future<void> mergeFolderSnapshot(int folderId, String sourcePath) {
    return _libraryStore.mergeFolderSnapshot(folderId, sourcePath);
  }
}
