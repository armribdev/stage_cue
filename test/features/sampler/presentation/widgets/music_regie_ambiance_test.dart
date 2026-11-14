import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/features/sampler/domain/entities/pad.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';
import 'package:stage_cue/features/sampler/presentation/providers/sampler_provider.dart';
import 'package:stage_cue/features/sampler/presentation/widgets/music_preview_panel.dart';

PadItem _ambiancePad({
  required String name,
  required bool isPlaying,
  int variants = 1,
}) {
  final sounds = [
    for (var i = 0; i < variants; i++)
      Sound(
        id: i + 1,
        title: '$name $i',
        displayName: '$name $i',
        filePath: '/tmp/ambiance$i.wav',
        type: SoundType.ambiance,
        createdAt: DateTime(2026, 1, 1),
      ),
  ];
  final pad = Pad(
    id: 42,
    boardId: 1,
    name: name,
    sortOrder: 0,
    createdAt: DateTime(2026, 1, 1),
    sounds: sounds,
  );
  return PadItem(pad: pad, isPlaying: isPlaying);
}

class _Calls {
  int choose = 0;
  int stop = 0;
}

Future<_Calls> _pumpPanel(
  WidgetTester tester, {
  PadItem? ambiance,
  AmbianceTransition? transition,
  bool isAdvanced = true,
}) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final calls = _Calls();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: MusicPreviewPanel(
            state: SamplerState(pads: const [], currentAmbiancePad: ambiance),
            musicVolume: 1,
            resolveMusicPad: (_) => null,
            isAdvanced: isAdvanced,
            isDesktop: true,
            onAdvancedChanged: (_) {},
            onChooseMusic: () {},
            ambianceTransition: transition,
            onChooseAmbiance: () => calls.choose++,
            onStopAmbiance: (_) => calls.stop++,
          ),
        ),
      ),
    ),
  );
  // Pas de pumpAndSettle : le clignotement d'un fondu en cours boucle sans fin.
  await tester.pump(const Duration(milliseconds: 400));
  return calls;
}

IconButton _buttonWithTooltip(WidgetTester tester, String tooltip) =>
    tester.widget<IconButton>(
      find
          .ancestor(
            of: find.byTooltip(tooltip),
            matching: find.byType(IconButton),
          )
          .first,
    );

/// Le badge de progression d'un fondu est le seul indicateur du tiroir : il
/// appartient au bouton dont il tombe dans le rectangle.
bool _hasBadge(WidgetTester tester, String tooltip) {
  final button = tester.getRect(find.byTooltip(tooltip));
  return find
      .byType(CircularProgressIndicator)
      .evaluate()
      .map((e) => tester.getCenter(find.byElementPredicate((x) => x == e)))
      .any(button.contains);
}

