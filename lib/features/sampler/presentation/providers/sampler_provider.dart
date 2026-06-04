import 'dart:math';

import 'package:flutter/material.dart';
import '../../../../core/audio/audio_player_service.dart';
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

  SamplerState({
    required this.pads,
    this.isLoading = false,
    this.error,
    this.boards = const [],
    this.selectedBoard,
    this.isBoardsLoading = false,
    this.boardsError,
  });

  SamplerState copyWith({
    List<PadItem>? pads,
    bool? isLoading,
    Object? error = _unset,
    List<SoundBoard>? boards,
    Object? selectedBoard = _unset,
    bool? isBoardsLoading,
    Object? boardsError = _unset,
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
  int? _activeBoardId;
  double _masterVolume = 1.0;
  _RemovedPadSnapshot? _lastRemovedPad;
  final _random = Random();

  SamplerState _state = SamplerState(pads: []);
  SamplerState get state => _state;
  double get masterVolume => _masterVolume;
  bool get canUndoLastRemoval =>
      _lastRemovedPad != null && _lastRemovedPad!.boardId == _activeBoardId;

  SamplerNotifier(
    this._repository,
    this._loadPadsUseCase, [
    this._removePadUseCase,
  ]);

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
        final newBoardId = await _repository.createSoundBoard('Scène 1');
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
      final newBoardId = await _repository.createSoundBoard(name);
      final newBoard = SoundBoard(
        id: newBoardId,
        name: name,
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
      final newBoardId = await _repository.createSoundBoard(newName);
      await _repository.duplicatePads(sourceBoard.id, newBoardId);

      final newBoard = SoundBoard(
        id: newBoardId,
        name: newName,
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
          // Mettre à jour les données du pad sans recréer les players
          existing.pad = pad;
          if (existing.isPlaying) {
            existing.currentPlayer
                ?.setVolume(existing.pad.volume * _masterVolume);
          }
          return existing;
        }

        final players = <AudioPlayerService>[];
        for (final sound in pad.sounds) {
          try {
            players.add(await AudioPlayerService.create(sound.filePath));
          } catch (e) {
            debugPrint('Échec du chargement de ${sound.filePath}: $e');
          }
        }
        if (players.isEmpty && pad.sounds.isNotEmpty) return null;

        final padItem = PadItem(pad: pad, players: players);
        for (var i = 0; i < players.length; i++) {
          final idx = i;
          players[idx].onPlayerStateChanged.listen((playing) {
            if (playing) {
              padItem._currentPlayerIndex = idx;
              padItem.isPlaying = true;
            } else if (padItem._currentPlayerIndex == idx) {
              padItem.isPlaying = false;
              padItem._currentPlayerIndex = null;
            }
            notifyListeners();
          });
        }
        return padItem;
      });

      final items = await Future.wait(loadFutures);
      final padItems = items.whereType<PadItem>().toList();

      _state = _state.copyWith(pads: padItems, isLoading: false);
      final keptIds = padItems.map((item) => item.pad.id).toSet();
      final removedItems =
          previousItems.where((item) => !keptIds.contains(item.pad.id)).toList();
      _disposePadItems(removedItems);
    } catch (e) {
      _state = _state.copyWith(isLoading: false, error: e.toString());
    }
    notifyListeners();
  }

  /// Joue ou arrête le pad selon son mode de lecture.
  Future<void> toggleSound(PadItem padItem) async {
    if (padItem.isPlaying) {
      await padItem.currentPlayer?.stop();
      return;
    }

    if (padItem.players.isEmpty) return;

    final soundIndex = switch (padItem.pad.playMode) {
      PadPlayMode.random => padItem.players.length == 1
          ? 0
          : _random.nextInt(padItem.players.length),
      PadPlayMode.sequential => () {
          final idx = padItem._nextSoundIndex % padItem.players.length;
          padItem._nextSoundIndex = (idx + 1) % padItem.players.length;
          return idx;
        }(),
    };

    final player = padItem.players[soundIndex];
    player.setVolume(padItem.pad.volume * _masterVolume);
    await player.play();
    notifyListeners();
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
          padItem.currentPlayer?.setVolume(nextVolume * _masterVolume);
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

  Future<void> setMasterVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    if (_masterVolume == clamped) return;
    _masterVolume = clamped;
    for (final padItem in _state.pads) {
      if (padItem.isPlaying) {
        padItem.currentPlayer?.setVolume(padItem.pad.volume * _masterVolume);
      }
    }
    notifyListeners();
  }

  Future<void> stopAllSounds() async {
    for (final padItem in _state.pads) {
      if (padItem.isPlaying) {
        await padItem.currentPlayer?.stop();
        padItem.isPlaying = false;
        padItem._currentPlayerIndex = null;
      }
    }
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
