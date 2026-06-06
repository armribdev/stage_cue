import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import '../../../../core/audio/audio_player_service.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/pad.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/sound_board.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';
import '../../domain/usecases/load_sounds_usecase.dart';
import '../../domain/usecases/remove_sound_from_board_usecase.dart';

/// État du sampler
class SamplerState {
  static const Object _unset = Object();

  final List<PadItem> pads;
  final bool isLoading;
  final String? error;
  final List<SoundBoard> boards;
  final SoundBoard? selectedBoard;
  final bool isBoardsLoading;
  final String? boardsError;
  final PadItem? currentMusicPad;
  final List<int> musicQueuePadIds;

  SamplerState({
    required this.pads,
    this.isLoading = false,
    this.error,
    this.boards = const [],
    this.selectedBoard,
    this.isBoardsLoading = false,
    this.boardsError,
    this.currentMusicPad,
    this.musicQueuePadIds = const [],
  });

  /// Prochaine musique en file d'attente.
  PadItem? queuedMusicPad(PadItem? Function(int padId) resolve) {
    if (musicQueuePadIds.isEmpty) return null;
    return resolve(musicQueuePadIds.first);
  }

  /// File d'attente résolue.
  List<PadItem> musicQueue(PadItem? Function(int padId) resolve) {
    return musicQueuePadIds
        .map(resolve)
        .whereType<PadItem>()
        .toList(growable: false);
  }

  SamplerState copyWith({
    List<PadItem>? pads,
    bool? isLoading,
    Object? error = _unset,
    List<SoundBoard>? boards,
    Object? selectedBoard = _unset,
    bool? isBoardsLoading,
    Object? boardsError = _unset,
    Object? currentMusicPad = _unset,
    List<int>? musicQueuePadIds,
    bool clearCurrentMusicPad = false,
    bool clearMusicQueue = false,
  }) {
    return SamplerState(
      pads: pads ?? this.pads,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _unset) ? this.error : error as String?,
      boards: boards ?? this.boards,
      selectedBoard: identical(selectedBoard, _unset)
          ? this.selectedBoard
          : selectedBoard as SoundBoard?,
      isBoardsLoading: isBoardsLoading ?? this.isBoardsLoading,
      boardsError: identical(boardsError, _unset)
          ? this.boardsError
          : boardsError as String?,
      currentMusicPad: clearCurrentMusicPad
          ? null
          : identical(currentMusicPad, _unset)
          ? this.currentMusicPad
          : currentMusicPad as PadItem?,
      musicQueuePadIds: clearMusicQueue
          ? const []
          : musicQueuePadIds ?? this.musicQueuePadIds,
    );
  }
}

/// Item de pad avec ses lecteurs audio associés (un par son)
class PadItem {
  Pad pad;
  final List<AudioPlayerService> players;
  bool isPlaying;
  int _nextSoundIndex;
  int? _currentPlayerIndex;

  PadItem({
    required this.pad,
    required this.players,
    this.isPlaying = false,
    int nextSoundIndex = 0,
  }) : _nextSoundIndex = nextSoundIndex;

  /// Lecteur actuellement actif (celui qui joue ou vient de jouer).
  AudioPlayerService? get currentPlayer =>
      _currentPlayerIndex != null && _currentPlayerIndex! < players.length
          ? players[_currentPlayerIndex!]
          : null;

  /// Index du son actuellement joué (pour la clé du TweenAnimationBuilder).
  int? get currentSoundIndex => _currentPlayerIndex;
}

class _RemovedPadSnapshot {
  final int boardId;
  final Pad pad;
  final int index;

  const _RemovedPadSnapshot({
    required this.boardId,
    required this.pad,
    required this.index,
  });
}

/// Provider/Notifier pour la gestion de l'état du sampler
class SamplerNotifier extends ChangeNotifier {
  final SoundRepository _repository;
  final LoadSoundsUseCase _loadPadsUseCase;
  final RemoveSoundFromBoardUseCase? _removePadUseCase;

  /// Optionnel : résout le chemin local jouable d'un son de bibliothèque Drive
  /// (download/cache à la demande). Null = sons purement locaux.
  final LibraryRepository? _libraryRepository;

  int? _activeBoardId;
  double _musicVolume = 1.0;
  _RemovedPadSnapshot? _lastRemovedPad;
  final _random = Random();
  bool _skipMusicAutoAdvance = false;

  /// Pads musique "hors-scène" : créés à la volée depuis le sélecteur pour
  /// jouer une musique dans la régie sans l'ajouter au plateau.
  final Map<int, PadItem> _offStageMusicPads = {};

