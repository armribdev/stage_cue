import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/audio/audio_player_service.dart';
import 'package:stage_cue/features/sampler/domain/entities/pad.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';
import 'package:stage_cue/features/sampler/presentation/providers/sampler_provider.dart';
import 'package:stage_cue/features/sampler/presentation/widgets/pad_button.dart';

class FakeAudioPlayerService implements AudioPlayerService {
  final StreamController<bool> _controller =
      StreamController<bool>.broadcast();

  @override
  Duration get duration => const Duration(milliseconds: 500);

  @override
  bool get isPlaying => false;

  @override
  Stream<bool> get onPlayerStateChanged => _controller.stream;

  @override
  void dispose() => _controller.close();

  @override
  Future<void> play() async {}

  @override
  Future<void> playFromPosition(Duration position) async {}

  @override
  Duration get position => Duration.zero;

  @override
  void setVolume(double volume) {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> playAtVolume(double volume) async {}

  @override
  void fadeVolumeTo(double to, Duration duration) {}

  @override
  Future<void> fadeOutAndStop(Duration duration) async {}
}

PadItem buildPadItem({String? padName, required String soundTitle}) {
  final sound = Sound(
    id: 1,
    title: soundTitle,
    displayName: null,
    filePath: '/tmp/test.wav',
    type: SoundType.soundEffect,
    createdAt: DateTime(2026, 1, 1),
  );
  final pad = Pad(
    id: 1,
    boardId: 1,
    name: padName,
    sortOrder: 0,
    createdAt: DateTime(2026, 1, 1),
    sounds: [sound],
  );
  return PadItem(pad: pad, players: [FakeAudioPlayerService()]);
}

void main() {
  testWidgets('PadButton affiche le nom du pad si defini', (tester) async {
    final padItem = buildPadItem(padName: 'Nom custom', soundTitle: 'Titre');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PadButton(
            padItem: padItem,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Nom custom'), findsOneWidget);
    expect(find.text('Titre'), findsNothing);
  });

  testWidgets('PadButton fallback sur le titre du son si nom vide', (
    tester,
  ) async {
    final padItem = buildPadItem(padName: null, soundTitle: 'Titre fallback');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PadButton(
            padItem: padItem,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Titre fallback'), findsOneWidget);
  });
}
