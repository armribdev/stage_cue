import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart';
import '../../../../core/database/database.dart' as db;
import '../../../../core/database/sounds.dart' as db_sounds;
import '../../../../core/utils/file_utils.dart' show scanDirectoryForAudioFiles, isAudioFile;
import '../models/sound_model.dart';
import '../models/watched_path_model.dart';
import '../models/indexing_progress.dart';
import '../../domain/entities/sound.dart' as domain;
import '../../domain/entities/watched_path.dart' as domain;

/// Source de données locale pour les sons (base de données)
class LocalSoundDataSource {
  final db.AppDatabase _database;

  LocalSoundDataSource(this._database);

  /// Récupère tous les sons
  Future<List<domain.Sound>> getAllSounds() async {
    final sounds = await _database.select(_database.sounds).get();
    return sounds.map((s) => SoundModel.toEntity(s)).toList();
  }

  /// Récupère uniquement les sons qui sont dans la board, triés par ordre d'ajout
  /// Utilise une jointure SQL pour de meilleures performances et éviter les problèmes de sons supprimés
  Future<List<domain.Sound>> getBoardSounds() async {
    // Utiliser une jointure INNER JOIN pour récupérer uniquement les sons existants
    // et les trier par ordre d'ajout à la board
    final query = _database.select(_database.sounds).join([
      innerJoin(
        _database.boardSounds,
        _database.boardSounds.soundId.equalsExp(_database.sounds.id),
      ),
    ])
      ..orderBy([OrderingTerm(expression: _database.boardSounds.addedAt)]);
    
    final results = await query.get();
    
    // Extraire les sons de la jointure
    return results
        .map((row) => row.readTable(_database.sounds))
        .map((s) => SoundModel.toEntity(s))
        .toList();
  }

