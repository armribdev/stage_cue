import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import '../../../../core/database/database.dart' as db;
import '../../../../core/database/sounds.dart' as db_sounds;
import '../../../../core/utils/file_utils.dart'
    show scanDirectoryForAudioFiles, isAudioFile;
import '../models/sound_model.dart';
import '../models/sound_board_model.dart';
import '../models/watched_path_model.dart';
import '../models/indexing_progress.dart';
import '../../domain/entities/sound.dart' as domain;
import '../../domain/entities/sound_board.dart' as domain;
import '../../domain/entities/watched_path.dart' as domain;

/// Source de données locale pour les sons (base de données)
class LocalSoundDataSource {
  final db.AppDatabase _database;
  static const Duration _musicThreshold = Duration(seconds: 30);

  LocalSoundDataSource(this._database);

  Future<db_sounds.SoundType> _resolveSoundTypeFromDuration(File file) async {
    AudioSource? source;
    try {
      source = await SoLoud.instance.loadFile(file.path, mode: LoadMode.memory);
      final duration = SoLoud.instance.getLength(source);
      if (duration > _musicThreshold) {
        return db_sounds.SoundType.music;
      }
    } catch (e) {
      debugPrint(
        'Impossible de lire la durée de ${file.path}, type par défaut appliqué: $e',
      );
    } finally {
      if (source != null) {
        SoLoud.instance.disposeSource(source);
      }
    }
    return db_sounds.SoundType.soundEffect;
  }

  /// Récupère tous les sons
  Future<List<domain.Sound>> getAllSounds() async {
    final sounds = await _database.select(_database.sounds).get();
    return sounds.map((s) => SoundModel.toEntity(s)).toList();
  }

  /// Récupère uniquement les sons qui sont dans la board, triés par sort_order puis added_at
  /// Utilise une jointure SQL pour de meilleures performances et éviter les problèmes de sons supprimés
  Future<List<domain.Sound>> getBoardSounds(int boardId) async {
    final rows = await _database
        .customSelect(
          '''
      SELECT
        s.id AS id,
        s.title AS title,
        COALESCE(bss.display_name, s.display_name) AS display_name,
        s.file_path AS file_path,
        s.type AS type,
        COALESCE(bss.color, s.color) AS color,
        COALESCE(bss.volume, s.volume) AS volume,
        s.created_at AS created_at
      FROM sounds s
      INNER JOIN board_sounds bs
        ON bs.sound_id = s.id
      LEFT JOIN board_sound_settings bss
        ON bss.board_id = bs.board_id
       AND bss.sound_id = bs.sound_id
      WHERE bs.board_id = ?
      ORDER BY bs.sort_order, bs.added_at
      ''',
          variables: [Variable<int>(boardId)],
        )
        .get();

    return rows.map((row) {
      final typeValue = row.read<int>('type');
      final soundType = switch (typeValue) {
        0 => domain.SoundType.soundEffect,
        1 => domain.SoundType.music,
        2 => domain.SoundType.ambiance,
        _ => domain.SoundType.soundEffect,
      };
      return domain.Sound(
        id: row.read<int>('id'),
        title: row.read<String>('title'),
        displayName: row.read<String?>('display_name'),
        filePath: row.read<String>('file_path'),
        type: soundType,
        colorValue: row.read<int?>('color'),
        volume: row.read<double>('volume'),
        createdAt: row.read<DateTime>('created_at'),
      );
    }).toList();
  }

  /// Ajoute un son à la board
  Future<void> addSoundToBoard(int boardId, int soundId) async {
    // Vérifier si le son est déjà dans la board
    final existing =
        await (_database.select(_database.boardSounds)..where(
              (b) => b.boardId.equals(boardId) & b.soundId.equals(soundId),
            ))
            .getSingleOrNull();

    if (existing == null) {
      // Calculer le prochain sort_order (compte des sons déjà dans la board)
      final boardSoundsList = await (_database.select(
        _database.boardSounds,
      )..where((b) => b.boardId.equals(boardId))).get();
      final nextOrder = boardSoundsList.length;

      await _database
          .into(_database.boardSounds)
          .insert(
            db.BoardSoundsCompanion.insert(
              boardId: boardId,
              soundId: soundId,
              addedAt: Value(DateTime.now()),
              sortOrder: Value(nextOrder),
            ),
          );
    }
  }

