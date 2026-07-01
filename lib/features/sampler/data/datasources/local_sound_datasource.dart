import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import '../../../../core/database/database.dart' as db;
import '../../../../core/database/sounds.dart' as db_sounds;
import 'package:path_provider/path_provider.dart';

import '../../../../core/platform/saf_directory_bridge.dart';
import '../../../../core/utils/file_utils.dart'
    show scanDirectoryForAudioFiles, computeQuickHash;
import '../../../../core/audio/soloud_file_loader.dart';
import '../../../../core/audio/audio_load_log.dart';
import '../../../../core/audio/audio_file_validation.dart';
import '../models/sound_model.dart';
import '../models/sound_board_model.dart';
import '../models/watched_path_model.dart';
import '../models/indexing_progress.dart';
import '../../domain/entities/sound.dart' as domain;
import '../../domain/entities/sound_board.dart' as domain;
import '../../domain/entities/watched_path.dart' as domain;
import '../../domain/entities/pad.dart' as domain_pad;

/// Source de données locale pour les sons (base de données)
class LocalSoundDataSource {
  final db.AppDatabase _database;
  static const Duration _musicThreshold = Duration(seconds: 30);

  LocalSoundDataSource(this._database);

  /// Résout les métadonnées d'un fichier audio local.
  /// Retourne `type: null` si le fichier est absent ou si le probe de durée échoue.
  Future<({db_sounds.SoundType? type, String? contentHash})>
      _resolveMetadataForFile(File file) async {
    if (!await file.exists() || await file.length() <= 0) {
      return (type: null, contentHash: null);
    }
    final probeType = await _probeSoundTypeFromDuration(file);
    final contentHash =
        probeType != null ? await computeQuickHash(file) : null;
    return (type: probeType, contentHash: contentHash);
  }

  /// Probe de type par durée SoLoud. Retourne null si le fichier est invalide
  /// ou si SoLoud ne peut pas le lire.
  Future<db_sounds.SoundType?> _probeSoundTypeFromDuration(File file) async {
    if (!await isPlausibleAudioFile(file)) {
      AudioLoadLog.metadataProbeFailed(
        path: file.path,
        error: StateError(
          'Fichier trop petit ou en-tête invalide '
          '(min $kMinimumValidAudioFileBytes o)',
        ),
      );
      return null;
    }

    final duration = await _readDurationViaSoLoud(file);
    if (duration == null) return null;
    return _typeFromDuration(duration);
  }

  db_sounds.SoundType _typeFromDuration(Duration duration) =>
      duration > _musicThreshold
          ? db_sounds.SoundType.music
          : db_sounds.SoundType.soundEffect;

