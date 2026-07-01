import 'package:drift/drift.dart';
import '../../../../core/database/database.dart' as db;
import '../../domain/entities/library.dart' as domain;
import '../models/library_model.dart';

/// Source de données locale pour les bibliothèques portables (table Libraries).
class LocalLibraryDataSource {
  final db.AppDatabase _database;

  LocalLibraryDataSource(this._database);

  Future<List<domain.Library>> getAllLibraries() async {
    final rows = await _database.select(_database.libraries).get();
    return rows.map(LibraryModel.toEntity).toList();
  }

  /// Renvoie (crée si besoin) le nœud dossier `(libraryId, driveFolderId)`.
  /// Partagé entre liens imbriqués : deux bibliothèques qui couvrent le même
  /// dossier Drive convergent vers le même nœud plutôt que de le dupliquer.
  Future<int> ensureFolder({
    required int libraryId,
    required String driveFolderId,
    required String relativePath,
  }) async {
    final existing = await (_database.select(_database.libraryFolders)
          ..where(
            (f) =>
                f.libraryId.equals(libraryId) &
                f.driveFolderId.equals(driveFolderId),
          ))
        .getSingleOrNull();
    if (existing != null) {
      // Dossier déplacé/renommé : garde le chemin relatif à jour.
      if (existing.relativePath != relativePath) {
        await (_database.update(_database.libraryFolders)
              ..where((f) => f.id.equals(existing.id)))
            .write(db.LibraryFoldersCompanion(
              relativePath: Value(relativePath),
            ));
      }
      return existing.id;
    }
    return _database.into(_database.libraryFolders).insert(
          db.LibraryFoldersCompanion.insert(
            libraryId: libraryId,
            driveFolderId: driveFolderId,
            relativePath: Value(relativePath),
          ),
        );
  }

  Future<domain.Library?> getLibraryById(int id) async {
    final row = await (_database.select(
      _database.libraries,
    )..where((l) => l.id.equals(id))).getSingleOrNull();
    return row != null ? LibraryModel.toEntity(row) : null;
  }

  /// Insère une bibliothèque et retourne l'entité créée (avec son id).
  Future<domain.Library> insertLibrary({
    required String name,
    required String localRootPath,
    String? driveFolderId,
    String? drivePath,
    String? ownerEmail,
    String? sharedDriveId,
    bool autoDownload = false,
  }) async {
    final id = await _database.into(_database.libraries).insert(
          LibraryModel.toInsertCompanion(
            name: name,
            localRootPath: localRootPath,
            driveFolderId: driveFolderId,
            drivePath: drivePath,
            ownerEmail: ownerEmail,
            sharedDriveId: sharedDriveId,
            autoDownload: autoDownload,
          ),
        );
    final created = await getLibraryById(id);
    return created!;
  }

  /// Met à jour l'état de synchronisation après un push/pull réussi.
  Future<void> updateSyncState({
    required int id,
    String? driveFolderId,
    bool updateDriveFolderId = false,
    int? lastSyncedRevision,
    DateTime? lastSyncedAt,
  }) async {
    final companion = db.LibrariesCompanion(
      driveFolderId:
          updateDriveFolderId ? Value(driveFolderId) : const Value.absent(),
      lastSyncedRevision: lastSyncedRevision != null
          ? Value(lastSyncedRevision)
          : const Value.absent(),
      lastSyncedAt:
          lastSyncedAt != null ? Value(lastSyncedAt) : const Value.absent(),
    );
    await (_database.update(
      _database.libraries,
    )..where((l) => l.id.equals(id))).write(companion);
  }

  Future<void> setAutoDownload(int id, {required bool value}) async {
    await (_database.update(_database.libraries)..where((l) => l.id.equals(id)))
        .write(db.LibrariesCompanion(autoDownload: Value(value)));
  }

  Future<void> updateOwnerEmail(int id, String ownerEmail) async {
    await (_database.update(_database.libraries)..where((l) => l.id.equals(id)))
        .write(db.LibrariesCompanion(ownerEmail: Value(ownerEmail)));
  }

  Future<void> deleteLibrary(int id) async {
    await (_database.delete(
      _database.libraries,
    )..where((l) => l.id.equals(id))).go();
  }

  /// Nœuds dossier d'une bibliothèque (unités de snapshot par-dossier).
  Future<List<db.LibraryFolder>> getFoldersForLibrary(int libraryId) {
    return (_database.select(_database.libraryFolders)
          ..where((f) => f.libraryId.equals(libraryId)))
        .get();
  }

  Future<db.LibraryFolder?> getFolderById(int id) {
    return (_database.select(_database.libraryFolders)
          ..where((f) => f.id.equals(id)))
        .getSingleOrNull();
  }

  /// Met à jour la révision de snapshot connue pour un nœud dossier.
  Future<void> updateFolderSyncState({
    required int id,
    required int lastSyncedRevision,
    DateTime? lastSyncedAt,
  }) async {
    await (_database.update(_database.libraryFolders)
          ..where((f) => f.id.equals(id)))
        .write(db.LibraryFoldersCompanion(
      lastSyncedRevision: Value(lastSyncedRevision),
      lastSyncedAt:
          lastSyncedAt != null ? Value(lastSyncedAt) : const Value.absent(),
    ));
  }
}
