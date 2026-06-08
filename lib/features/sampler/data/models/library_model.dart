import 'package:drift/drift.dart';
import '../../domain/entities/library.dart' as domain;
import '../../../../core/database/database.dart' as db;

/// Mapping entre la table Drift `Libraries` et l'entité domain [domain.Library].
class LibraryModel {
  static domain.Library toEntity(db.Library row) {
    return domain.Library(
      id: row.id,
      name: row.name,
      localRootPath: row.localRootPath,
      driveFolderId: row.driveFolderId,
      drivePath: row.drivePath,
      ownerEmail: row.ownerEmail,
      sharedDriveId: row.sharedDriveId,
      lastSyncedRevision: row.lastSyncedRevision,
      lastSyncedAt: row.lastSyncedAt,
      createdAt: row.createdAt,
      autoDownload: row.autoDownload,
    );
  }

  static db.LibrariesCompanion toInsertCompanion({
    required String name,
    required String localRootPath,
    String? driveFolderId,
    String? drivePath,
    String? ownerEmail,
    String? sharedDriveId,
    bool autoDownload = false,
  }) {
    return db.LibrariesCompanion.insert(
      name: name,
      localRootPath: localRootPath,
      driveFolderId: Value(driveFolderId),
      drivePath: Value(drivePath),
      ownerEmail: Value(ownerEmail),
      sharedDriveId: Value(sharedDriveId),
      autoDownload: Value(autoDownload),
    );
  }
}