  SamplerState _state = SamplerState(pads: []);
  SamplerState get state => _state;
  double get musicVolume => _musicVolume;

  /// Volume effectif d'un pad : les pads musique sont en plus soumis
  /// au volume musique global, les autres pads jouent à leur volume propre.
  double _effectiveVolume(PadItem padItem) =>
      padItem.pad.isMusicPad
          ? padItem.pad.volume * _musicVolume
          : padItem.pad.volume;
  bool get canUndoLastRemoval =>
      _lastRemovedPad != null && _lastRemovedPad!.boardId == _activeBoardId;

  SamplerNotifier(
    this._repository,
    this._loadPadsUseCase, [
    this._removePadUseCase,
    this._libraryRepository,
  ]);

  /// Résout le chemin local jouable d'un son (cache Drive si bibliothèque).
  Future<String> _resolvePlayablePath(Sound sound) async {
    final libraryRepository = _libraryRepository;
    String? resolved;
    if (libraryRepository != null) {
      try {
        resolved = await libraryRepository.resolvePlayablePath(sound);
      } catch (e) {
        debugPrint('Résolution du chemin échouée pour ${sound.title}: $e');
      }
    }
    resolved ??= sound.filePath;

    final file = File(resolved);
    if (!await file.exists()) {
      throw StateError(
        'Fichier audio introuvable : ${sound.displayName ?? sound.title}',
      );
    }
    return file.absolute.path;
  }

  Future<void> _loadPlayersForPad(PadItem padItem, Pad pad) async {
    for (final player in padItem.players) {
      player.dispose();
    }
    padItem.players.clear();

    for (final sound in pad.sounds) {
      try {
        final path = await _resolvePlayablePath(sound);
        padItem.players.add(await AudioPlayerService.create(path));
      } catch (e) {
        debugPrint('Échec du chargement de ${sound.filePath}: $e');
      }
    }
    _attachPlayerListeners(padItem);
  }

  void _attachPlayerListeners(PadItem padItem) {
    for (var i = 0; i < padItem.players.length; i++) {
      final idx = i;
      padItem.players[idx].onPlayerStateChanged.listen((playing) {
        if (playing) {
          padItem._currentPlayerIndex = idx;
          padItem.isPlaying = true;
          if (padItem.pad.isMusicPad) {
            _state = _state.copyWith(currentMusicPad: padItem);
          }
        } else if (padItem._currentPlayerIndex == idx) {
          padItem.isPlaying = false;
          padItem._currentPlayerIndex = null;
          if (padItem.pad.isMusicPad) {
            _handleMusicPlaybackEnded(padItem);
          }
        }
        notifyListeners();
      });
    }
  }

  bool _padSoundsChanged(PadItem existing, Pad updated) {
    final previousSounds = existing.pad.sounds;
    if (previousSounds.length != updated.sounds.length) return true;
    for (var i = 0; i < updated.sounds.length; i++) {
      if (previousSounds[i].id != updated.sounds[i].id) return true;
    }
    return false;
  }

  void _disposePadItems(List<PadItem> items) {
    for (final item in items) {
      for (final player in item.players) {
        player.dispose();
      }
    }
  }

  void setActiveBoard(int? boardId) {
    _activeBoardId = boardId;
  }

  void clearActiveBoard() {
    _activeBoardId = null;
  }

  // ── Boards ────────────────────────────────────────────────────────────────

  Future<void> loadBoards({int? selectBoardId}) async {
    _state = _state.copyWith(isBoardsLoading: true, boardsError: null);
    notifyListeners();

    try {
      var boards = await _repository.getSoundBoards();
      if (boards.isEmpty) {
        final libraryId = await _libraryRepository?.singleConnectedLibraryId();
        final newBoardId = await _repository.createSoundBoard(
          'Scène 1',
          libraryId: libraryId,
        );
        boards = await _repository.getSoundBoards();
        selectBoardId = newBoardId;
      }

      final targetId =
          selectBoardId ?? _state.selectedBoard?.id ?? boards.first.id;
      final selected = boards.firstWhere(
        (board) => board.id == targetId,
        orElse: () => boards.first,
      );

      _state = _state.copyWith(
        boards: boards,
        selectedBoard: selected,
        isBoardsLoading: false,
        boardsError: null,
      );
      _activeBoardId = selected.id;
      notifyListeners();

      await loadSounds();
    } catch (e) {
      _state = _state.copyWith(
        isBoardsLoading: false,
        boardsError: e.toString(),
      );
      notifyListeners();
    }
  }

