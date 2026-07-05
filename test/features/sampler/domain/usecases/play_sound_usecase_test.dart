import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/audio/audio_player_service.dart';
import 'package:stage_cue/features/sampler/domain/usecases/play_sound_usecase.dart';

class FakeAudioPlayerService implements AudioPlayerService {
  bool played = false;

  @override
  Duration get duration => const Duration(milliseconds: 300);

  @override
  bool get isPlaying => played;

  @override
  Stream<bool> get onPlayerStateChanged => const Stream<bool>.empty();

  @override
  void dispose() {}

  @override
  Future<void> play() async {
    played = true;
  }

  @override
  Future<void> playFromPosition(Duration position) async {
    played = true;
  }

  @override
  Duration get position => Duration.zero;

  @override
  void setVolume(double volume) {}

  @override
  Future<void> stop() async {
    played = false;
  }

  @override
  Future<void> playAtVolume(double volume, {Duration startOffset = Duration.zero}) async {
    played = true;
  }

  @override
  Future<void> playOverlapping({
    double volume = 1.0,
    Duration startOffset = Duration.zero,
  }) async {
    played = true;
  }

  @override
  void fadeVolumeTo(double to, Duration duration) {}

  @override
  Future<void> fadeOutAndStop(Duration duration) async {
    played = false;
  }
}

void main() {
  test('PlaySoundUseCase appelle play() du lecteur audio', () async {
    final fakePlayer = FakeAudioPlayerService();
    final useCase = PlaySoundUseCase(fakePlayer);

    await useCase();

    expect(fakePlayer.played, isTrue);
  });
}