void main() {
  group('voie ambiance du tiroir ouvert', () {
    testWidgets('sans ambiance : invite à en lancer une', (tester) async {
      final calls = await _pumpPanel(tester);

      expect(find.text('Aucune ambiance'), findsOneWidget);
      expect(find.text('Lancez une ambiance'), findsOneWidget);
      expect(find.byTooltip('Arrêter l\'ambiance'), findsNothing);

      await tester.tap(find.byTooltip('Lancer une ambiance'));
      expect(calls.choose, 1);
      expect(calls.stop, 0);
    });

    testWidgets('à l\'antenne : nom, arrêt et changement', (tester) async {
      final calls = await _pumpPanel(
        tester,
        ambiance: _ambiancePad(name: 'Forêt', isPlaying: true),
      );

      expect(find.text('Forêt'), findsOneWidget);
      expect(find.text('Aucune ambiance'), findsNothing);
      expect(find.text('Lancez une ambiance'), findsNothing);

      await tester.tap(find.byTooltip('Arrêter l\'ambiance'));
      expect(calls.stop, 1);

      await tester.tap(find.byTooltip('Changer d\'ambiance'));
      expect(calls.choose, 1);
    });

    testWidgets('une ambiance chargée mais arrêtée compte comme au repos', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        ambiance: _ambiancePad(name: 'Forêt', isPlaying: false),
      );

      expect(find.text('Aucune ambiance'), findsOneWidget);
      expect(find.byTooltip('Arrêter l\'ambiance'), findsNothing);
    });

    testWidgets('plusieurs variantes : le sous-titre les compte', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        ambiance: _ambiancePad(name: 'Pluie', isPlaying: true, variants: 3),
      );

      expect(find.text('3 variantes'), findsOneWidget);
    });
  });

  group('fondu en cours sur la voie ambiance', () {
    final pad = _ambiancePad(name: 'Forêt', isPlaying: true);

    testWidgets('sans fondu : commandes actives, aucun badge', (tester) async {
      await _pumpPanel(tester, ambiance: pad);

      expect(
        _buttonWithTooltip(tester, 'Arrêter l\'ambiance').onPressed,
        isNotNull,
      );
      expect(
        _buttonWithTooltip(tester, 'Changer d\'ambiance').onPressed,
        isNotNull,
      );
      expect(_hasBadge(tester, 'Arrêter l\'ambiance'), isFalse);
      expect(_hasBadge(tester, 'Changer d\'ambiance'), isFalse);
    });

    testWidgets('arrêt en fondu : commandes figées, badge sur l\'arrêt', (
      tester,
    ) async {
      final calls = await _pumpPanel(
        tester,
        ambiance: pad,
        transition: const AmbianceTransition(
          id: 1,
          kind: AmbianceTransitionKind.fadeOut,
          duration: Duration(seconds: 2),
        ),
      );

      expect(_buttonWithTooltip(tester, 'Arrêter l\'ambiance').onPressed, null);
      expect(_buttonWithTooltip(tester, 'Changer d\'ambiance').onPressed, null);
      expect(_hasBadge(tester, 'Arrêter l\'ambiance'), isTrue);
      expect(_hasBadge(tester, 'Changer d\'ambiance'), isFalse);

      await tester.tap(find.byTooltip('Arrêter l\'ambiance'));
      expect(
        calls.stop,
        0,
        reason: 'un second arrêt pendant le fondu est ignoré',
      );
    });

    testWidgets('fondu enchaîné : badge sur le bouton de changement', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        ambiance: pad,
        transition: const AmbianceTransition(
          id: 2,
          kind: AmbianceTransitionKind.crossfade,
          duration: Duration(seconds: 2),
        ),
      );

      expect(_hasBadge(tester, 'Changer d\'ambiance'), isTrue);
      expect(_hasBadge(tester, 'Arrêter l\'ambiance'), isFalse);
      expect(_buttonWithTooltip(tester, 'Arrêter l\'ambiance').onPressed, null);
    });

    testWidgets('la progression du badge suit la durée du fondu', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        ambiance: pad,
        transition: const AmbianceTransition(
          id: 3,
          kind: AmbianceTransitionKind.fadeOut,
          duration: Duration(seconds: 4),
        ),
      );

      double progress() => tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value!;

      final early = progress();
      await tester.pump(const Duration(seconds: 2));
      final mid = progress();
      expect(early, lessThan(0.2));
      expect(mid, closeTo(0.5, 0.15));
    });
  });

  group('bandeau réduit', () {
    testWidgets('au repos : icône seule, sans nom ni arrêt visibles', (
      tester,
    ) async {
      final calls = await _pumpPanel(tester, isAdvanced: false);

      expect(find.text('Forêt'), findsNothing);
      await tester.tap(find.byTooltip('Lancer une ambiance'));
      expect(calls.choose, 1);
    });

    testWidgets('à l\'antenne : la pastille montre le nom et l\'arrêt', (
      tester,
    ) async {
      final calls = await _pumpPanel(
        tester,
        isAdvanced: false,
        ambiance: _ambiancePad(name: 'Forêt', isPlaying: true),
      );

      expect(find.text('Forêt'), findsOneWidget);
      await tester.tap(find.byTooltip('Arrêter l\'ambiance'));
      expect(calls.stop, 1);
    });
  });
}
