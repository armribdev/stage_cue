import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/audio/audio_player_service.dart';
import 'package:stage_cue/core/theme/app_icons.dart';
import 'package:stage_cue/features/sampler/domain/entities/pad.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';
import 'package:stage_cue/features/sampler/presentation/models/pad_sound_slot.dart';
import 'package:stage_cue/features/sampler/presentation/providers/sampler_provider.dart';
import 'package:stage_cue/features/sampler/presentation/widgets/pad_button.dart';
import '../../../../support/find_stroke_icon.dart';

class FakeAudioPlayerService implements AudioPlayerService {
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

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
  }) async => true;

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
  String? lastStartFailure;

  @override
  Future<bool> playOverlapping({
    double volume = 1.0,
    Duration startOffset = Duration.zero,
  }) async => true;

  @override
  void fadeVolumeTo(double to, Duration duration) {}

  @override
  Future<void> fadeEnvelope(
    double level,
    Duration duration, {
    required bool fadeIn,
    FadeCurve curve = FadeCurve.cubic,
  }) async {}
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
          body: PadButton(padItem: padItem, onTap: () {}),
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
          body: PadButton(padItem: padItem, onTap: () {}),
        ),
      ),
    );

    expect(find.text('Titre fallback'), findsOneWidget);
  });

  testWidgets('les icônes d édition sont en bas à droite, sous le titre', (
    tester,
  ) async {
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

    // Le titre garde toute la largeur : plus de coupure autour des icônes.
    final title = tester.getRect(find.textContaining('Aa Bb'));
    final edit = tester.getRect(findStrokeIcon(AppIcons.padEdit));
    final close = tester.getRect(findStrokeIcon(AppIcons.padRemove));
    final pad = tester.getRect(find.byType(PadButton));

    expect(title.bottom, lessThanOrEqualTo(edit.top));
    expect(edit.right, lessThan(close.left));
    // Le glyphe est centré dans sa zone de clic (20 px), sans fond visible.
    expect(close.right, greaterThan(pad.right - 20));
    expect(close.bottom, greaterThan(pad.bottom - 20));
  });

  testWidgets('toucher « N sons » ouvre le choix du son, sans icône dédiée '
      'et sans déclencher le pad', (tester) async {
    Sound sound(int id) => Sound(
      id: id,
      title: 'Son $id',
      displayName: null,
      filePath: '/tmp/test$id.wav',
      type: SoundType.soundEffect,
      createdAt: DateTime(2026, 1, 1),
    );
    final padItem = PadItem(
      pad: Pad(
        id: 1,
        boardId: 1,
        name: 'Multi',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
        sounds: [sound(1), sound(2)],
      ),
      slots: [
        for (var i = 0; i < 2; i++)
          PadSoundSlot(
            availability: PadSoundAvailability.ready,
            player: FakeAudioPlayerService(),
          ),
      ],
    );
    var taps = 0;
    var showSounds = 0;

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
                onTap: () => taps++,
                onShowSounds: () => showSounds++,
              ),
            ),
          ),
        ),
      ),
    );

    expect(findStrokeIcon(AppIcons.padSounds), findsNothing);

    await tester.tap(find.text('2 sons'));
    expect(showSounds, 1);
    expect(taps, 0);

    await tester.tap(find.text('Multi'));
    expect(taps, 1);
    expect(showSounds, 1);
  });
}