  Future<void> selectBoard(SoundBoard board) async {
    if (_state.selectedBoard?.id == board.id) return;

    await stopAllSounds();
    _lastRemovedPad = null;
    _state = _state.copyWith(selectedBoard: board);
    _activeBoardId = board.id;
    notifyListeners();
    await loadSounds();
  }

  Future<SoundBoard?> createBoard(String name) async {
    try {
      final libraryId = await _libraryRepository?.singleConnectedLibraryId();
      final newBoardId = await _repository.createSoundBoard(
        name,
        libraryId: libraryId,
      );
      final newBoard = SoundBoard(
        id: newBoardId,
        name: name,
        libraryId: libraryId,
        createdAt: DateTime.now(),
      );

      _state = _state.copyWith(
        boards: [..._state.boards, newBoard],
        selectedBoard: newBoard,
        isBoardsLoading: false,
        boardsError: null,
      );
      _activeBoardId = newBoardId;
      notifyListeners();
      await loadSounds();
      return newBoard;
    } catch (e) {
      _state = _state.copyWith(boardsError: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<bool> renameBoard(SoundBoard board, String name) async {
    try {
      await _repository.renameSoundBoard(board.id, name);
      final updatedBoards = _state.boards
          .map(
            (b) => b.id == board.id
                ? SoundBoard(id: b.id, name: name, createdAt: b.createdAt)
                : b,
          )
          .toList();
      final selected = _state.selectedBoard?.id == board.id
          ? SoundBoard(id: board.id, name: name, createdAt: board.createdAt)
          : _state.selectedBoard;

      _state = _state.copyWith(boards: updatedBoards, selectedBoard: selected);
      notifyListeners();
      return true;
    } catch (e) {
      _state = _state.copyWith(boardsError: e.toString());
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteBoard(SoundBoard board) async {
    try {
      await _repository.deleteSoundBoard(board.id);
      final updatedBoards =
          _state.boards.where((b) => b.id != board.id).toList();
      SoundBoard? nextSelected = _state.selectedBoard;
      if (_state.selectedBoard?.id == board.id) {
        nextSelected = updatedBoards.isNotEmpty ? updatedBoards.first : null;
      }

      _state = _state.copyWith(
        boards: updatedBoards,
        selectedBoard: nextSelected,
      );
      _activeBoardId = nextSelected?.id;
      notifyListeners();
      await loadSounds();
      return true;
    } catch (e) {
      _state = _state.copyWith(boardsError: e.toString());
      notifyListeners();
      return false;
    }
  }

  Future<SoundBoard?> duplicateBoard(
    SoundBoard sourceBoard,
    String newName,
  ) async {
    try {
      final newBoardId = await _repository.createSoundBoard(
        newName,
        libraryId: sourceBoard.libraryId,
      );
      await _repository.duplicatePads(sourceBoard.id, newBoardId);

      final newBoard = SoundBoard(
        id: newBoardId,
        name: newName,
        libraryId: sourceBoard.libraryId,
        createdAt: DateTime.now(),
      );
      _state = _state.copyWith(
        boards: [..._state.boards, newBoard],
        selectedBoard: newBoard,
        isBoardsLoading: false,
        boardsError: null,
      );
      _activeBoardId = newBoardId;
      notifyListeners();
      await loadSounds(boardId: newBoardId);
      return newBoard;
    } catch (e) {
      _state = _state.copyWith(boardsError: e.toString());
      notifyListeners();
      return null;
    }
  }

  // ── Pads ──────────────────────────────────────────────────────────────────

  Future<void> loadSounds({int? boardId}) async {
    if (boardId != null) _activeBoardId = boardId;
    _lastRemovedPad = null;
    final currentBoardId = _activeBoardId;
    if (currentBoardId == null) {
      _disposePadItems(_state.pads);
      _state = _state.copyWith(pads: [], isLoading: false);
      notifyListeners();
      return;
    }

    _state = _state.copyWith(isLoading: true, error: null);
    notifyListeners();

    try {
      final pads = await _loadPadsUseCase(currentBoardId);
      final previousItems = _state.pads;
      final previousItemsById = <int, PadItem>{
        for (final item in previousItems) item.pad.id: item,
      };

      final loadFutures = pads.map((pad) async {
        final existing = previousItemsById[pad.id];
        if (existing != null) {
          final soundsChanged = _padSoundsChanged(existing, pad);
          existing.pad = pad;
          if (soundsChanged) {
            await _loadPlayersForPad(existing, pad);
            if (existing.players.isEmpty && pad.sounds.isNotEmpty) {
              return null;
            }
          }
          if (existing.isPlaying) {
            existing.currentPlayer?.setVolume(_effectiveVolume(existing));
          }
          return existing;
        }

        final padItem = PadItem(pad: pad, players: <AudioPlayerService>[]);
        await _loadPlayersForPad(padItem, pad);
        if (padItem.players.isEmpty && pad.sounds.isNotEmpty) return null;
        return padItem;
      });

      final items = await Future.wait(loadFutures);
      final padItems = items.whereType<PadItem>().toList();

      _state = _state.copyWith(pads: padItems, isLoading: false);
      final keptIds = padItems.map((item) => item.pad.id).toSet();
      final removedItems =
          previousItems.where((item) => !keptIds.contains(item.pad.id)).toList();
      _disposePadItems(removedItems);
      _syncMusicStateWithPads();
    } catch (e) {
      _state = _state.copyWith(isLoading: false, error: e.toString());
    }
    notifyListeners();
  }

  /// Joue ou arrête le pad selon son mode de lecture.
  Future<void> toggleSound(PadItem padItem) async {
    if (padItem.pad.isMusicPad) {
      await _toggleMusicPad(padItem);
      return;
    }

    if (padItem.isPlaying) {
      await padItem.currentPlayer?.stop();
      return;
    }

    if (padItem.players.isEmpty) return;

    final soundIndex = _pickSoundIndex(padItem);
    final player = padItem.players[soundIndex];
    player.setVolume(_effectiveVolume(padItem));
    await player.play();
    notifyListeners();
  }

  int _pickSoundIndex(PadItem padItem) {
    return switch (padItem.pad.playMode) {
      PadPlayMode.random => padItem.players.length == 1
          ? 0
          : _random.nextInt(padItem.players.length),
      PadPlayMode.sequential => () {
          final idx = padItem._nextSoundIndex % padItem.players.length;
          padItem._nextSoundIndex = (idx + 1) % padItem.players.length;
          return idx;
        }(),
    };
  }

  Future<void> _toggleMusicPad(PadItem padItem) async {
    if (padItem.players.isEmpty) return;

    final currentMusic = _state.currentMusicPad;

    if (padItem.isPlaying) {
      await _stopMusicPad(padItem, manual: true);
      return;
    }

    if (_state.musicQueuePadIds.contains(padItem.pad.id)) {
      _removeFromMusicQueue(padItem.pad.id);
      return;
    }

    if (currentMusic != null &&
        currentMusic.pad.id != padItem.pad.id &&
        currentMusic.isPlaying) {
      enqueueMusicPad(padItem);
      return;
    }

    await playMusicNow(padItem);
  }

  void _removeFromMusicQueue(int padId) {
    final nextQueue =
        _state.musicQueuePadIds.where((id) => id != padId).toList();
    if (nextQueue.length == _state.musicQueuePadIds.length) return;
    _state = _state.copyWith(musicQueuePadIds: nextQueue);
    notifyListeners();
  }

  void enqueueMusicPad(PadItem padItem) {
    if (padItem.pad.id == _state.currentMusicPad?.pad.id) return;
    if (_state.musicQueuePadIds.contains(padItem.pad.id)) return;
    _state = _state.copyWith(
      musicQueuePadIds: [..._state.musicQueuePadIds, padItem.pad.id],
    );
    notifyListeners();
  }

  Future<void> playMusicNow(PadItem padItem) async {
    if (padItem.players.isEmpty) return;

    final current = _state.currentMusicPad;
    if (current != null &&
        current.pad.id != padItem.pad.id &&
        current.isPlaying) {
      await _stopMusicPad(current, manual: true);
    }

    _state = _state.copyWith(
      musicQueuePadIds: _state.musicQueuePadIds
          .where((id) => id != padItem.pad.id)
          .toList(),
    );
    await _playMusicPad(padItem);
  }

  Future<PadItem?> playMusicBySoundId(int soundId) async {
    final padItem = await _ensureMusicPadForSound(soundId);
    if (padItem == null) return null;
    await playMusicNow(padItem);
    return padItem;
  }

  Future<PadItem?> enqueueMusicBySoundId(int soundId) async {
    final padItem = await _ensureMusicPadForSound(soundId);
    if (padItem == null) return null;

    if (_state.currentMusicPad?.pad.id == padItem.pad.id &&
        (_state.currentMusicPad?.isPlaying ?? false)) {
      return padItem;
    }

    final current = _state.currentMusicPad;
    if (current != null &&
        current.isPlaying &&
        current.pad.id != padItem.pad.id) {
      enqueueMusicPad(padItem);
      return padItem;
    }

    await playMusicNow(padItem);
    return padItem;
  }

  Future<PadItem?> _ensureMusicPadForSound(int soundId) async {
    var existing = _findPadItemForSound(soundId);
    if (existing != null) {
      if (existing.players.isEmpty) {
        await _loadPlayersForPad(existing, existing.pad);
        if (existing.players.isEmpty) {
          _setMusicLoadError();
          return null;
        }
      }
      return existing;
    }

    final boardId = _activeBoardId;
    if (boardId != null) {
      final padIdBySound =
          await _repository.getSoundIdToFirstPadIdInBoard(boardId);
      if (padIdBySound.containsKey(soundId)) {
        await loadSounds(boardId: boardId);
        existing = _findPadItemForSound(soundId);
        if (existing != null) return existing;
      }
    }

    return _createOffStageMusicPad(soundId);
  }

  /// Prépare une musique pour la régie sans l'ajouter au plateau — un son
  /// peut être joué directement sans être lié à un pad sur la scène.
  Future<PadItem?> _createOffStageMusicPad(int soundId) async {
    try {
      final sound = await _repository.getSoundById(soundId);
      if (sound == null) {
        _setMusicLoadError();
        return null;
      }

      final pad = Pad(
        id: -soundId,
        boardId: -1,
        sortOrder: 0,
        createdAt: DateTime.now(),
        sounds: [sound],
      );
      final padItem = PadItem(pad: pad, players: <AudioPlayerService>[]);
      await _loadPlayersForPad(padItem, pad);
      if (padItem.players.isEmpty) {
        _setMusicLoadError();
        return null;
      }
      _offStageMusicPads[pad.id] = padItem;
      return padItem;
    } catch (e) {
      debugPrint('Impossible de préparer la musique pour la régie: $e');
      _state = _state.copyWith(error: 'Impossible de préparer cette musique.');
      notifyListeners();
      return null;
    }
  }

  void _setMusicLoadError() {
    _state = _state.copyWith(
      error: 'Fichier audio introuvable ou indisponible hors-ligne.',
    );
    notifyListeners();
  }

  PadItem? _findPadItemForSound(int soundId) {
    for (final padItem in _state.pads) {
      if (padItem.pad.sounds.any((sound) => sound.id == soundId)) {
        return padItem;
      }
    }
    for (final padItem in _offStageMusicPads.values) {
      if (padItem.pad.sounds.any((sound) => sound.id == soundId)) {
        return padItem;
      }
    }
    return null;
  }

  /// Pad musique correspondant à un son, sur la scène ou hors-scène.
  PadItem? findMusicPadForSound(int soundId) => _findPadItemForSound(soundId);

  Future<void> _playMusicPad(PadItem padItem) async {
    if (padItem.players.isEmpty) {
      await _loadPlayersForPad(padItem, padItem.pad);
      if (padItem.players.isEmpty) {
        _setMusicLoadError();
        return;
      }
    }

    _state = _state.copyWith(
      currentMusicPad: padItem,
      musicQueuePadIds: _state.musicQueuePadIds
          .where((id) => id != padItem.pad.id)
          .toList(),
    );

    final soundIndex = _pickSoundIndex(padItem);
    final player = padItem.players[soundIndex];
    player.setVolume(_effectiveVolume(padItem));
    await player.play();
    notifyListeners();
  }

  Future<void> _stopMusicPad(PadItem padItem, {required bool manual}) async {
    if (manual) {
      _skipMusicAutoAdvance = true;
    }
    try {
      await padItem.currentPlayer?.stop();
    } finally {
      if (manual) {
        _skipMusicAutoAdvance = false;
      }
    }

    var nextState = _state;
    if (_state.currentMusicPad?.pad.id == padItem.pad.id) {
      nextState = nextState.copyWith(clearCurrentMusicPad: true);
    }
    if (_state.musicQueuePadIds.contains(padItem.pad.id)) {
      nextState = nextState.copyWith(
        musicQueuePadIds: nextState.musicQueuePadIds
            .where((id) => id != padItem.pad.id)
            .toList(),
      );
    }
    _state = nextState;
    notifyListeners();
  }

  void _handleMusicPlaybackEnded(PadItem padItem) {
    if (_skipMusicAutoAdvance) return;
    if (_state.currentMusicPad?.pad.id != padItem.pad.id) return;

    final queue = _state.musicQueuePadIds;
    _state = _state.copyWith(clearCurrentMusicPad: true);
    notifyListeners();

    if (queue.isEmpty) return;

    final nextId = queue.first;
    final next = _resolvePadItem(nextId);
    _state = _state.copyWith(musicQueuePadIds: queue.sublist(1));
    notifyListeners();
    if (next != null) {
      unawaited(_playMusicPad(next));
    }
  }

  Future<void> removeFromMusicQueue(int padId) async {
    _removeFromMusicQueue(padId);
  }

  Future<void> clearMusicQueue() async {
    if (_state.musicQueuePadIds.isEmpty) return;
    _state = _state.copyWith(clearMusicQueue: true);
    notifyListeners();
  }

  Future<void> playNextInQueueNow() async {
    if (_state.musicQueuePadIds.isEmpty) return;

    final nextId = _state.musicQueuePadIds.first;
    final next = _resolvePadItem(nextId);
    if (next == null) {
      _state = _state.copyWith(musicQueuePadIds: _state.musicQueuePadIds.sublist(1));
      notifyListeners();
      return;
    }

    final current = _state.currentMusicPad;
    if (current != null && current.isPlaying) {
      await _stopMusicPad(current, manual: true);
    }

    _state = _state.copyWith(musicQueuePadIds: _state.musicQueuePadIds.sublist(1));
    await _playMusicPad(next);
  }

  Future<void> stopCurrentMusic() async {
    final current = _state.currentMusicPad;
    if (current == null || !current.isPlaying) return;
    await _stopMusicPad(current, manual: true);
  }

  /// Fondu sortant de la musique en cours (sans lancer la file).
  /// Une durée nulle coupe immédiatement.
  Future<void> fadeOutCurrentMusic(Duration duration) async {
    final current = _state.currentMusicPad;
    if (current == null || !current.isPlaying) return;
    if (duration == Duration.zero) {
      await _stopMusicPad(current, manual: true);
      return;
    }
    final player = current.currentPlayer;
    if (player == null) return;

    _skipMusicAutoAdvance = true;
    try {
      await player.fadeOutAndStop(duration);
    } finally {
      _skipMusicAutoAdvance = false;
    }

    var nextState = _state;
    if (_state.currentMusicPad?.pad.id == current.pad.id) {
      nextState = nextState.copyWith(clearCurrentMusicPad: true);
    }
    current.isPlaying = false;
    current._currentPlayerIndex = null;
    _state = nextState;
    notifyListeners();
  }

  /// Enchaîne vers la musique suivante en file, avec un fondu enchaîné.
  /// Une durée nulle passe directement à la suivante.
  Future<void> crossfadeToNextMusic(Duration duration) async {
    if (_state.musicQueuePadIds.isEmpty) return;

    final current = _state.currentMusicPad;
    if (duration == Duration.zero || current == null || !current.isPlaying) {
      await playNextInQueueNow();
      return;
    }

    final nextId = _state.musicQueuePadIds.first;
    final next = _resolvePadItem(nextId);
    if (next == null || next.players.isEmpty) {
      _state = _state.copyWith(
        musicQueuePadIds: _state.musicQueuePadIds.sublist(1),
      );
      notifyListeners();
      return;
    }

    final currentPlayer = current.currentPlayer;
    if (currentPlayer == null) return;

    final soundIndex = _pickSoundIndex(next);
    final nextPlayer = next.players[soundIndex];
    final targetVolume = _effectiveVolume(next);
    final crossfadeDuration = duration;

    _skipMusicAutoAdvance = true;
    try {
      _state = _state.copyWith(
        currentMusicPad: next,
        musicQueuePadIds: _state.musicQueuePadIds.sublist(1),
      );
      notifyListeners();

      await nextPlayer.playAtVolume(0);
      next._currentPlayerIndex = soundIndex;
      next.isPlaying = true;

      currentPlayer.fadeVolumeTo(0, crossfadeDuration);
      nextPlayer.fadeVolumeTo(targetVolume, crossfadeDuration);

      await Future<void>.delayed(crossfadeDuration);

      if (currentPlayer.isPlaying) {
        await currentPlayer.stop();
      }
      current.isPlaying = false;
      current._currentPlayerIndex = null;
    } finally {
      _skipMusicAutoAdvance = false;
    }
    notifyListeners();
  }

  Future<void> toggleCurrentMusicPlayback() async {
    final current = _state.currentMusicPad;
    if (current == null) {
      if (_state.musicQueuePadIds.isNotEmpty) {
        await playNextInQueueNow();
      }
      return;
    }
    if (current.isPlaying) {
      await _stopMusicPad(current, manual: true);
      return;
    }
    await playMusicNow(current);
  }

  Future<void> restartCurrentMusic() async {
    final current = _state.currentMusicPad;
    if (current == null || current.players.isEmpty) return;
    if (current.isPlaying) {
      _skipMusicAutoAdvance = true;
      try {
        await current.currentPlayer?.stop();
      } finally {
        _skipMusicAutoAdvance = false;
      }
    }
    await _playMusicPad(current);
  }

  Future<void> skipToNextMusic() async {
    if (_state.musicQueuePadIds.isEmpty) {
      await stopCurrentMusic();
      return;
    }
    await playNextInQueueNow();
  }

  void _clearMusicState() {
    _state = _state.copyWith(
      clearCurrentMusicPad: true,
      clearMusicQueue: true,
    );
  }

  PadItem? _resolvePadItem(int? padId) {
    if (padId == null) return null;
    for (final padItem in _state.pads) {
      if (padItem.pad.id == padId) return padItem;
    }
    return _offStageMusicPads[padId];
  }

  /// Résout un pad musique par id — sur la scène ou hors-scène (régie seule).
  PadItem? resolveMusicPad(int padId) => _resolvePadItem(padId);

  void _syncMusicStateWithPads() {
    final currentId = _state.currentMusicPad?.pad.id;
    final nextCurrent = _resolvePadItem(currentId);
    final nextQueue = _state.musicQueuePadIds
        .where((id) => _resolvePadItem(id) != null && id != nextCurrent?.pad.id)
        .toList();

    if (nextCurrent == _state.currentMusicPad &&
        _listEquals(nextQueue, _state.musicQueuePadIds)) {
      return;
    }

    _state = _state.copyWith(
      currentMusicPad: nextCurrent,
      musicQueuePadIds: nextQueue,
      clearCurrentMusicPad: nextCurrent == null && currentId != null,
    );
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Met à jour les réglages d'un pad et persiste en base.
  Future<void> updatePadItemSettings(
    PadItem padItem, {
    Color? buttonColor,
    bool updateColor = false,
    String? displayName,
    bool updateDisplayName = false,
    double? volume,
    PadPlayMode? playMode,
  }) async {
    var hasChanged = false;
    String? nextName = padItem.pad.name;
    int? nextColor = padItem.pad.colorValue;
    double nextVolume = padItem.pad.volume;
    PadPlayMode? nextPlayMode;

    if (updateColor) {
      nextColor = buttonColor?.toARGB32();
      hasChanged = true;
    }
    if (updateDisplayName) {
      final trimmed = displayName?.trim();
      nextName = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
      if (nextName != padItem.pad.name) hasChanged = true;
    }
    if (volume != null) {
      final clamped = volume.clamp(0.0, 1.0);
      if (clamped != padItem.pad.volume) {
        nextVolume = clamped;
        hasChanged = true;
        if (padItem.isPlaying) {
          final effective = padItem.pad.isMusicPad
              ? nextVolume * _musicVolume
              : nextVolume;
          padItem.currentPlayer?.setVolume(effective);
        }
      }
    }
    if (playMode != null && playMode != padItem.pad.playMode) {
      nextPlayMode = playMode;
      hasChanged = true;
    }

    if (!hasChanged) return;

    padItem.pad = padItem.pad.copyWith(
      name: nextName,
      clearName: updateDisplayName && nextName == null,
      colorValue: nextColor,
      clearColor: updateColor && nextColor == null,
      volume: nextVolume,
      playMode: nextPlayMode,
    );
    notifyListeners();

    await _repository.updatePadSettings(
      padId: padItem.pad.id,
      name: nextName,
      updateName: updateDisplayName,
      colorValue: updateColor ? nextColor : null,
      updateColor: updateColor,
      volume: volume != null ? nextVolume : null,
      playMode: nextPlayMode,
    );
  }

  /// Volume global de la musique — n'affecte que les pads musique.
  Future<void> setMusicVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    if (_musicVolume == clamped) return;
    _musicVolume = clamped;
    for (final padItem in _state.pads) {
      if (padItem.isPlaying && padItem.pad.isMusicPad) {
        padItem.currentPlayer?.setVolume(_effectiveVolume(padItem));
      }
    }
    notifyListeners();
  }

  Future<void> stopAllSounds() async {
    _skipMusicAutoAdvance = true;
    try {
      for (final padItem in _state.pads) {
        if (padItem.isPlaying) {
          await padItem.currentPlayer?.stop();
          padItem.isPlaying = false;
          padItem._currentPlayerIndex = null;
        }
      }
    } finally {
      _skipMusicAutoAdvance = false;
    }
    _clearMusicState();
    notifyListeners();
  }

  Future<void> reorderSoundsFromList(List<PadItem> newOrder) async {
    if (_activeBoardId == null) return;
    _state = _state.copyWith(pads: newOrder);
    notifyListeners();
    try {
      await _repository.reorderBoardPads(
        _activeBoardId!,
        newOrder.map((p) => p.pad.id).toList(),
      );
    } catch (e) {
      debugPrint('Erreur lors du réordonnancement: $e');
      await loadSounds();
    }
  }

  /// Retire un pad de la board.
  Future<bool> removeSound(PadItem padItem) async {
    final currentBoardId = _activeBoardId;
    if (currentBoardId == null) return false;

    final previousIndex = _state.pads.indexOf(padItem);
    if (previousIndex < 0) return false;

    if (_removePadUseCase != null) {
      try {
        await _removePadUseCase(padItem.pad.id);
      } catch (e) {
        debugPrint('Erreur lors du retrait du pad: $e');
        _state = _state.copyWith(error: 'Impossible de retirer ce pad.');
        notifyListeners();
        return false;
      }
    }

    _lastRemovedPad = _RemovedPadSnapshot(
      boardId: currentBoardId,
      pad: padItem.pad,
      index: previousIndex,
    );
    if (padItem.isPlaying) {
      try {
        await padItem.currentPlayer?.stop();
      } catch (_) {}
    }
    for (final player in padItem.players) {
      player.dispose();
    }

    _state = _state.copyWith(
      pads: _state.pads.where((p) => p != padItem).toList(),
      error: null,
    );
    _syncMusicStateWithPads();
    notifyListeners();
    return true;
  }

  /// Annule la dernière suppression de pad.
  Future<int?> undoLastRemoval() async {
    final snapshot = _lastRemovedPad;
    final currentBoardId = _activeBoardId;
    if (snapshot == null || currentBoardId == null) return null;
    if (snapshot.boardId != currentBoardId) return null;

    try {
      await _repository.createPadWithSettings(
        boardId: snapshot.boardId,
        soundIds: snapshot.pad.sounds.map((s) => s.id).toList(),
        name: snapshot.pad.name,
        colorValue: snapshot.pad.colorValue,
        volume: snapshot.pad.volume,
        playMode: snapshot.pad.playMode,
        sortOrder: snapshot.index,
      );

      _lastRemovedPad = null;
      await loadSounds(boardId: snapshot.boardId);
      _state = _state.copyWith(error: null);
      notifyListeners();

      // Retourner l'id du pad restauré (le nouvel id après recréation)
      final restored = _state.pads
          .where((p) => p.pad.sortOrder == snapshot.index)
          .firstOrNull;
      return restored?.pad.id;
    } catch (e) {
      debugPrint('Erreur lors de l\'annulation de suppression: $e');
      _state = _state.copyWith(
        error: 'Impossible d\'annuler la suppression du pad.',
      );
      notifyListeners();
      return null;
    }
  }

  /// Ajoute un son à un pad existant et recharge.
  Future<void> addSoundToPad(int padId, int soundId) async {
    await _repository.addSoundToPad(padId, soundId);
    await loadSounds();
  }

  /// Retire un son d'un pad. Si c'est le dernier son, supprime le pad.
  Future<void> removeSoundFromPad(int padId, int soundId) async {
    final padItem = _state.pads.firstWhere((p) => p.pad.id == padId);
    if (padItem.pad.sounds.length <= 1) {
      await removeSound(padItem);
    } else {
      await _repository.removeSoundFromPad(padId, soundId);
      await loadSounds();
    }
  }

  @override
  void dispose() {
    for (final padItem in _state.pads) {
      for (final player in padItem.players) {
        player.dispose();
      }
    }
    for (final padItem in _offStageMusicPads.values) {
      for (final player in padItem.players) {
        player.dispose();
      }
    }
    super.dispose();
  }

  // ── Sons (bibliothèque) ───────────────────────────────────────────────────

  Future<List<Sound>> getAllSounds() async {
    return await _repository.getAllSounds();
  }

  // ── Tags ──────────────────────────────────────────────────────────────────

  Future<List<TagCategoryWithTags>> loadTagCatalog() async {
    return await _repository.getTagCatalog();
  }

  Future<List<TagItem>> getTagsForSound(int soundId) async {
    return await _repository.getTagsForSound(soundId);
  }

  Future<void> updateSoundTags(int soundId, Set<int> tagIds) async {
    await _repository.setTagsForSound(soundId, tagIds.toList());
  }
}
