import 'dart:io';
import '../../domain/entities/sound.dart';
import '../../domain/entities/watched_path.dart';
import '../datasources/local_sound_datasource.dart';
import '../models/indexing_progress.dart';
import '../../../../core/database/database.dart' as db;

/// Repository pour la gestion des sons
class SoundRepository {
  final LocalSoundDataSource _soundDataSource;
  final LocalWatchedPathDataSource _watchedPathDataSource;

  SoundRepository(
    this._soundDataSource,
    this._watchedPathDataSource,
  );

  /// Factory method pour créer un repository à partir d'une base de données
  /// Réduit la duplication de code dans les écrans
  factory SoundRepository.fromDatabase(db.AppDatabase database) {
    final soundDataSource = LocalSoundDataSource(database);
    final watchedPathDataSource = LocalWatchedPathDataSource(database);
    return SoundRepository(soundDataSource, watchedPathDataSource);
  }

  /// Récupère tous les sons
  Future<List<Sound>> getAllSounds() async {
    return await _soundDataSource.getAllSounds();
  }

  /// Récupère un son par son ID
  Future<Sound?> getSoundById(int id) async {
    return await _soundDataSource.getSoundById(id);
  }

  /// Indexe un fichier audio
  Future<void> indexAudioFile(File file) async {
    await _soundDataSource.indexAudioFile(file);
  }

  /// Indexe tous les fichiers audio d'un dossier
  Future<int> indexDirectory(
    Directory directory, {
    void Function(IndexingProgress)? onProgress,
  }) async {
    return await _soundDataSource.indexDirectory(directory, onProgress: onProgress);
  }

  /// Scanne tous les chemins surveillés
  Future<int> scanAllWatchedPaths() async {
    return await _watchedPathDataSource.scanAllWatchedPaths(_soundDataSource);
  }

  /// Récupère tous les chemins surveillés
  Future<List<WatchedPath>> getAllWatchedPaths() async {
    return await _watchedPathDataSource.getAllWatchedPaths();
  }

  /// Ajoute un chemin surveillé
  Future<int> addWatchedPath(
    WatchedPath watchedPath, {
    void Function(IndexingProgress)? onProgress,
  }) async {
    final id = await _watchedPathDataSource.insertWatchedPath(watchedPath);
    
    // Indexer automatiquement les fichiers
    try {
      if (watchedPath.isDirectory) {
        await _soundDataSource.indexDirectory(
          Directory(watchedPath.path),
          onProgress: onProgress,
        );
      } else {
        await _soundDataSource.indexAudioFile(File(watchedPath.path));
        // Notifier la progression pour les fichiers (instantané)
        onProgress?.call(IndexingProgress(
          path: watchedPath.path,
          current: 1,
          total: 1,
          isComplete: true,
        ));
      }
    } catch (e) {
      // Notifier l'erreur
      onProgress?.call(IndexingProgress(
        path: watchedPath.path,
        current: 0,
        total: 0,
        isComplete: true,
        error: e.toString(),
      ));
      // Ne pas rethrow pour permettre l'ajout du chemin même si l'indexation échoue
    }
    
    return id;
  }

  /// Supprime un chemin surveillé et ses sons associés
  Future<void> removeWatchedPath(WatchedPath watchedPath) async {
    await _watchedPathDataSource.deleteWatchedPath(watchedPath.id);
    await _soundDataSource.deleteSoundsByPath(
      watchedPath.path,
      watchedPath.isDirectory,
    );
  }

  /// Supprime un son
  Future<void> deleteSound(int id) async {
    await _soundDataSource.deleteSound(id);
  }

  /// Récupère uniquement les sons qui sont dans la board
  Future<List<Sound>> getBoardSounds() async {
    return await _soundDataSource.getBoardSounds();
  }

  /// Ajoute un son à la board
  Future<void> addSoundToBoard(int soundId) async {
    await _soundDataSource.addSoundToBoard(soundId);
  }

  /// Retire un son de la board
  Future<void> removeSoundFromBoard(int soundId) async {
    await _soundDataSource.removeSoundFromBoard(soundId);
  }

  /// Vérifie si un son est dans la board
  Future<bool> isSoundInBoard(int soundId) async {
    return await _soundDataSource.isSoundInBoard(soundId);
  }
}