  /// Retire un son de la board
  Future<void> removeSoundFromBoard(int boardId, int soundId) async {
    await (_database.delete(_database.boardSounds)
          ..where((b) => b.boardId.equals(boardId) & b.soundId.equals(soundId)))
        .go();
  }

  /// Réordonne les sons de la board selon la liste fournie (soundIds dans l'ordre voulu)
  Future<void> reorderBoardSounds(
    int boardId,
    List<int> soundIdsInOrder,
  ) async {
    // Applique l'ordre en une transaction pour éviter les états partiels
    // si une écriture échoue au milieu de la séquence.
    await _database.transaction(() async {
      for (var i = 0; i < soundIdsInOrder.length; i++) {
        await (_database.update(_database.boardSounds)..where(
              (b) =>
                  b.boardId.equals(boardId) &
                  b.soundId.equals(soundIdsInOrder[i]),
            ))
            .write(db.BoardSoundsCompanion(sortOrder: Value(i)));
      }
    });
  }

  /// Vérifie si un son est dans la board
  Future<bool> isSoundInBoard(int boardId, int soundId) async {
    final result =
        await (_database.select(_database.boardSounds)..where(
              (b) => b.boardId.equals(boardId) & b.soundId.equals(soundId),
            ))
            .getSingleOrNull();
    return result != null;
  }

