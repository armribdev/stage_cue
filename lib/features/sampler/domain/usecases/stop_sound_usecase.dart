import '../../../../core/audio/audio_player_service.dart';

/// Use case pour arrêter un son
class StopSoundUseCase {
  final AudioPlayerService _audioPlayer;

  StopSoundUseCase(this._audioPlayer);

  Future<void> call() async {
    await _audioPlayer.stop();
  }
}