  Future<Duration?> _readDurationViaSoLoud(File file) async {
    AudioSource? source;
    try {
      source = await loadAudioSourceFromFile(file);
      final duration = SoLoud.instance.getLength(source);
      if (duration <= Duration.zero) return null;
      return duration;
    } catch (e) {
      AudioLoadLog.metadataProbeFailed(path: file.path, error: e);
      return null;
    } finally {
      if (source != null) {
        try {
          SoLoud.instance.disposeSource(source);
        } catch (e) {
          debugPrint('Dispose SoLoud (probe durée) échoué: $e');
        }
      }
    }
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
      final typeValue = row.read<int?>('type');
      return domain.Sound(
        id: row.read<int>('id'),
        title: row.read<String>('title'),
        displayName: row.read<String?>('display_name'),
        filePath: row.read<String>('file_path'),
        type: switch (typeValue) {
          0 => domain.SoundType.soundEffect,
          1 => domain.SoundType.music,
          2 => domain.SoundType.ambiance,
          _ => null,
        },
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

  /// Change le type d'un son (corrige une auto-détection par durée erronée).
  Future<void> updateSoundType(int id, domain.SoundType type) async {
    final dbType = switch (type) {
      domain.SoundType.soundEffect => db_sounds.SoundType.soundEffect,
      domain.SoundType.music => db_sounds.SoundType.music,
      domain.SoundType.ambiance => db_sounds.SoundType.ambiance,
    };
    await (_database.update(_database.sounds)..where((s) => s.id.equals(id)))
        .write(db.SoundsCompanion(type: Value(dbType)));
  }

  /// Marque ou démarque un son comme favori (accès rapide en recherche).
  Future<void> setFavorite(int id, bool isFavorite) async {
    await (_database.update(_database.sounds)..where((s) => s.id.equals(id)))
        .write(db.SoundsCompanion(isFavorite: Value(isFavorite)));
  }

  /// Enregistre l'instant de dernière lecture (tri par récence).
  Future<void> markPlayed(int id, {DateTime? at}) async {
    await (_database.update(_database.sounds)..where((s) => s.id.equals(id)))
        .write(db.SoundsCompanion(lastPlayedAt: Value(at ?? DateTime.now())));
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
      final metadata = await _resolveMetadataForFile(file);

      // Ajouter le fichier à la base de données
      await _database
          .into(_database.sounds)
          .insert(
            db.SoundsCompanion.insert(
              title: title,
              filePath: file.path,
              type: Value(metadata.type),
              contentHash: Value(metadata.contentHash),
            ),
          );
    } catch (e) {
      rethrow;
    }
  }

  /// Indexe un fichier audio déjà matérialisé dans le cache d'une bibliothèque.
  ///
  /// [file] est le fichier local (dans le cache de la bibliothèque), [libraryId]
  /// la bibliothèque d'appartenance et [relativePath] le chemin portable. Le son
  /// devient ainsi synchronisable entre appareils. Retourne true si un nouveau
  /// son a été créé (false si déjà présent).
  Future<bool> indexLibraryAudioFile(
    File file, {
    required int libraryId,
    required String relativePath,
  }) async {
    // Déduplication par (bibliothèque, chemin relatif).
    final existing = await (_database.select(_database.sounds)
          ..where(
            (s) =>
                s.libraryId.equals(libraryId) &
                s.relativePath.equals(relativePath),
          ))
        .get();
    if (existing.isNotEmpty) return false;

    final title = p.basenameWithoutExtension(file.path);
    final metadata = await _resolveMetadataForFile(file);

    await _database.into(_database.sounds).insert(
          db.SoundsCompanion.insert(
            title: title,
            filePath: file.path,
            type: Value(metadata.type),
            libraryId: Value(libraryId),
            relativePath: Value(relativePath),
            contentHash: Value(metadata.contentHash),
          ),
        );
    return true;
  }

  /// Persiste hash et/ou type si le fichier vient d'être matérialisé.
  /// Ne modifie jamais un type déjà connu (`type != null`).
  Future<void> materializeSoundFileMetadata({
    required int soundId,
    required File file,
  }) async {
    final existing = await (_database.select(_database.sounds)
          ..where((s) => s.id.equals(soundId)))
        .getSingleOrNull();
    if (existing == null) return;
    if (!await isPlausibleAudioFile(file)) return;

    if (existing.type == null) {
      final probeType = await _probeSoundTypeFromDuration(file);
      final contentHash = probeType != null
          ? await computeQuickHash(file)
          : existing.contentHash;
      await (_database.update(_database.sounds)
            ..where((s) => s.id.equals(soundId)))
          .write(
        db.SoundsCompanion(
          type: Value(probeType),
          contentHash: Value(contentHash),
        ),
      );
      return;
    }

    if (existing.contentHash != null) return;
    final contentHash = await computeQuickHash(file);
    await (_database.update(_database.sounds)
          ..where((s) => s.id.equals(soundId)))
        .write(db.SoundsCompanion(contentHash: Value(contentHash)));
  }

  /// true si un son `(libraryId, relativePath)` existe déjà en base.
  Future<bool> hasLibrarySound({
    required int libraryId,
    required String relativePath,
  }) async {
    final existing = await (_database.select(_database.sounds)
          ..where(
            (s) =>
                s.libraryId.equals(libraryId) &
                s.relativePath.equals(relativePath),
          ))
        .get();
    return existing.isNotEmpty;
  }

  /// Corrige le chemin relatif portable d'un son (déplacement/renommage Drive).
  Future<void> updateSoundRelativePath({
    required int soundId,
    required String relativePath,
    required String localPath,
  }) async {
    await (_database.update(_database.sounds)
          ..where((s) => s.id.equals(soundId)))
        .write(
          db.SoundsCompanion(
            relativePath: Value(relativePath),
            filePath: Value(localPath),
          ),
        );
  }

  /// Met à jour le chemin local cache d'un son de bibliothèque si nécessaire.
  Future<void> syncLibrarySoundLocalPath(int soundId, String localPath) async {
    final row = await (_database.select(_database.sounds)
          ..where((s) => s.id.equals(soundId)))
        .getSingleOrNull();
    if (row == null || row.filePath == localPath) return;

    await (_database.update(_database.sounds)
          ..where((s) => s.id.equals(soundId)))
        .write(db.SoundsCompanion(filePath: Value(localPath)));
  }

  /// Synchronise un son de bibliothèque avec l'index Drive.
  ///
  /// Identité forte : l'`driveFileId` (immuable au renommage/déplacement) est la
  /// clé de déduplication. Ordre de résolution :
  /// 1. match `(libraryId, driveFileId)` → même fichier : corrige le chemin
  ///    relatif/local s'il a bougé (aucun doublon créé) ;
  /// 2. sinon match `(libraryId, relativePath)` legacy → adopte l'`driveFileId`
  ///    (backfill des sons indexés avant l'identité forte) ;
  /// 3. sinon nouveau son.
  ///
  /// Retourne `true` si un nouveau son a été créé.
  Future<bool> syncLibrarySoundFromDriveIndex({
    required int libraryId,
    required String relativePath,
    required String localPath,
    String? driveFileId,
  }) async {
    // 1. Identité forte : le fichier est déjà connu par son ID Drive.
    if (driveFileId != null) {
      final byFileId = await (_database.select(_database.sounds)
            ..where(
              (s) =>
                  s.libraryId.equals(libraryId) &
                  s.driveFileId.equals(driveFileId),
            ))
          .get();
      if (byFileId.isNotEmpty) {
        final row = byFileId.first;
        if (row.relativePath != relativePath || row.filePath != localPath) {
          await (_database.update(_database.sounds)
                ..where((s) => s.id.equals(row.id)))
              .write(
            db.SoundsCompanion(
              relativePath: Value(relativePath),
              filePath: Value(localPath),
            ),
          );
        }
        return false;
      }
    }

    // 2. Legacy : son déjà indexé par chemin, sans identité forte → on l'adopte.
    final byPath = await (_database.select(_database.sounds)
          ..where(
            (s) =>
                s.libraryId.equals(libraryId) &
                s.relativePath.equals(relativePath),
          ))
        .get();
    if (byPath.isNotEmpty) {
      final row = byPath.first;
      await (_database.update(_database.sounds)
            ..where((s) => s.id.equals(row.id)))
          .write(
        db.SoundsCompanion(
          filePath: Value(localPath),
          driveFileId:
              driveFileId != null ? Value(driveFileId) : const Value.absent(),
        ),
      );
      return false;
    }

    // 3. Nouveau son.
    final title = p.basenameWithoutExtension(relativePath);
    final metadata = await _resolveMetadataForFile(File(localPath));

    await _database.into(_database.sounds).insert(
          db.SoundsCompanion.insert(
            title: title,
            filePath: localPath,
            type: Value(metadata.type),
            libraryId: Value(libraryId),
            relativePath: Value(relativePath),
            contentHash: Value(metadata.contentHash),
            driveFileId: Value(driveFileId),
          ),
        );
    return true;
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
          final metadata = await _resolveMetadataForFile(file);

          // Ajouter le fichier à la base de données
          await _database
              .into(_database.sounds)
              .insert(
                db.SoundsCompanion.insert(
                  title: title,
                  filePath: file.path,
                  type: Value(metadata.type),
                  contentHash: Value(metadata.contentHash),
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

  /// Indexe les fichiers audio d'un dossier via SAF (Android : Drive, stockage…).
  Future<int> indexContentTree(
    String treeUri, {
    required int watchedPathId,
    void Function(IndexingProgress)? onProgress,
  }) async {
    try {
      onProgress?.call(
        IndexingProgress(
          path: treeUri,
          current: 0,
          total: 0,
          isComplete: false,
        ),
      );

      final entries = await SafDirectoryBridge.listAudioFiles(treeUri);
      onProgress?.call(
        IndexingProgress(
          path: treeUri,
          current: 0,
          total: entries.length,
          isComplete: false,
        ),
      );

      final docs = await getApplicationDocumentsDirectory();
      final cacheRoot = SafDirectoryBridge.cacheRootForWatchedPath(
        watchedPathId,
        docs.path,
      );

      var indexedCount = 0;
      var processedCount = 0;

      for (final entry in entries) {
        processedCount++;
        try {
          final localPath = p.join(cacheRoot, entry.relativePath);
          final localFile = File(localPath);
          final existingSounds = await (_database.select(
            _database.sounds,
          )..where((s) => s.filePath.equals(localPath))).get();
          if (existingSounds.isNotEmpty) {
            continue;
          }

          await SafDirectoryBridge.copyToFile(
            documentUri: entry.uri,
            destinationPath: localPath,
          );
          await indexAudioFile(localFile);
          indexedCount++;
        } catch (e) {
          debugPrint(
            'Erreur lors de l\'indexation SAF de ${entry.relativePath}: $e',
          );
        }

        onProgress?.call(
          IndexingProgress(
            path: treeUri,
            current: processedCount,
            total: entries.length,
            isComplete: false,
          ),
        );
      }

      onProgress?.call(
        IndexingProgress(
          path: treeUri,
          current: processedCount,
          total: entries.length,
          isComplete: true,
        ),
      );

      return indexedCount;
    } catch (e) {
      onProgress?.call(
        IndexingProgress(
          path: treeUri,
          current: 0,
          total: 0,
          isComplete: true,
          error: e.toString(),
        ),
      );
      rethrow;
    }
  }

  /// Retourne tous les sons appartenant à une bibliothèque Drive (relativePath non nul).
  Future<List<domain.Sound>> getSoundsForLibrary(int libraryId) async {
    final rows = await (_database.select(_database.sounds)
          ..where(
            (s) =>
                s.libraryId.equals(libraryId) &
                s.relativePath.isNotNull(),
          ))
        .get();
    return rows.map((row) {
      return domain.Sound(
        id: row.id,
        title: row.title,
        displayName: row.displayName,
        filePath: row.filePath,
        type: switch (row.type) {
          db_sounds.SoundType.music => domain.SoundType.music,
          db_sounds.SoundType.ambiance => domain.SoundType.ambiance,
          db_sounds.SoundType.soundEffect => domain.SoundType.soundEffect,
          null => null,
        },
        colorValue: row.color,
        volume: row.volume,
        createdAt: row.createdAt,
        libraryId: row.libraryId,
        relativePath: row.relativePath,
        contentHash: row.contentHash,
      );
    }).toList();
  }

  /// Chemins relatifs des sons favoris d'une bibliothèque — pour épingler le
  /// cache : ces fichiers ne doivent jamais être évincés par le LRU (P3).
  Future<Set<String>> getFavoriteRelativePaths(int libraryId) async {
    final rows = await (_database.select(_database.sounds)
          ..where(
            (s) =>
                s.libraryId.equals(libraryId) &
                s.isFavorite.equals(true) &
                s.relativePath.isNotNull(),
          ))
        .get();
    return {
      for (final row in rows)
        if (row.relativePath != null) row.relativePath!,
    };
  }

  /// Supprime tous les sons d'une bibliothèque Drive.
  Future<void> deleteSoundsByLibraryId(int libraryId) async {
    await (_database.delete(
      _database.sounds,
    )..where((s) => s.libraryId.equals(libraryId))).go();
  }

  /// Supprime les sons associés à un chemin surveillé.
  Future<void> deleteSoundsForWatchedPath({
    required String path,
    required int watchedPathId,
    required bool isDirectory,
  }) async {
    if (!isDirectory) {
      await (_database.delete(
        _database.sounds,
      )..where((s) => s.filePath.equals(path))).go();
      return;
    }

    if (SafDirectoryBridge.isSafTreeUri(path)) {
      final marker = '/saf_watch/$watchedPathId/';
      final allSounds = await _database.select(_database.sounds).get();
      final soundsToDelete = allSounds.where((sound) {
        final soundPath = sound.filePath.replaceAll('\\', '/');
        return soundPath.contains(marker);
      }).toList();

      for (final sound in soundsToDelete) {
        await (_database.delete(
          _database.sounds,
        )..where((s) => s.id.equals(sound.id))).go();
      }

      final docs = await getApplicationDocumentsDirectory();
      final cacheDir = Directory(
        SafDirectoryBridge.cacheRootForWatchedPath(watchedPathId, docs.path),
      );
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
      return;
    }

    final directoryPath = Directory(path).path.replaceAll('\\', '/');
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
  Future<int> createBoard(
    String name, {
    int? color,
    int? libraryId,
  }) async {
    return await _database
        .into(_database.soundBoards)
        .insert(
          db.SoundBoardsCompanion.insert(
            name: name,
            color: Value(color),
            libraryId: Value(libraryId),
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

/// Source de données locale pour les pads
class LocalPadDataSource {
  final db.AppDatabase _database;

  LocalPadDataSource(this._database);

  domain.Sound _rowToSound(QueryRow row) {
    final typeValue = row.read<int?>('type');
    return domain.Sound(
      id: row.read<int>('id'),
      title: row.read<String>('title'),
      displayName: row.read<String?>('display_name'),
      filePath: row.read<String>('file_path'),
      type: switch (typeValue) {
        0 => domain.SoundType.soundEffect,
        1 => domain.SoundType.music,
        2 => domain.SoundType.ambiance,
        _ => null,
      },
      colorValue: row.read<int?>('color'),
      volume: row.read<double>('volume'),
      createdAt: row.read<DateTime>('created_at'),
      libraryId: row.read<int?>('library_id'),
      relativePath: row.read<String?>('relative_path'),
      contentHash: row.read<String?>('content_hash'),
    );
  }

  /// Récupère tous les pads d'une board avec leurs sons.
  Future<List<domain_pad.Pad>> getBoardPads(int boardId) async {
    final padRows = await _database.customSelect(
      '''
      SELECT id, board_id, name, color, sort_order, row_index, play_mode, volume, created_at
      FROM pads
      WHERE board_id = ?
      ORDER BY row_index, sort_order, created_at
      ''',
      variables: [Variable<int>(boardId)],
    ).get();

    final pads = <domain_pad.Pad>[];
    for (final padRow in padRows) {
      final soundRows = await _database.customSelect(
        '''
        SELECT s.id, s.title, s.display_name, s.file_path, s.type,
               s.color, s.volume, s.created_at,
               s.library_id, s.relative_path, s.content_hash
        FROM pad_sounds ps
        INNER JOIN sounds s ON s.id = ps.sound_id
        WHERE ps.pad_id = ?
        ORDER BY ps.sort_order, ps.added_at
        ''',
        variables: [Variable<int>(padRow.read<int>('id'))],
      ).get();

      pads.add(domain_pad.Pad(
        id: padRow.read<int>('id'),
        boardId: padRow.read<int>('board_id'),
        name: padRow.read<String?>('name'),
        colorValue: padRow.read<int?>('color'),
        sortOrder: padRow.read<int>('sort_order'),
        rowIndex: padRow.read<int>('row_index'),
        playMode: padRow.read<int>('play_mode') == 0
            ? domain_pad.PadPlayMode.random
            : domain_pad.PadPlayMode.sequential,
        volume: padRow.read<double>('volume'),
        createdAt: padRow.read<DateTime>('created_at'),
        sounds: soundRows.map(_rowToSound).toList(),
      ));
    }
    return pads;
  }

  /// Crée un pad avec un son initial, retourne l'id du pad créé.
  Future<int> createPad(int boardId, int soundId, {int rowIndex = 0}) async {
    final countRow = await _database.customSelect(
      'SELECT COUNT(*) AS c FROM pads WHERE board_id = ?',
      variables: [Variable<int>(boardId)],
    ).getSingle();
    final nextOrder = countRow.read<int>('c');

    final padId = await _database.into(_database.pads).insert(
      db.PadsCompanion.insert(
        boardId: boardId,
        sortOrder: Value(nextOrder),
        rowIndex: Value(rowIndex),
      ),
    );
    await _database.into(_database.padSounds).insert(
      db.PadSoundsCompanion.insert(padId: padId, soundId: soundId),
    );
    return padId;
  }

  /// Crée un pad avec des réglages complets et plusieurs sons.
  Future<int> createPadWithSettings({
    required int boardId,
    required List<int> soundIds,
    String? name,
    int? colorValue,
    double volume = 1.0,
    domain_pad.PadPlayMode playMode = domain_pad.PadPlayMode.random,
    int? sortOrder,
    int rowIndex = 0,
  }) async {
    final nextOrder = sortOrder ??
        (await _database.customSelect(
          'SELECT COUNT(*) AS c FROM pads WHERE board_id = ?',
          variables: [Variable<int>(boardId)],
        ).getSingle())
            .read<int>('c');

    final padId = await _database.into(_database.pads).insert(
      db.PadsCompanion.insert(
        boardId: boardId,
        name: Value(name),
        color: Value(colorValue),
        sortOrder: Value(nextOrder),
        rowIndex: Value(rowIndex),
        playMode: Value(
          playMode == domain_pad.PadPlayMode.random
              ? db_sounds.PadPlayMode.random
              : db_sounds.PadPlayMode.sequential,
        ),
        volume: Value(volume),
      ),
    );
    for (var i = 0; i < soundIds.length; i++) {
      await _database.into(_database.padSounds).insert(
        db.PadSoundsCompanion.insert(
          padId: padId,
          soundId: soundIds[i],
          sortOrder: Value(i),
        ),
      );
    }
    return padId;
  }

  /// Supprime un pad (cascade sur pad_sounds).
  Future<void> deletePad(int padId) async {
    await (_database.delete(_database.pads)
          ..where((p) => p.id.equals(padId)))
        .go();
  }

  /// Ajoute un son à un pad existant.
  Future<void> addSoundToPad(int padId, int soundId) async {
    final existing = await _database.customSelect(
      'SELECT COUNT(*) AS c FROM pad_sounds WHERE pad_id = ? AND sound_id = ?',
      variables: [Variable<int>(padId), Variable<int>(soundId)],
    ).getSingle();
    if (existing.read<int>('c') > 0) return;

    final countRow = await _database.customSelect(
      'SELECT COUNT(*) AS c FROM pad_sounds WHERE pad_id = ?',
      variables: [Variable<int>(padId)],
    ).getSingle();
    final nextOrder = countRow.read<int>('c');

    await _database.into(_database.padSounds).insert(
      db.PadSoundsCompanion.insert(
        padId: padId,
        soundId: soundId,
        sortOrder: Value(nextOrder),
      ),
    );
  }

  /// Retire un son d'un pad.
  Future<void> removeSoundFromPad(int padId, int soundId) async {
    await (_database.delete(_database.padSounds)
          ..where(
            (ps) => ps.padId.equals(padId) & ps.soundId.equals(soundId),
          ))
        .go();
  }

  /// Réordonne les pads d'une board.
  Future<void> reorderBoardPads(int boardId, List<int> padIdsInOrder) async {
    await _database.transaction(() async {
      for (var i = 0; i < padIdsInOrder.length; i++) {
        await (_database.update(_database.pads)
              ..where(
                (p) =>
                    p.id.equals(padIdsInOrder[i]) & p.boardId.equals(boardId),
              ))
            .write(db.PadsCompanion(sortOrder: Value(i)));
      }
    });
  }

  /// Met à jour row_index et sort_order de chaque pad en une transaction.
  Future<void> applyPadsLayout(
    int boardId,
    List<({int padId, int rowIndex, int sortOrder})> layout,
  ) async {
    await _database.transaction(() async {
      for (final entry in layout) {
        await (_database.update(_database.pads)
              ..where(
                (p) => p.id.equals(entry.padId) & p.boardId.equals(boardId),
              ))
            .write(
          db.PadsCompanion(
            rowIndex: Value(entry.rowIndex),
            sortOrder: Value(entry.sortOrder),
          ),
        );
      }
    });
  }

  /// Met à jour les réglages d'un pad.
  Future<void> updatePadSettings({
    required int padId,
    String? name,
    bool updateName = false,
    int? colorValue,
    bool updateColor = false,
    double? volume,
    domain_pad.PadPlayMode? playMode,
  }) async {
    final companion = db.PadsCompanion(
      name: updateName ? Value(name) : const Value.absent(),
      color: updateColor ? Value(colorValue) : const Value.absent(),
      volume: volume != null ? Value(volume) : const Value.absent(),
      playMode: playMode != null
          ? Value(
              playMode == domain_pad.PadPlayMode.random
                  ? db_sounds.PadPlayMode.random
                  : db_sounds.PadPlayMode.sequential,
            )
          : const Value.absent(),
    );
    await (_database.update(_database.pads)
          ..where((p) => p.id.equals(padId)))
        .write(companion);
  }

  Future<void> updatePadRowIndex(int padId, int newRowIndex) async {
    await (_database.update(_database.pads)
          ..where((p) => p.id.equals(padId)))
        .write(db.PadsCompanion(rowIndex: Value(newRowIndex)));
  }

  /// Duplique tous les pads d'une board vers une autre board.
  Future<void> duplicatePads(int sourceBoardId, int targetBoardId) async {
    final sourcePads = await _database.customSelect(
      'SELECT id, name, color, sort_order, play_mode, volume FROM pads '
      'WHERE board_id = ? ORDER BY sort_order',
      variables: [Variable<int>(sourceBoardId)],
    ).get();

    for (final padRow in sourcePads) {
      final newPadId = await _database.into(_database.pads).insert(
        db.PadsCompanion.insert(
          boardId: targetBoardId,
          name: Value(padRow.read<String?>('name')),
          color: Value(padRow.read<int?>('color')),
          sortOrder: Value(padRow.read<int>('sort_order')),
          playMode: Value(
            db_sounds.PadPlayMode.values[padRow.read<int>('play_mode')],
          ),
          volume: Value(padRow.read<double>('volume')),
        ),
      );

      final soundRows = await _database.customSelect(
        'SELECT sound_id, sort_order FROM pad_sounds '
        'WHERE pad_id = ? ORDER BY sort_order',
        variables: [Variable<int>(padRow.read<int>('id'))],
      ).get();

      for (final soundRow in soundRows) {
        await _database.into(_database.padSounds).insert(
          db.PadSoundsCompanion.insert(
            padId: newPadId,
            soundId: soundRow.read<int>('sound_id'),
            sortOrder: Value(soundRow.read<int>('sort_order')),
          ),
        );
      }
    }
  }

  /// Retourne les IDs de tous les sons présents dans les pads d'une board.
  Future<Set<int>> getSoundIdsInBoard(int boardId) async {
    final rows = await _database.customSelect(
      '''
      SELECT DISTINCT ps.sound_id
      FROM pad_sounds ps
      INNER JOIN pads p ON p.id = ps.pad_id
      WHERE p.board_id = ?
      ''',
      variables: [Variable<int>(boardId)],
    ).get();
    return rows.map((r) => r.read<int>('sound_id')).toSet();
  }

  /// Premier pad (ordre de la board) contenant chaque son.
  Future<Map<int, int>> getSoundIdToFirstPadIdInBoard(int boardId) async {
    final rows = await _database.customSelect(
      '''
      SELECT ps.sound_id, ps.pad_id
      FROM pad_sounds ps
      INNER JOIN pads p ON p.id = ps.pad_id
      WHERE p.board_id = ?
      ORDER BY p.sort_order, p.created_at, ps.sort_order, ps.added_at
      ''',
      variables: [Variable<int>(boardId)],
    ).get();
    final map = <int, int>{};
    for (final row in rows) {
      final soundId = row.read<int>('sound_id');
      map.putIfAbsent(soundId, () => row.read<int>('pad_id'));
    }
    return map;
  }
}
