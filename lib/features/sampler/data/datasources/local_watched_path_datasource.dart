import 'dart:io';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import '../../../../core/database/database.dart' as db;
import '../../../../core/platform/saf_directory_bridge.dart';
import '../../../../core/sync/sync_log.dart';
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
    SyncLog.trace(
      'Début du scan de ${watchedPaths.length} chemin(s) surveillé(s)',
    );
    int totalIndexed = 0;

    for (final watchedPath in watchedPaths) {
      try {
        if (!watchedPath.isDirectory) {
          SyncLog.trace(
            'Chemin ignoré (fichier individuel non supporté): '
            '${p.basename(watchedPath.path)}',
          );
          continue;
        }

        SyncLog.trace('Scan du dossier: ${p.basename(watchedPath.path)}');
        if (SafDirectoryBridge.isSafTreeUri(watchedPath.path)) {
          final count = await soundDataSource.indexContentTree(
            watchedPath.path,
            watchedPathId: watchedPath.id,
          );
          totalIndexed += count;
          SyncLog.trace(
            'Dossier SAF ${p.basename(watchedPath.path)}: $count nouveau(x) '
            'fichier(s) indexé(s)',
          );
        } else {
          final directory = Directory(watchedPath.path);
          if (await directory.exists()) {
            final count = await soundDataSource.indexDirectory(directory);
            totalIndexed += count;
            SyncLog.trace(
              'Dossier ${p.basename(watchedPath.path)}: $count nouveau(x) '
              'fichier(s) indexé(s)',
            );
          } else {
            // Un dossier surveillé qui a disparu (disque externe débranché) :
            // ses sons deviendront indisponibles, il faut pouvoir le dire.
            SyncLog.warn(
              'Dossier surveillé introuvable : '
              '« ${p.basename(watchedPath.path)} » — scan ignoré.',
            );
          }
        }
      } catch (e) {
        SyncLog.warn(
          'Erreur lors du scan du dossier '
          '« ${p.basename(watchedPath.path)} » : $e',
        );
      }
    }

    SyncLog.info(
      'Scan des dossiers surveillés terminé : ${watchedPaths.length} '
      'dossier(s), $totalIndexed nouveau(x) fichier(s) indexé(s).',
    );
    return totalIndexed;
  }
}
