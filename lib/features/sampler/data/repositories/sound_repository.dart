import 'dart:io';
import '../../domain/entities/sound.dart';
import '../../domain/entities/sound_board.dart';
import '../../domain/entities/watched_path.dart';
import '../datasources/local_sound_datasource.dart';
import '../datasources/local_tag_datasource.dart';
import '../models/indexing_progress.dart';
import '../../../../core/database/database.dart' as db;
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';

/// Repository pour la gestion des sons
class SoundRepository {
  final LocalSoundDataSource _soundDataSource;
  final LocalWatchedPathDataSource _watchedPathDataSource;
  final LocalSoundBoardDataSource _soundBoardDataSource;
  final LocalTagDataSource _tagDataSource;

  SoundRepository(
    this._soundDataSource,
    this._watchedPathDataSource,
    this._soundBoardDataSource,
    this._tagDataSource,
  );

  /// Factory method pour créer un repository à partir d'une base de données
  /// Réduit la duplication de code dans les écrans
  factory SoundRepository.fromDatabase(db.AppDatabase database) {
    final soundDataSource = LocalSoundDataSource(database);
    final watchedPathDataSource = LocalWatchedPathDataSource(database);
    final soundBoardDataSource = LocalSoundBoardDataSource(database);
    final tagDataSource = LocalTagDataSource(database);
    return SoundRepository(
      soundDataSource,
      watchedPathDataSource,
      soundBoardDataSource,
      tagDataSource,
    );
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

  /// Met à jour les réglages d'un son (couleur, volume)
  Future<void> updateSoundSettings({
    required int id,
    int? colorValue,
    bool updateColor = false,
    String? displayName,
    bool updateDisplayName = false,
    double? volume,
  }) async {
    await _soundDataSource.updateSoundSettings(
      id: id,
      colorValue: colorValue,
      updateColor: updateColor,
      displayName: displayName,
      updateDisplayName: updateDisplayName,
      volume: volume,
    );
  }

  /// Récupère uniquement les sons qui sont dans la board
  Future<List<Sound>> getBoardSounds(int boardId) async {
    return await _soundDataSource.getBoardSounds(boardId);
  }

  /// Ajoute un son à la board
  Future<void> addSoundToBoard(int boardId, int soundId) async {
    await _soundDataSource.addSoundToBoard(boardId, soundId);
  }

  /// Retire un son de la board
  Future<void> removeSoundFromBoard(int boardId, int soundId) async {
    await _soundDataSource.removeSoundFromBoard(boardId, soundId);
  }

  /// Réordonne les sons de la board selon la liste fournie
  Future<void> reorderBoardSounds(int boardId, List<int> soundIdsInOrder) async {
    await _soundDataSource.reorderBoardSounds(boardId, soundIdsInOrder);
  }

  /// Vérifie si un son est dans la board
  Future<bool> isSoundInBoard(int boardId, int soundId) async {
    return await _soundDataSource.isSoundInBoard(boardId, soundId);
  }

  /// Récupère toutes les soundboards
  Future<List<SoundBoard>> getSoundBoards() async {
    return await _soundBoardDataSource.getAllBoards();
  }

  /// Crée une soundboard
  Future<int> createSoundBoard(String name) async {
    return await _soundBoardDataSource.createBoard(name);
  }

  /// Renomme une soundboard
  Future<void> renameSoundBoard(int boardId, String name) async {
    await _soundBoardDataSource.renameBoard(boardId, name);
  }

  /// Supprime une soundboard
  Future<void> deleteSoundBoard(int boardId) async {
    await _soundBoardDataSource.deleteBoard(boardId);
  }

  /// Récupère le catalogue des tags (catégories + tags)
  Future<List<TagCategoryWithTags>> getTagCatalog() async {
    return await _tagDataSource.getCatalog();
  }

  /// Récupère les tags associés à un son
  Future<List<TagItem>> getTagsForSound(int soundId) async {
    return await _tagDataSource.getTagsForSound(soundId);
  }

  /// Met à jour les tags d'un son
  Future<void> setTagsForSound(int soundId, List<int> tagIds) async {
    await _tagDataSource.setTagsForSound(soundId, tagIds);
  }

  /// Recherche des sons par tags/synonymes
  Future<Set<int>> findSoundIdsByTagQuery(String query) async {
    return await _tagDataSource.findSoundIdsByTagQuery(query);
  }
}