  /// Ajoute un son à la board
  Future<void> addSoundToBoard(int soundId) async {
    // Vérifier si le son est déjà dans la board
    final existing = await (_database.select(_database.boardSounds)
          ..where((b) => b.soundId.equals(soundId)))
        .getSingleOrNull();
    
    if (existing == null) {
      await _database.into(_database.boardSounds).insert(
        db.BoardSoundsCompanion.insert(
          soundId: Value(soundId),
          addedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  /// Retire un son de la board
  Future<void> removeSoundFromBoard(int soundId) async {
    await (_database.delete(_database.boardSounds)
          ..where((b) => b.soundId.equals(soundId)))
        .go();
  }

  /// Vérifie si un son est dans la board
  Future<bool> isSoundInBoard(int soundId) async {
    final result = await (_database.select(_database.boardSounds)
          ..where((b) => b.soundId.equals(soundId)))
        .getSingleOrNull();
    return result != null;
  }

  /// Récupère un son par son ID
  Future<domain.Sound?> getSoundById(int id) async {
    final sound = await (_database.select(_database.sounds)
          ..where((s) => s.id.equals(id)))
        .getSingleOrNull();
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
    await (_database.delete(_database.sounds)
          ..where((s) => s.id.equals(id)))
        .go();
  }

  /// Indexe un fichier audio
  Future<void> indexAudioFile(File file) async {
    try {
      // Vérifier si le fichier existe déjà dans la base de données
      final existingSounds = await (_database.select(_database.sounds)
            ..where((s) => s.filePath.equals(file.path)))
          .get();
      
      if (existingSounds.isNotEmpty) {
        // Le fichier est déjà indexé
        return;
      }

      // Extraire le nom du fichier sans extension pour le titre
      final title = p.basenameWithoutExtension(file.path);
      
      // Ajouter le fichier à la base de données
      await _database.into(_database.sounds).insert(
        db.SoundsCompanion.insert(
          title: title,
          filePath: file.path,
          type: db_sounds.SoundType.soundEffect,
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
        onProgress?.call(IndexingProgress(
          path: directory.path,
          current: 0,
          total: 0,
          isComplete: true,
          error: 'Le dossier n\'existe pas',
        ));
        return 0;
      }

      // Notifier le début du scan
      onProgress?.call(IndexingProgress(
        path: directory.path,
        current: 0,
        total: 0,
        isComplete: false,
      ));

      final audioFiles = await scanDirectoryForAudioFiles(directory);
      
      // Notifier le nombre total de fichiers trouvés
      onProgress?.call(IndexingProgress(
        path: directory.path,
        current: 0,
        total: audioFiles.length,
        isComplete: false,
      ));
      
      int indexedCount = 0;
      int processedCount = 0;
      
      for (final file in audioFiles) {
        try {
          processedCount++;
          
          // Vérifier si le fichier existe déjà dans la base de données
          final existingSounds = await (_database.select(_database.sounds)
                ..where((s) => s.filePath.equals(file.path)))
              .get();
          
          if (existingSounds.isNotEmpty) {
            // Le fichier est déjà indexé
            onProgress?.call(IndexingProgress(
              path: directory.path,
              current: processedCount,
              total: audioFiles.length,
              isComplete: false,
            ));
            continue;
          }

          // Extraire le nom du fichier sans extension pour le titre
          final title = p.basenameWithoutExtension(file.path);
          
          // Ajouter le fichier à la base de données
          await _database.into(_database.sounds).insert(
            db.SoundsCompanion.insert(
              title: title,
              filePath: file.path,
              type: db_sounds.SoundType.soundEffect,
            ),
          );
          indexedCount++;
          
          // Notifier la progression
          onProgress?.call(IndexingProgress(
            path: directory.path,
            current: processedCount,
            total: audioFiles.length,
            isComplete: false,
          ));
        } catch (e) {
          // Continuer avec les autres fichiers même en cas d'erreur
          processedCount++;
          onProgress?.call(IndexingProgress(
            path: directory.path,
            current: processedCount,
            total: audioFiles.length,
            isComplete: false,
          ));
        }
      }
      
      // Notifier la fin de l'indexation
      onProgress?.call(IndexingProgress(
        path: directory.path,
        current: processedCount,
        total: audioFiles.length,
        isComplete: true,
      ));
      
      return indexedCount;
    } catch (e) {
      print('Erreur lors de l\'indexation du dossier ${directory.path}: $e');
      // Notifier l'erreur
      onProgress?.call(IndexingProgress(
        path: directory.path,
        current: 0,
        total: 0,
        isComplete: true,
        error: e.toString(),
      ));
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
        await (_database.delete(_database.sounds)
              ..where((s) => s.id.equals(sound.id)))
            .go();
      }
    } else {
      await (_database.delete(_database.sounds)
            ..where((s) => s.filePath.equals(path)))
          .go();
    }
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
    await (_database.delete(_database.watchedPaths)
          ..where((w) => w.id.equals(id)))
        .go();
  }

  /// Scanne tous les chemins surveillés et indexe les nouveaux fichiers
  Future<int> scanAllWatchedPaths(LocalSoundDataSource soundDataSource) async {
    final watchedPaths = await getAllWatchedPaths();
    print('Début du scan de ${watchedPaths.length} chemin(s) surveillé(s)');
    int totalIndexed = 0;
    
    for (final watchedPath in watchedPaths) {
      try {
        if (watchedPath.isDirectory) {
          print('Scan du dossier: ${watchedPath.path}');
          final directory = Directory(watchedPath.path);
          if (await directory.exists()) {
            final count = await soundDataSource.indexDirectory(directory);
            totalIndexed += count;
            print('Dossier ${watchedPath.path}: $count nouveau(x) fichier(s) indexé(s)');
          } else {
            print('Le dossier n\'existe pas: ${watchedPath.path}');
          }
        } else {
          print('Indexation du fichier: ${watchedPath.path}');
          final file = File(watchedPath.path);
          if (await file.exists() && isAudioFile(file.path)) {
            await soundDataSource.indexAudioFile(file);
            totalIndexed++;
            print('Fichier indexé: ${watchedPath.path}');
          } else {
            if (!await file.exists()) {
              print('Le fichier n\'existe pas: ${watchedPath.path}');
            } else if (!isAudioFile(file.path)) {
              print('Le fichier n\'est pas un fichier audio: ${watchedPath.path}');
            }
          }
        }
      } catch (e) {
        print('Erreur lors du scan de ${watchedPath.path}: $e');
      }
    }
    
    print('Scan terminé: $totalIndexed nouveau(x) fichier(s) indexé(s) au total');
    return totalIndexed;
  }
}

