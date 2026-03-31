import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/audio/audio_player_service.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';
import 'package:stage_cue/features/sampler/presentation/providers/sampler_provider.dart';
import 'package:stage_cue/features/sampler/presentation/widgets/pad_button.dart';

class FakeAudioPlayerService implements AudioPlayerService {
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  @override
  Duration get duration => const Duration(milliseconds: 500);

  @override
  bool get isPlaying => false;

  @override
  Stream<bool> get onPlayerStateChanged => _controller.stream;

  @override
  void dispose() {
    _controller.close();
  }

  @override
  Future<void> play() async {}

  @override
  void setVolume(double volume) {}

  @override
  Future<void> stop() async {}
}

SoundItem buildSoundItem({String? displayName, required String title}) {
  return SoundItem(
    sound: Sound(
      id: 1,
      title: title,
      displayName: displayName,
      filePath: '/tmp/test.wav',
      type: SoundType.soundEffect,
      createdAt: DateTime(2026, 1, 1),
    ),
    player: FakeAudioPlayerService(),
  );
}

void main() {
  testWidgets('PadButton affiche displayName si present', (tester) async {
    final soundItem = buildSoundItem(displayName: 'Nom custom', title: 'Titre');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PadButton(
            soundItem: soundItem,
            onTap: () {},
            onRemove: () {},
          ),
        ),
      ),
    );

    expect(find.text('Nom custom'), findsOneWidget);
    expect(find.text('Titre'), findsNothing);
  });

  testWidgets('PadButton fallback sur title si displayName vide', (tester) async {
    final soundItem = buildSoundItem(displayName: '  ', title: 'Titre fallback');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PadButton(
            soundItem: soundItem,
            onTap: () {},
            onRemove: () {},
          ),
        ),
      ),
    );

    expect(find.text('Titre fallback'), findsOneWidget);
  });
}

