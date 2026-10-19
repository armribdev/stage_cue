import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/database.dart' as db;
import '../../../../core/platform/saf_directory_bridge.dart';
import '../models/watched_path_model.dart';
import '../../domain/entities/watched_path.dart' as domain;
import 'local_sound_datasource.dart';

/// Source de données locale pour les chemins surveillés
class LocalWatchedPathDataSource {
  final db.AppDatabase _database;

  LocalWatchedPathDataSource(this._database);

  /// Récupère tous les chemins surveillés
  Future<List<domain.WatchedPath>> getAllWatchedPaths() async {
    final paths = await _database.select(_database.watchedPaths).get();
    return paths.map((p) => WatchedPathModel.toEntity(p)).toList();
  }

  /// Ajoute un chemin surveillé
  Future<int> insertWatchedPath(domain.WatchedPath watchedPath) async {
    return await _database
        .into(_database.watchedPaths)
        .insert(WatchedPathModel.toCompanion(watchedPath));
  }

  /// Supprime un chemin surveillé
  Future<void> deleteWatchedPath(int id) async {
    await (_database.delete(
      _database.watchedPaths,
    )..where((w) => w.id.equals(id))).go();
  }

  Future<void> updateWatchedPathAccount({
    required int id,
    String? accountEmail,
    String? driveFileId,
  }) async {
    await (_database.update(_database.watchedPaths)..where((w) => w.id.equals(id)))
        .write(
      db.WatchedPathsCompanion(
        accountEmail: Value(accountEmail),
        driveFileId: Value(driveFileId),
      ),
    );
  }

  /// Scanne tous les chemins surveillés et indexe les nouveaux fichiers
  Future<int> scanAllWatchedPaths(LocalSoundDataSource soundDataSource) async {
    final watchedPaths = await getAllWatchedPaths();
    debugPrint(
      'Début du scan de ${watchedPaths.length} chemin(s) surveillé(s)',
    );
    int totalIndexed = 0;

    for (final watchedPath in watchedPaths) {
      try {
        if (!watchedPath.isDirectory) {
          debugPrint(
            'Chemin ignoré (fichier individuel non supporté): ${watchedPath.path}',
          );
          continue;
        }

        debugPrint('Scan du dossier: ${watchedPath.path}');
        if (SafDirectoryBridge.isSafTreeUri(watchedPath.path)) {
          final count = await soundDataSource.indexContentTree(
            watchedPath.path,
            watchedPathId: watchedPath.id,
          );
          totalIndexed += count;
          debugPrint(
            'Dossier SAF ${watchedPath.path}: $count nouveau(x) fichier(s) indexé(s)',
          );
        } else {
          final directory = Directory(watchedPath.path);
          if (await directory.exists()) {
            final count = await soundDataSource.indexDirectory(directory);
            totalIndexed += count;
            debugPrint(
              'Dossier ${watchedPath.path}: $count nouveau(x) fichier(s) indexé(s)',
            );
          } else {
            debugPrint('Le dossier n\'existe pas: ${watchedPath.path}');
          }
        }
      } catch (e) {
        debugPrint('Erreur lors du scan de ${watchedPath.path}: $e');
      }
    }

    debugPrint(
      'Scan terminé: $totalIndexed nouveau(x) fichier(s) indexé(s) au total',
    );
    return totalIndexed;
  }
}
