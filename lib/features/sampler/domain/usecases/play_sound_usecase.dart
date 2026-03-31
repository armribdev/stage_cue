import '../../../../core/audio/audio_player_service.dart';

/// Use case pour jouer un son
class PlaySoundUseCase {
  final AudioPlayerService _audioPlayer;

  PlaySoundUseCase(this._audioPlayer);

  Future<void> call() async {
    await _audioPlayer.play();
  }
}

