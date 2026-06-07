import 'dart:io';
import '../../domain/entities/pad.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/sound_board.dart';
import '../../domain/entities/watched_path.dart';
import '../../../../core/platform/saf_directory_bridge.dart';
import '../datasources/local_sound_datasource.dart';
import '../datasources/local_tag_datasource.dart';
import '../models/indexing_progress.dart';
import '../../../../core/database/database.dart' as db;
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';

/// Repository pour la gestion des sons et des pads
class SoundRepository {
  final LocalSoundDataSource _soundDataSource;
  final LocalWatchedPathDataSource _watchedPathDataSource;
  final LocalSoundBoardDataSource _soundBoardDataSource;
  final LocalTagDataSource _tagDataSource;
  final LocalPadDataSource _padDataSource;

  SoundRepository(
    this._soundDataSource,
    this._watchedPathDataSource,
    this._soundBoardDataSource,
    this._tagDataSource,
    this._padDataSource,
  );

  factory SoundRepository.fromDatabase(db.AppDatabase database) {
    final soundDataSource = LocalSoundDataSource(database);
    final watchedPathDataSource = LocalWatchedPathDataSource(database);
    final soundBoardDataSource = LocalSoundBoardDataSource(database);
    final tagDataSource = LocalTagDataSource(database);
    final padDataSource = LocalPadDataSource(database);
    return SoundRepository(
      soundDataSource,
      watchedPathDataSource,
      soundBoardDataSource,
      tagDataSource,
      padDataSource,
    );
  }

  // ── Sons ──────────────────────────────────────────────────────────────────

  Future<List<Sound>> getAllSounds() async {
    return await _soundDataSource.getAllSounds();
  }

  Future<Sound?> getSoundById(int id) async {
    return await _soundDataSource.getSoundById(id);
  }

  Future<void> indexAudioFile(File file) async {
    await _soundDataSource.indexAudioFile(file);
  }

  Future<int> indexDirectory(
    Directory directory, {
    void Function(IndexingProgress)? onProgress,
  }) async {
    return await _soundDataSource.indexDirectory(
      directory,
      onProgress: onProgress,
    );
  }

  Future<int> scanAllWatchedPaths() async {
    return await _watchedPathDataSource.scanAllWatchedPaths(_soundDataSource);
  }

  Future<void> deleteSound(int id) async {
    await _soundDataSource.deleteSound(id);
  }

  /// Met à jour les réglages globaux d'un son (hors contexte de board).
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

  // ── Chemins surveillés ────────────────────────────────────────────────────

  Future<List<WatchedPath>> getAllWatchedPaths() async {
    return await _watchedPathDataSource.getAllWatchedPaths();
  }

  Future<int> addWatchedPath(
    WatchedPath watchedPath, {
    void Function(IndexingProgress)? onProgress,
    void Function()? onInserted,
  }) async {
    final id = await _watchedPathDataSource.insertWatchedPath(watchedPath);
    onInserted?.call();
    if (!watchedPath.isDirectory) {
      throw ArgumentError(
        'Seuls les dossiers peuvent être indexés : ${watchedPath.path}',
      );
    }

    try {
      if (SafDirectoryBridge.isSafTreeUri(watchedPath.path)) {
        await _soundDataSource.indexContentTree(
          watchedPath.path,
          watchedPathId: id,
          onProgress: onProgress,
        );
      } else {
        await _soundDataSource.indexDirectory(
          Directory(watchedPath.path),
          onProgress: onProgress,
        );
      }
    } catch (e) {
      onProgress?.call(
        IndexingProgress(
          path: watchedPath.path,
          current: 0,
          total: 0,
          isComplete: true,
          error: e.toString(),
        ),
      );
    }
    return id;
  }

  Future<void> updateWatchedPathAccount({
    required int id,
    String? accountEmail,
    String? driveFileId,
  }) async {
    await _watchedPathDataSource.updateWatchedPathAccount(
      id: id,
      accountEmail: accountEmail,
      driveFileId: driveFileId,
    );
  }

