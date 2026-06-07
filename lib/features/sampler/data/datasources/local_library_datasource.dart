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
  }) async {
    final id = await _database.into(_database.libraries).insert(
          LibraryModel.toInsertCompanion(
            name: name,
            localRootPath: localRootPath,
            driveFolderId: driveFolderId,
            drivePath: drivePath,
            ownerEmail: ownerEmail,
            sharedDriveId: sharedDriveId,
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
}
