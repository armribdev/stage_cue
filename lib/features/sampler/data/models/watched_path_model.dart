import 'package:drift/drift.dart';
import '../../domain/entities/watched_path.dart';
import '../../../../core/database/database.dart' as db;

/// Modèle de données pour WatchedPath (mapping entre Drift et entité domain)
class WatchedPathModel {
  /// Convertit un WatchedPath de Drift vers une entité domain
  static WatchedPath toEntity(db.WatchedPath watchedPath) {
    return WatchedPath(
      id: watchedPath.id,
      path: watchedPath.path,
      isDirectory: watchedPath.isDirectory,
      addedAt: watchedPath.addedAt,
    );
  }

  /// Convertit une entité domain vers un Companion Drift pour insertion
  static db.WatchedPathsCompanion toCompanion(WatchedPath watchedPath) {
    return db.WatchedPathsCompanion.insert(
      path: watchedPath.path,
      isDirectory: Value(watchedPath.isDirectory),
    );
  }
}