  Future<void> removeWatchedPath(WatchedPath watchedPath) async {
    await _watchedPathDataSource.deleteWatchedPath(watchedPath.id);
    await _soundDataSource.deleteSoundsForWatchedPath(
      path: watchedPath.path,
      watchedPathId: watchedPath.id,
      isDirectory: watchedPath.isDirectory,
    );
  }

  // ── Boards ────────────────────────────────────────────────────────────────

  Future<List<SoundBoard>> getSoundBoards() async {
    return await _soundBoardDataSource.getAllBoards();
  }

  Future<int> createSoundBoard(
    String name, {
    int? color,
    int? libraryId,
  }) async {
    return await _soundBoardDataSource.createBoard(
      name,
      color: color,
      libraryId: libraryId,
    );
  }

  Future<void> renameSoundBoard(int boardId, String name) async {
    await _soundBoardDataSource.renameBoard(boardId, name);
  }

  Future<void> deleteSoundBoard(int boardId) async {
    await _soundBoardDataSource.deleteBoard(boardId);
  }

  // ── Pads ──────────────────────────────────────────────────────────────────

  Future<List<Pad>> getBoardPads(int boardId) async {
    return await _padDataSource.getBoardPads(boardId);
  }

  /// Crée un nouveau pad avec un son initial.
  Future<int> createPad(int boardId, int soundId) async {
    return await _padDataSource.createPad(boardId, soundId);
  }

  /// Crée un pad avec réglages complets (utilisé pour l'annulation de suppression).
  Future<int> createPadWithSettings({
    required int boardId,
    required List<int> soundIds,
    String? name,
    int? colorValue,
    double volume = 1.0,
    PadPlayMode playMode = PadPlayMode.random,
    int? sortOrder,
  }) async {
    return await _padDataSource.createPadWithSettings(
      boardId: boardId,
      soundIds: soundIds,
      name: name,
      colorValue: colorValue,
      volume: volume,
      playMode: playMode,
      sortOrder: sortOrder,
    );
  }

  Future<void> deletePad(int padId) async {
    await _padDataSource.deletePad(padId);
  }

  Future<void> addSoundToPad(int padId, int soundId) async {
    await _padDataSource.addSoundToPad(padId, soundId);
  }

  Future<void> removeSoundFromPad(int padId, int soundId) async {
    await _padDataSource.removeSoundFromPad(padId, soundId);
  }

  Future<void> reorderBoardPads(int boardId, List<int> padIdsInOrder) async {
    await _padDataSource.reorderBoardPads(boardId, padIdsInOrder);
  }

  Future<void> updatePadSettings({
    required int padId,
    String? name,
    bool updateName = false,
    int? colorValue,
    bool updateColor = false,
    double? volume,
    PadPlayMode? playMode,
  }) async {
    await _padDataSource.updatePadSettings(
      padId: padId,
      name: name,
      updateName: updateName,
      colorValue: colorValue,
      updateColor: updateColor,
      volume: volume,
      playMode: playMode,
    );
  }

  Future<void> duplicatePads(int sourceBoardId, int targetBoardId) async {
    await _padDataSource.duplicatePads(sourceBoardId, targetBoardId);
  }

  Future<Set<int>> getSoundIdsInBoard(int boardId) async {
    return await _padDataSource.getSoundIdsInBoard(boardId);
  }

  Future<Map<int, int>> getSoundIdToFirstPadIdInBoard(int boardId) async {
    return await _padDataSource.getSoundIdToFirstPadIdInBoard(boardId);
  }

  // ── Tags ──────────────────────────────────────────────────────────────────

  Future<List<TagCategoryWithTags>> getTagCatalog() async {
    return await _tagDataSource.getCatalog();
  }

  Future<List<TagItem>> getTagsForSound(int soundId) async {
    return await _tagDataSource.getTagsForSound(soundId);
  }

  Future<void> setTagsForSound(int soundId, List<int> tagIds) async {
    await _tagDataSource.setTagsForSound(soundId, tagIds);
  }

  Future<Set<int>> findSoundIdsByTagQuery(String query) async {
    return await _tagDataSource.findSoundIdsByTagQuery(query);
  }
}
