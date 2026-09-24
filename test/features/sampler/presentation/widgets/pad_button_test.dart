import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/audio/audio_player_service.dart';
import 'package:stage_cue/features/sampler/domain/entities/pad.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';
import 'package:stage_cue/features/sampler/presentation/models/pad_sound_slot.dart';
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
  bool get isPaused => false;

  @override
  Stream<bool> get onPlayerStateChanged => _controller.stream;

  @override
  void dispose() => _controller.close();

  @override
  Future<void> play() async {}

  @override
  Future<bool> playFromPosition(
    Duration position, {
    double volume = 1.0,
    bool looping = false,
    Duration loopStart = Duration.zero,
  }) async =>
      true;

  @override
  Duration get position => Duration.zero;

  @override
  void setVolume(double volume) {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> playAtVolume(
    double volume, {
    Duration startOffset = Duration.zero,
    bool looping = false,
  }) async {}

  @override
  Future<void> playOverlapping({
    double volume = 1.0,
    Duration startOffset = Duration.zero,
  }) async {}

  @override
  void fadeVolumeTo(double to, Duration duration) {}

  @override
  Future<void> fadeEnvelope(
    double level,
    Duration duration, {
    required bool fadeIn,
    FadeCurve curve = FadeCurve.cubic,
  }) async {}

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
  return PadItem(
    pad: pad,
    slots: [
      PadSoundSlot(
        availability: PadSoundAvailability.ready,
        player: FakeAudioPlayerService(),
      ),
    ],
  );
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

  testWidgets(
    'seule la 1re ligne du titre cède la place aux icônes d édition',
    (tester) async {
      final padItem = buildPadItem(
        padName: 'Aa Bb Cc Dd Ee Ff Gg',
        soundTitle: 'Titre',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 180,
                height: 130,
                child: PadButton(
                  padItem: padItem,
                  onTap: () {},
                  isEditable: true,
                  onEdit: () {},
                  onRemove: () {},
                ),
              ),
            ),
          ),
        ),
      );

      // Police de test Ahem : 15px par glyphe. Contenu 156px, moins 50px
      // d'icônes et d'espacement → 106px pour la 1re ligne.
      final firstLine = find.text('Aa Bb');
      final rest = find.text('Cc Dd Ee Ff Gg');
      expect(firstLine, findsOneWidget);
      expect(rest, findsOneWidget);

      expect(
        tester.getSize(rest).width,
        greaterThan(tester.getSize(firstLine).width),
      );
      expect(
        tester.getTopLeft(rest).dx,
        tester.getTopLeft(firstLine).dx,
      );
      // Interligne constant : les icônes, plus hautes qu'une ligne, ne
      // doivent pas repousser la 2e ligne.
      expect(
        tester.getTopLeft(rest).dy,
        tester.getBottomLeft(firstLine).dy,
      );
      expect(
        tester.getTopRight(firstLine).dx,
        lessThanOrEqualTo(tester.getTopLeft(find.byIcon(Icons.edit_outlined)).dx),
      );
    },
  );
}
