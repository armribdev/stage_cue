import 'package:flutter/material.dart';
import '../../../../core/audio/audio_player_service.dart';
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/sound_board.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';
import '../../domain/usecases/load_sounds_usecase.dart';
import '../../domain/usecases/remove_sound_from_board_usecase.dart';

/// État du sampler
class SamplerState {
  final List<SoundItem> sounds;
  final bool isLoading;
  final String? error;
  final List<SoundBoard> boards;
  final SoundBoard? selectedBoard;
  final bool isBoardsLoading;
  final String? boardsError;

  SamplerState({
    required this.sounds,
    this.isLoading = false,
    this.error,
    this.boards = const [],
    this.selectedBoard,
    this.isBoardsLoading = false,
    this.boardsError,
  });

  SamplerState copyWith({
    List<SoundItem>? sounds,
    bool? isLoading,
    String? error,
    List<SoundBoard>? boards,
    SoundBoard? selectedBoard,
    bool? isBoardsLoading,
    String? boardsError,
  }) {
    return SamplerState(
      sounds: sounds ?? this.sounds,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      boards: boards ?? this.boards,
      selectedBoard: selectedBoard ?? this.selectedBoard,
      isBoardsLoading: isBoardsLoading ?? this.isBoardsLoading,
      boardsError: boardsError ?? this.boardsError,
    );
  }
}

/// Item de son avec son lecteur audio associé
class SoundItem {
  Sound sound;
  final AudioPlayerService player;
  bool isPlaying;
  Color? buttonColor;
  double volume;

  SoundItem({
    required this.sound,
    required this.player,
    this.isPlaying = false,
    this.buttonColor,
    this.volume = 1.0,
  });
}

/// Provider/Notifier pour la gestion de l'état du sampler
class SamplerNotifier extends ChangeNotifier {
  final SoundRepository _repository;
  final LoadSoundsUseCase _loadSoundsUseCase;
  final RemoveSoundFromBoardUseCase? _removeSoundFromBoardUseCase;
  int? _activeBoardId;
  double _masterVolume = 1.0;

  SamplerState _state = SamplerState(sounds: []);
  SamplerState get state => _state;
  double get masterVolume => _masterVolume;

  SamplerNotifier(
    this._repository,
    this._loadSoundsUseCase, [
    this._removeSoundFromBoardUseCase,
  ]);

  /// Définit la soundboard active (null pour désactiver)
  void setActiveBoard(int? boardId) {
    _activeBoardId = boardId;
  }

  /// Efface la soundboard active
  void clearActiveBoard() {
    _activeBoardId = null;
  }

