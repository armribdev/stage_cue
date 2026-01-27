import 'package:flutter/foundation.dart';
import '../../../../core/audio/audio_player_service.dart';
import '../../domain/entities/sound.dart';
import '../../domain/usecases/load_sounds_usecase.dart';
import '../../domain/usecases/remove_sound_from_board_usecase.dart';

/// État du sampler
class SamplerState {
  final List<SoundItem> sounds;
  final bool isLoading;
  final String? error;

  SamplerState({
    required this.sounds,
    this.isLoading = false,
    this.error,
  });

  SamplerState copyWith({
    List<SoundItem>? sounds,
    bool? isLoading,
    String? error,
  }) {
    return SamplerState(
      sounds: sounds ?? this.sounds,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

/// Item de son avec son lecteur audio associé
class SoundItem {
  final Sound sound;
  final AudioPlayerService player;
  bool isPlaying;

  SoundItem({
    required this.sound,
    required this.player,
    this.isPlaying = false,
  });
}

/// Provider/Notifier pour la gestion de l'état du sampler
class SamplerNotifier extends ChangeNotifier {
  final LoadSoundsUseCase _loadSoundsUseCase;
  final RemoveSoundFromBoardUseCase? _removeSoundFromBoardUseCase;

  SamplerState _state = SamplerState(sounds: []);
  SamplerState get state => _state;

  SamplerNotifier(
    this._loadSoundsUseCase, [
    this._removeSoundFromBoardUseCase,
  ]);

  /// Charge tous les sons
  Future<void> loadSounds() async {
    _state = _state.copyWith(isLoading: true, error: null);
    notifyListeners();

    try {
      final sounds = await _loadSoundsUseCase();
      
      // Créer les SoundItems avec leurs lecteurs audio
      final soundItems = sounds.map((sound) {
        final player = AudioPlayerService();
        final soundItem = SoundItem(sound: sound, player: player);
        
        // Écouter les changements d'état après avoir créé le SoundItem
        player.onPlayerStateChanged.listen((isPlaying) {
          // Utiliser directement la référence au soundItem
          soundItem.isPlaying = isPlaying;
          notifyListeners();
        });
        
        return soundItem;
      }).toList();

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
      await soundItem.player.play(soundItem.sound.filePath);
      // L'état sera mis à jour automatiquement par le listener
    }
    // Notifier immédiatement pour un feedback visuel rapide
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

  /// Retire un son de la board
  Future<void> removeSound(SoundItem soundItem) async {
    soundItem.player.dispose();
    
    // Retirer le son de la board dans la base de données
    if (_removeSoundFromBoardUseCase != null) {
      try {
        await _removeSoundFromBoardUseCase!(soundItem.sound.id);
      } catch (e) {
        // En cas d'erreur, on continue quand même pour retirer de l'UI
        print('Erreur lors du retrait du son de la board: $e');
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
}