  /// Récupère un son par son ID
  Future<domain.Sound?> getSoundById(int id) async {
    final sound = await (_database.select(
      _database.sounds,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
    return sound != null ? SoundModel.toEntity(sound) : null;
  }

  /// Ajoute un son
  Future<int> insertSound(domain.Sound sound) async {
    return await _database
        .into(_database.sounds)
        .insert(SoundModel.toCompanion(sound));
  }

  /// Supprime un son
  Future<void> deleteSound(int id) async {
    await (_database.delete(
      _database.sounds,
    )..where((s) => s.id.equals(id))).go();
  }

  /// Met à jour les réglages d'un son (couleur, volume)
  Future<void> updateSoundSettings({
    required int id,
    int? colorValue,
    bool updateColor = false,
    String? displayName,
    bool updateDisplayName = false,
    double? volume,
  }) async {
    final companion = db.SoundsCompanion(
      color: updateColor ? Value(colorValue) : const Value.absent(),
      displayName: updateDisplayName
          ? Value(displayName)
          : const Value.absent(),
      volume: volume != null ? Value(volume) : const Value.absent(),
    );
    await (_database.update(
      _database.sounds,
    )..where((s) => s.id.equals(id))).write(companion);
  }

  /// Met à jour les réglages d'un pad pour une board spécifique.
  Future<void> upsertBoardSoundSettings({
    required int boardId,
    required int soundId,
    int? colorValue,
    bool updateColor = false,
    String? displayName,
    bool updateDisplayName = false,
    double? volume,
  }) async {
    final existing = await _database
        .customSelect(
          '''
      SELECT display_name, color, volume
      FROM board_sound_settings
      WHERE board_id = ? AND sound_id = ?
      LIMIT 1
      ''',
          variables: [Variable<int>(boardId), Variable<int>(soundId)],
        )
        .getSingleOrNull();

    final nextDisplayName = updateDisplayName
        ? displayName
        : existing?.read<String?>('display_name');
    final nextColor = updateColor ? colorValue : existing?.read<int?>('color');
    final nextVolume = volume ?? existing?.read<double?>('volume');

    await _database.customStatement(
      '''
      INSERT INTO board_sound_settings (board_id, sound_id, display_name, color, volume)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(board_id, sound_id) DO UPDATE SET
        display_name = excluded.display_name,
        color = excluded.color,
        volume = excluded.volume
      ''',
      [boardId, soundId, nextDisplayName, nextColor, nextVolume],
    );
  }

  /// Copie les réglages par-board d'une scène source vers une scène cible.
  Future<void> copyBoardSoundSettings(int sourceBoardId, int targetBoardId) async {
    await _database.customStatement(
      '''
      INSERT OR IGNORE INTO board_sound_settings (board_id, sound_id, display_name, color, volume)
      SELECT ?, sound_id, display_name, color, volume
      FROM board_sound_settings
      WHERE board_id = ?
      ''',
      [targetBoardId, sourceBoardId],
    );
  }

  /// Indexe un fichier audio
  Future<void> indexAudioFile(File file) async {
    try {
      // Vérifier si le fichier existe déjà dans la base de données
      final existingSounds = await (_database.select(
        _database.sounds,
      )..where((s) => s.filePath.equals(file.path))).get();

      if (existingSounds.isNotEmpty) {
        // Le fichier est déjà indexé
        return;
      }

      // Extraire le nom du fichier sans extension pour le titre
      final title = p.basenameWithoutExtension(file.path);
      final soundType = await _resolveSoundTypeFromDuration(file);

      // Ajouter le fichier à la base de données
      await _database
          .into(_database.sounds)
          .insert(
            db.SoundsCompanion.insert(
              title: title,
              filePath: file.path,
              type: soundType,
            ),
          );
    } catch (e) {
      rethrow;
    }
  }

  /// Indexe tous les fichiers audio d'un dossier
  Future<int> indexDirectory(
    Directory directory, {
    void Function(IndexingProgress)? onProgress,
  }) async {
    try {
      // Vérifier que le dossier existe
      if (!await directory.exists()) {
        onProgress?.call(
          IndexingProgress(
            path: directory.path,
            current: 0,
            total: 0,
            isComplete: true,
            error: 'Le dossier n\'existe pas',
          ),
        );
        return 0;
      }

      // Notifier le début du scan
      onProgress?.call(
        IndexingProgress(
          path: directory.path,
          current: 0,
          total: 0,
          isComplete: false,
        ),
      );

      final audioFiles = await scanDirectoryForAudioFiles(directory);

      // Notifier le nombre total de fichiers trouvés
      onProgress?.call(
        IndexingProgress(
          path: directory.path,
          current: 0,
          total: audioFiles.length,
          isComplete: false,
        ),
      );

      int indexedCount = 0;
      int processedCount = 0;

      for (final file in audioFiles) {
        processedCount++;
        try {
          // Vérifier si le fichier existe déjà dans la base de données
          final existingSounds = await (_database.select(
            _database.sounds,
          )..where((s) => s.filePath.equals(file.path))).get();

          if (existingSounds.isNotEmpty) {
            // Le fichier est déjà indexé
            onProgress?.call(
              IndexingProgress(
                path: directory.path,
                current: processedCount,
                total: audioFiles.length,
                isComplete: false,
              ),
            );
            continue;
          }

          // Extraire le nom du fichier sans extension pour le titre
          final title = p.basenameWithoutExtension(file.path);
          final soundType = await _resolveSoundTypeFromDuration(file);

          // Ajouter le fichier à la base de données
          await _database
              .into(_database.sounds)
              .insert(
                db.SoundsCompanion.insert(
                  title: title,
                  filePath: file.path,
                  type: soundType,
                ),
              );
          indexedCount++;

          // Notifier la progression
          onProgress?.call(
            IndexingProgress(
              path: directory.path,
              current: processedCount,
              total: audioFiles.length,
              isComplete: false,
            ),
          );
        } catch (e) {
          // Continuer avec les autres fichiers même en cas d'erreur
          onProgress?.call(
            IndexingProgress(
              path: directory.path,
              current: processedCount,
              total: audioFiles.length,
              isComplete: false,
            ),
          );
        }
      }

      // Notifier la fin de l'indexation
      onProgress?.call(
        IndexingProgress(
          path: directory.path,
          current: processedCount,
          total: audioFiles.length,
          isComplete: true,
        ),
      );

      return indexedCount;
    } catch (e) {
      debugPrint(
        'Erreur lors de l\'indexation du dossier ${directory.path}: $e',
      );
      // Notifier l'erreur
      onProgress?.call(
        IndexingProgress(
          path: directory.path,
          current: 0,
          total: 0,
          isComplete: true,
          error: e.toString(),
        ),
      );
      rethrow;
    }
  }

  /// Supprime les sons associés à un chemin surveillé
  Future<void> deleteSoundsByPath(String path, bool isDirectory) async {
    if (isDirectory) {
      final directory = Directory(path);
      final directoryPath = directory.path.replaceAll('\\', '/');
      // Récupérer tous les sons et filtrer ceux qui commencent par le chemin du dossier
      final allSounds = await _database.select(_database.sounds).get();
      final soundsToDelete = allSounds.where((sound) {
        final soundPath = sound.filePath.replaceAll('\\', '/');
        return soundPath.startsWith(directoryPath);
      }).toList();

      for (final sound in soundsToDelete) {
        await (_database.delete(
          _database.sounds,
        )..where((s) => s.id.equals(sound.id))).go();
      }
    } else {
      await (_database.delete(
        _database.sounds,
      )..where((s) => s.filePath.equals(path))).go();
    }
  }
}

/// Source de données locale pour les soundboards
class LocalSoundBoardDataSource {
  final db.AppDatabase _database;

  LocalSoundBoardDataSource(this._database);

  /// Récupère toutes les soundboards
  Future<List<domain.SoundBoard>> getAllBoards() async {
    final boards = await (_database.select(
      _database.soundBoards,
    )..orderBy([(b) => OrderingTerm(expression: b.createdAt)])).get();
    return boards.map((b) => SoundBoardModel.toEntity(b)).toList();
  }

  /// Crée une soundboard
  Future<int> createBoard(String name) async {
    return await _database
        .into(_database.soundBoards)
        .insert(
          db.SoundBoardsCompanion.insert(
            name: name,
            createdAt: Value(DateTime.now()),
          ),
        );
  }

  /// Renomme une soundboard
  Future<void> renameBoard(int boardId, String name) async {
    await (_database.update(_database.soundBoards)
          ..where((b) => b.id.equals(boardId)))
        .write(db.SoundBoardsCompanion(name: Value(name)));
  }

  /// Supprime une soundboard
  Future<void> deleteBoard(int boardId) async {
    await (_database.delete(
      _database.soundBoards,
    )..where((b) => b.id.equals(boardId))).go();
  }
}

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

  /// Scanne tous les chemins surveillés et indexe les nouveaux fichiers
  Future<int> scanAllWatchedPaths(LocalSoundDataSource soundDataSource) async {
    final watchedPaths = await getAllWatchedPaths();
    debugPrint(
      'Début du scan de ${watchedPaths.length} chemin(s) surveillé(s)',
    );
    int totalIndexed = 0;

    for (final watchedPath in watchedPaths) {
      try {
        if (watchedPath.isDirectory) {
          debugPrint('Scan du dossier: ${watchedPath.path}');
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
        } else {
          debugPrint('Indexation du fichier: ${watchedPath.path}');
          final file = File(watchedPath.path);
          if (await file.exists() && isAudioFile(file.path)) {
            await soundDataSource.indexAudioFile(file);
            totalIndexed++;
            debugPrint('Fichier indexé: ${watchedPath.path}');
          } else {
            if (!await file.exists()) {
              debugPrint('Le fichier n\'existe pas: ${watchedPath.path}');
            } else if (!isAudioFile(file.path)) {
              debugPrint(
                'Le fichier n\'est pas un fichier audio: ${watchedPath.path}',
              );
            }
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