  /// Charge toutes les soundboards et sélectionne une board active
  Future<void> loadBoards({int? selectBoardId}) async {
    _state = _state.copyWith(isBoardsLoading: true, boardsError: null);
    notifyListeners();

    try {
      var boards = await _repository.getSoundBoards();
      if (boards.isEmpty) {
        final newBoardId = await _repository.createSoundBoard('Board 1');
        boards = await _repository.getSoundBoards();
        selectBoardId = newBoardId;
      }

      final targetId = selectBoardId ?? _state.selectedBoard?.id ?? boards.first.id;
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

  /// Sélectionne une soundboard
  Future<void> selectBoard(SoundBoard board) async {
    _state = _state.copyWith(selectedBoard: board);
    _activeBoardId = board.id;
    notifyListeners();
    await loadSounds();
  }

  /// Crée une soundboard et la sélectionne
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

  /// Renomme une soundboard
  Future<bool> renameBoard(SoundBoard board, String name) async {
    try {
      await _repository.renameSoundBoard(board.id, name);
      final updatedBoards = _state.boards
          .map((b) => b.id == board.id
              ? SoundBoard(id: b.id, name: name, createdAt: b.createdAt)
              : b)
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

  /// Supprime une soundboard
  Future<bool> deleteBoard(SoundBoard board) async {
    try {
      await _repository.deleteSoundBoard(board.id);
      final updatedBoards = _state.boards.where((b) => b.id != board.id).toList();
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

  /// Charge tous les sons
  Future<void> loadSounds({int? boardId}) async {
    if (boardId != null) {
      _activeBoardId = boardId;
    }
    final currentBoardId = _activeBoardId;
    if (currentBoardId == null) {
      _state = _state.copyWith(sounds: [], isLoading: false);
      notifyListeners();
      return;
    }

    _state = _state.copyWith(isLoading: true, error: null);
    notifyListeners();

    try {
      final sounds = await _loadSoundsUseCase(currentBoardId);

      // Précharger les sons en parallèle pour une latence minimale
      final loadFutures = sounds.map((sound) async {
        try {
          final player = await AudioPlayerService.create(sound.filePath);
          final color =
              sound.colorValue != null ? Color(sound.colorValue!) : null;
          final soundItem = SoundItem(
            sound: sound,
            player: player,
            buttonColor: color,
            volume: sound.volume,
          );

          player.onPlayerStateChanged.listen((isPlaying) {
            soundItem.isPlaying = isPlaying;
            notifyListeners();
          });

          return soundItem;
        } catch (e) {
          debugPrint('Échec du chargement de ${sound.filePath}: $e');
          return null;
        }
      });

      final items = await Future.wait(loadFutures);
      final soundItems = items.whereType<SoundItem>().toList();

      _state = _state.copyWith(
        sounds: soundItems,
        isLoading: false,
      );
    } catch (e) {
      _state = _state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
    notifyListeners();
  }

  /// Joue ou arrête un son
  Future<void> toggleSound(SoundItem soundItem) async {
    if (soundItem.isPlaying) {
      await soundItem.player.stop();
      // L'état sera mis à jour automatiquement par le listener
    } else {
      soundItem.player.setVolume(soundItem.volume * _masterVolume);
      await soundItem.player.play();
      // L'état sera mis à jour automatiquement par le listener
    }
    // Notifier immédiatement pour un feedback visuel rapide
    notifyListeners();
  }

  /// Met à jour les réglages d'un sound item et notifie l'UI
  Future<void> updateSoundItemSettings(
    SoundItem soundItem, {
    Color? buttonColor,
    bool updateColor = false,
    String? displayName,
    bool updateDisplayName = false,
    double? volume,
  }) async {
    var hasChanged = false;
    int? colorValueToSave;
    String? displayNameToSave;
    double? volumeToSave;

    if (updateColor) {
      soundItem.buttonColor = buttonColor;
      colorValueToSave = buttonColor?.toARGB32();
      hasChanged = true;
    }
    if (updateDisplayName) {
      final trimmed = displayName?.trim();
      final normalized = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
      if (soundItem.sound.displayName != normalized) {
        soundItem.sound = Sound(
          id: soundItem.sound.id,
          title: soundItem.sound.title,
          displayName: normalized,
          filePath: soundItem.sound.filePath,
          type: soundItem.sound.type,
          colorValue: soundItem.sound.colorValue,
          volume: soundItem.sound.volume,
          createdAt: soundItem.sound.createdAt,
        );
        displayNameToSave = normalized;
        hasChanged = true;
      }
    }
    if (volume != null) {
      final clamped = volume.clamp(0.0, 1.0);
      if (soundItem.volume != clamped) {
        soundItem.volume = clamped;
        volumeToSave = clamped;
        hasChanged = true;
        if (soundItem.isPlaying) {
          soundItem.player.setVolume(soundItem.volume * _masterVolume);
        }
      }
    }

    if (hasChanged) {
      notifyListeners();
      await _repository.updateSoundSettings(
        id: soundItem.sound.id,
        colorValue: colorValueToSave,
        updateColor: updateColor,
        displayName: displayNameToSave,
        updateDisplayName: updateDisplayName,
        volume: volumeToSave,
      );
    }
  }

  /// Met à jour le volume général
  Future<void> setMasterVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    if (_masterVolume == clamped) {
      return;
    }
    _masterVolume = clamped;
    for (final soundItem in _state.sounds) {
      if (soundItem.isPlaying) {
        soundItem.player.setVolume(soundItem.volume * _masterVolume);
      }
    }
    notifyListeners();
  }

  /// Arrête tous les sons
  Future<void> stopAllSounds() async {
    for (var soundItem in _state.sounds) {
      if (soundItem.isPlaying) {
        await soundItem.player.stop();
        soundItem.isPlaying = false;
      }
    }
    notifyListeners();
  }

  /// Réordonne les sons de la board selon la liste fournie
  Future<void> reorderSoundsFromList(List<SoundItem> newOrder) async {
    if (_activeBoardId == null) return;
    _state = _state.copyWith(sounds: newOrder);
    notifyListeners();
    try {
      await _repository.reorderBoardSounds(
        _activeBoardId!,
        newOrder.map((s) => s.sound.id).toList(),
      );
    } catch (e) {
      debugPrint('Erreur lors du réordonnancement: $e');
      await loadSounds(); // Restaurer l'ordre précédent
    }
  }

  /// Retire un son de la board
  Future<void> removeSound(SoundItem soundItem) async {
    soundItem.player.dispose();
    
    // Retirer le son de la board dans la base de données
    if (_removeSoundFromBoardUseCase != null) {
      try {
        final currentBoardId = _activeBoardId;
        if (currentBoardId != null) {
          await _removeSoundFromBoardUseCase(currentBoardId, soundItem.sound.id);
        }
      } catch (e) {
        // En cas d'erreur, on continue quand même pour retirer de l'UI
        debugPrint('Erreur lors du retrait du son de la board: $e');
      }
    }
    
    _state = _state.copyWith(
      sounds: _state.sounds.where((s) => s != soundItem).toList(),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    for (var soundItem in _state.sounds) {
      soundItem.player.dispose();
    }
    super.dispose();
  }

  /// Charge le catalogue des tags (catégories + tags)
  Future<List<TagCategoryWithTags>> loadTagCatalog() async {
    return await _repository.getTagCatalog();
  }

  /// Récupère les tags d'un son
  Future<List<TagItem>> getTagsForSound(int soundId) async {
    return await _repository.getTagsForSound(soundId);
  }

  /// Met à jour les tags d'un son
  Future<void> updateSoundTags(int soundId, Set<int> tagIds) async {
    await _repository.setTagsForSound(soundId, tagIds.toList());
  }
}

