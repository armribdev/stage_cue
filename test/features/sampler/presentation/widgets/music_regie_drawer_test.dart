import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/theme/app_icons.dart';
import 'package:stage_cue/core/theme/transport_icon.dart';
import 'package:stage_cue/features/sampler/domain/entities/pad.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';
import 'package:stage_cue/features/sampler/presentation/providers/sampler_provider.dart';
import 'package:stage_cue/features/sampler/presentation/widgets/music_preview_panel.dart';

import '../../../../support/find_stroke_icon.dart';

PadItem _musicPad(int id, String name, {bool isPlaying = false}) {
  final pad = Pad(
    id: id,
    boardId: 1,
    name: name,
    sortOrder: id,
    createdAt: DateTime(2026, 1, 1),
    sounds: [
      Sound(
        id: id,
        title: name,
        displayName: name,
        filePath: '/tmp/music$id.wav',
        type: SoundType.music,
        createdAt: DateTime(2026, 1, 1),
      ),
    ],
  );
  return PadItem(pad: pad, isPlaying: isPlaying);
}

/// Appels reçus par le panneau, dans l'ordre où ils arrivent.
class _Spy {
  int togglePlay = 0;
  int skipNext = 0;
  int eject = 0;
  int chooseMusic = 0;
  int chooseMusicToPlay = 0;
  final fadeOuts = <Duration>[];
  final crossfades = <Duration>[];
  final removed = <int>[];
  final reorders = <(int, int)>[];
  final advanced = <bool>[];
}

const _cut = Duration(milliseconds: 100);

/// Pose le panneau dans un hôte qui rejoue ce que fait le vrai fournisseur
/// (mode avancé, retrait et réordonnancement de la file) : l'écran se met à
/// jour comme en production, ce qui permet de vérifier le résultat visible et
/// pas seulement le rappel.
Future<_Spy> _pumpPanel(
  WidgetTester tester, {
  PadItem? current,
  List<PadItem> queue = const [],
  List<int> unresolvedQueueIds = const [],
  double width = 1000,
  bool isAdvanced = true,
  bool isDesktop = true,
  bool withChooseToPlay = false,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final spy = _Spy();
  final byId = {for (final p in queue) p.pad.id: p};
  var queueIds = [...queue.map((p) => p.pad.id), ...unresolvedQueueIds];
  var advanced = isAdvanced;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Align(
            alignment: Alignment.bottomCenter,
            child: MusicPreviewPanel(
              state: SamplerState(
                pads: const [],
                currentMusicPad: current,
                musicQueuePadIds: queueIds,
              ),
              musicVolume: 1,
              resolveMusicPad: (id) => byId[id],
              isAdvanced: advanced,
              isDesktop: isDesktop,
              onAdvancedChanged: (value) {
                spy.advanced.add(value);
                setState(() => advanced = value);
              },
              onChooseMusic: () => spy.chooseMusic++,
              onChooseMusicToPlay: withChooseToPlay
                  ? () => spy.chooseMusicToPlay++
                  : null,
              onTogglePlayPause: () => spy.togglePlay++,
              onSkipNext: () => spy.skipNext++,
              onEjectMusic: () => spy.eject++,
              onFadeOut: spy.fadeOuts.add,
              onTransitionToNext: spy.crossfades.add,
              onRemoveFromQueue: (padId) {
                spy.removed.add(padId);
                setState(
                  () => queueIds = queueIds.where((id) => id != padId).toList(),
                );
              },
              onReorderMusicQueue: (oldIndex, newIndex) {
                spy.reorders.add((oldIndex, newIndex));
                setState(() {
                  final next = [...queueIds];
                  next.insert(newIndex, next.removeAt(oldIndex));
                  queueIds = next;
                });
              },
            ),
          ),
        ),
      ),
    ),
  );
  // Pas de pumpAndSettle : le clignotement d'un fondu et le voyant ON AIR
  // bouclent sans fin. Deux pas : le second laisse la colonne « à l'antenne »
  // reporter sa hauteur à la file (mode deux colonnes).
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 50));
  return spy;
}

Finder _glyph(TransportGlyph glyph) => find.byWidgetPredicate(
  (widget) => widget is TransportIcon && widget.glyph == glyph,
  description: 'TransportIcon($glyph)',
);

Finder _transportButton(TransportGlyph glyph) =>
    find.ancestor(of: _glyph(glyph), matching: find.byType(IconButton)).first;

bool _isEnabled(WidgetTester tester, TransportGlyph glyph) =>
    tester.widget<IconButton>(_transportButton(glyph)).onPressed != null;

/// Le badge de progression d'un fondu appartient au bouton dont il tombe dans
/// le rectangle.
bool _hasBadge(WidgetTester tester, TransportGlyph glyph) {
  final button = tester.getRect(_transportButton(glyph));
  return find
      .byType(CircularProgressIndicator)
      .evaluate()
      .map((e) => tester.getCenter(find.byElementPredicate((x) => x == e)))
      .any(button.contains);
}

/// Laisse un fondu de [duration] se terminer : l'indicateur s'efface et le
/// minuteur de retour à la coupe sèche se déclenche. Le ticker d'un fondu ne
/// démarre qu'à la première frame qui suit le geste (le temps simulé ne
/// compte qu'à partir de là), d'où le premier `pump()` ; la fin de
/// l'animation et le minuteur demandent ensuite chacun un rebuild.
Future<void> _letFadeFinish(WidgetTester tester, Duration duration) async {
  await tester.pump();
  await tester.pump(duration + const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 50));
}

/// Pause de la piste à l'antenne ; renvoie la durée de fondu transmise.
Future<Duration> _pauseAndFinish(WidgetTester tester, _Spy spy) async {
  final before = spy.fadeOuts.length;
  await tester.tap(_transportButton(TransportGlyph.pause));
  expect(spy.fadeOuts.length, before + 1, reason: 'la pause a bien démarré');
  final used = spy.fadeOuts.last;
  await _letFadeFinish(tester, used);
  return used;
}

void main() {
  group('transport musique', () {
    testWidgets(
      'rien de chargé : lecture ouvre le sélecteur, suivant inactif',
      (tester) async {
        final spy = await _pumpPanel(tester, withChooseToPlay: true);

        expect(find.text('Aucune musique lancée'), findsOneWidget);
        expect(_isEnabled(tester, TransportGlyph.next), isFalse);

        await tester.tap(_transportButton(TransportGlyph.play));
        expect(spy.chooseMusicToPlay, 1);
        expect(spy.togglePlay, 0);
        expect(spy.chooseMusic, 0);

        await tester.tap(_transportButton(TransportGlyph.next));
        expect(spy.skipNext, 0);
      },
    );

    testWidgets('sans sélecteur dédié, lecture retombe sur « ajouter »', (
      tester,
    ) async {
      final spy = await _pumpPanel(tester);

      await tester.tap(_transportButton(TransportGlyph.play));
      expect(spy.chooseMusic, 1);
      expect(spy.chooseMusicToPlay, 0);
    });

    testWidgets('file non vide sans piste : lecture démarre la file', (
      tester,
    ) async {
      final spy = await _pumpPanel(tester, queue: [_musicPad(11, 'Suite')]);

      await tester.tap(_transportButton(TransportGlyph.play));
      expect(spy.togglePlay, 1);
      expect(spy.chooseMusic, 0);
    });

    testWidgets('piste en pause : lecture relance, sans fondu', (tester) async {
      final spy = await _pumpPanel(tester, current: _musicPad(1, 'Ouverture'));

      expect(find.text('Ouverture'), findsOneWidget);
      expect(find.text('ON AIR'), findsNothing);
      await tester.tap(_transportButton(TransportGlyph.play));
      expect(spy.togglePlay, 1);
      expect(spy.fadeOuts, isEmpty);
    });

    testWidgets('piste à l\'antenne : pause passe par un fondu court', (
      tester,
    ) async {
      final spy = await _pumpPanel(
        tester,
        current: _musicPad(1, 'Ouverture', isPlaying: true),
      );

      expect(find.text('ON AIR'), findsOneWidget);
      expect(_glyph(TransportGlyph.pause), findsOneWidget);

      await tester.tap(_transportButton(TransportGlyph.pause));
      expect(spy.fadeOuts, [_cut]);
      expect(spy.togglePlay, 0, reason: 'la pause est un fondu, pas un toggle');

      await _letFadeFinish(tester, _cut);
    });

    testWidgets('suivant sans fondu choisi : passage direct', (tester) async {
      final spy = await _pumpPanel(
        tester,
        current: _musicPad(1, 'Ouverture', isPlaying: true),
        queue: [_musicPad(11, 'Suite')],
      );

      expect(_isEnabled(tester, TransportGlyph.next), isTrue);
      await tester.tap(_transportButton(TransportGlyph.next));

      expect(spy.skipNext, 1);
      expect(spy.crossfades, isEmpty);
      expect(_hasBadge(tester, TransportGlyph.next), isFalse);
    });

    testWidgets('suivant avec une durée choisie : fondu enchaîné', (
      tester,
    ) async {
      final spy = await _pumpPanel(
        tester,
        current: _musicPad(1, 'Ouverture', isPlaying: true),
        queue: [_musicPad(11, 'Suite')],
      );

      await tester.tap(find.text('5'));
      await tester.tap(_transportButton(TransportGlyph.next));
      expect(spy.crossfades, [const Duration(seconds: 5)]);
      expect(spy.skipNext, 0);

      // Retour à la coupe sèche : le suivant redevient un passage direct.
      await _letFadeFinish(tester, const Duration(seconds: 5));
      await tester.tap(_transportButton(TransportGlyph.next));
      expect(spy.skipNext, 1);
      expect(spy.crossfades, hasLength(1));
    });

    testWidgets('éjecter : visible à l\'arrêt seulement, jamais à l\'antenne', (
      tester,
    ) async {
      final spy = await _pumpPanel(tester, current: _musicPad(1, 'Ouverture'));

      expect(find.byTooltip('Éjecter la piste'), findsOneWidget);
      await tester.tap(find.byTooltip('Éjecter la piste'));
      expect(spy.eject, 1);
    });

    testWidgets('éjecter : absent pendant la lecture', (tester) async {
      await _pumpPanel(
        tester,
        current: _musicPad(1, 'Ouverture', isPlaying: true),
      );

      expect(find.byTooltip('Éjecter la piste'), findsNothing);
      expect(_glyph(TransportGlyph.eject), findsNothing);
    });

    testWidgets('bandeau réduit : mêmes commandes de transport', (
      tester,
    ) async {
      final spy = await _pumpPanel(
        tester,
        isAdvanced: false,
        current: _musicPad(1, 'Ouverture'),
      );

      await tester.tap(_transportButton(TransportGlyph.play));
      expect(spy.togglePlay, 1);

      await tester.tap(find.byTooltip('Éjecter la piste'));
      expect(spy.eject, 1);
    });
  });

  group('durées de fondu', () {
    Future<_Spy> pumpPlaying(WidgetTester tester) => _pumpPanel(
      tester,
      current: _musicPad(1, 'Ouverture', isPlaying: true),
      queue: [_musicPad(11, 'Suite')],
    );

    testWidgets('un tap sélectionne : le fondu suivant l\'utilise, une fois', (
      tester,
    ) async {
      final spy = await pumpPlaying(tester);

      await tester.tap(find.text('3'));
      expect(findStrokeIcon(AppIcons.lock), findsNothing);

      expect(await _pauseAndFinish(tester, spy), const Duration(seconds: 3));
      expect(await _pauseAndFinish(tester, spy), _cut);
    });

    testWidgets('re-tap sur la durée choisie la désélectionne', (tester) async {
      final spy = await pumpPlaying(tester);

      await tester.tap(find.text('3'));
      await tester.tap(find.text('3'));

      expect(await _pauseAndFinish(tester, spy), _cut);
    });

    testWidgets('choisir une autre durée remplace la précédente', (
      tester,
    ) async {
      final spy = await pumpPlaying(tester);

      await tester.tap(find.text('1'));
      await tester.tap(find.text('5'));

      expect(await _pauseAndFinish(tester, spy), const Duration(seconds: 5));
    });

    testWidgets('appui long verrouille : la durée survit aux fondus', (
      tester,
    ) async {
      final spy = await pumpPlaying(tester);

      await tester.longPress(find.text('3'));
      expect(findStrokeIcon(AppIcons.lock), findsOneWidget);

      expect(await _pauseAndFinish(tester, spy), const Duration(seconds: 3));
      expect(findStrokeIcon(AppIcons.lock), findsOneWidget);
      expect(await _pauseAndFinish(tester, spy), const Duration(seconds: 3));
      expect(await _pauseAndFinish(tester, spy), const Duration(seconds: 3));
    });

    testWidgets('second appui long déverrouille, la durée reste choisie', (
      tester,
    ) async {
      final spy = await pumpPlaying(tester);

      await tester.longPress(find.text('3'));
      await tester.longPress(find.text('3'));
      expect(findStrokeIcon(AppIcons.lock), findsNothing);

      // Sélection devenue temporaire : utilisée une fois, puis la coupe.
      expect(await _pauseAndFinish(tester, spy), const Duration(seconds: 3));
      expect(await _pauseAndFinish(tester, spy), _cut);
    });

    testWidgets('un tap sur une autre durée lève le verrou', (tester) async {
      final spy = await pumpPlaying(tester);

      await tester.longPress(find.text('3'));
      await tester.tap(find.text('5'));
      await tester.pump();
      expect(findStrokeIcon(AppIcons.lock), findsNothing);

      expect(await _pauseAndFinish(tester, spy), const Duration(seconds: 5));
      expect(await _pauseAndFinish(tester, spy), _cut);
    });

    testWidgets('la coupe lève le verrou et revient au fondu court', (
      tester,
    ) async {
      final spy = await pumpPlaying(tester);

      await tester.longPress(find.text('3'));
      await tester.tap(findStrokeIcon(AppIcons.cut));
      await tester.pump();
      expect(findStrokeIcon(AppIcons.lock), findsNothing);

      expect(await _pauseAndFinish(tester, spy), _cut);
    });

    testWidgets('l\'appui long sur la coupe ne verrouille rien', (
      tester,
    ) async {
      final spy = await pumpPlaying(tester);

      await tester.longPress(findStrokeIcon(AppIcons.cut));
      expect(findStrokeIcon(AppIcons.lock), findsNothing);

      expect(await _pauseAndFinish(tester, spy), _cut);
    });
  });

  group('transition en cours', () {
    testWidgets(
      'fondu de pause : lecture et suivant figés, badge sur lecture',
      (tester) async {
        final spy = await _pumpPanel(
          tester,
          current: _musicPad(1, 'Ouverture', isPlaying: true),
          queue: [_musicPad(11, 'Suite')],
        );
        expect(_isEnabled(tester, TransportGlyph.pause), isTrue);
        expect(_isEnabled(tester, TransportGlyph.next), isTrue);
        expect(_hasBadge(tester, TransportGlyph.pause), isFalse);

        await tester.tap(find.text('3'));
        await tester.tap(_transportButton(TransportGlyph.pause));
        await tester.pump(const Duration(milliseconds: 500));

        expect(_isEnabled(tester, TransportGlyph.pause), isFalse);
        expect(_isEnabled(tester, TransportGlyph.next), isFalse);
        expect(_hasBadge(tester, TransportGlyph.pause), isTrue);
        expect(_hasBadge(tester, TransportGlyph.next), isFalse);

        // Un second geste pendant le fondu est ignoré.
        await tester.tap(_transportButton(TransportGlyph.pause));
        await tester.tap(_transportButton(TransportGlyph.next));
        expect(spy.fadeOuts, hasLength(1));
        expect(spy.skipNext, 0);
        expect(spy.crossfades, isEmpty);

        await _letFadeFinish(tester, const Duration(seconds: 3));
        expect(_isEnabled(tester, TransportGlyph.pause), isTrue);
        expect(_isEnabled(tester, TransportGlyph.next), isTrue);
        expect(_hasBadge(tester, TransportGlyph.pause), isFalse);
      },
    );

    testWidgets('fondu enchaîné : badge sur suivant, commandes figées', (
      tester,
    ) async {
      final spy = await _pumpPanel(
        tester,
        current: _musicPad(1, 'Ouverture', isPlaying: true),
        queue: [_musicPad(11, 'Suite')],
      );

      await tester.tap(find.text('3'));
      await tester.tap(_transportButton(TransportGlyph.next));
      await tester.pump(const Duration(milliseconds: 500));

      expect(_hasBadge(tester, TransportGlyph.next), isTrue);
      expect(_hasBadge(tester, TransportGlyph.pause), isFalse);
      expect(_isEnabled(tester, TransportGlyph.pause), isFalse);
      expect(_isEnabled(tester, TransportGlyph.next), isFalse);

      await tester.tap(_transportButton(TransportGlyph.pause));
      expect(spy.fadeOuts, isEmpty);

      await _letFadeFinish(tester, const Duration(seconds: 3));
      expect(_hasBadge(tester, TransportGlyph.next), isFalse);
      expect(_isEnabled(tester, TransportGlyph.pause), isTrue);
    });

    testWidgets('sans durée choisie, aucun état figé ni badge', (tester) async {
      await _pumpPanel(
        tester,
        current: _musicPad(1, 'Ouverture', isPlaying: true),
        queue: [_musicPad(11, 'Suite')],
      );

      await tester.tap(_transportButton(TransportGlyph.pause));
      await tester.pump(const Duration(milliseconds: 20));

      expect(_isEnabled(tester, TransportGlyph.pause), isTrue);
      expect(_hasBadge(tester, TransportGlyph.pause), isFalse);

      await _letFadeFinish(tester, _cut);
    });

    testWidgets('la progression du badge suit la durée du fondu', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        current: _musicPad(1, 'Ouverture', isPlaying: true),
      );

      await tester.tap(find.text('5'));
      await tester.tap(_transportButton(TransportGlyph.pause));
      await tester.pump(const Duration(milliseconds: 100));

      double progress() => tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value!;

      final early = progress();
      await tester.pump(const Duration(milliseconds: 2400));
      final mid = progress();
      expect(early, lessThan(0.1));
      expect(mid, closeTo(0.5, 0.1));

      await _letFadeFinish(tester, const Duration(seconds: 3));
    });
  });

  group('file de passage', () {
    testWidgets('vide : invite à préparer la suite, ajout possible', (
      tester,
    ) async {
      final spy = await _pumpPanel(tester);

      expect(find.text('FILE DE PASSAGE'), findsOneWidget);
      expect(
        find.text(
          'Préparez la musique suivante sans interrompre celle en cours.',
        ),
        findsOneWidget,
      );
      expect(findStrokeIcon(AppIcons.close), findsNothing);

      await tester.tap(find.text('Ajouter à la file'));
      expect(spy.chooseMusic, 1);
    });

    testWidgets('liste les pistes dans l\'ordre, ignore les ids introuvables', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        queue: [_musicPad(11, 'Alpha'), _musicPad(12, 'Bravo')],
        unresolvedQueueIds: const [99],
      );

      expect(
        find.text(
          'Préparez la musique suivante sans interrompre celle en cours.',
        ),
        findsNothing,
      );
      expect(findStrokeIcon(AppIcons.close), findsNWidgets(2));
      expect(
        tester.getTopLeft(find.text('Alpha')).dy,
        lessThan(tester.getTopLeft(find.text('Bravo')).dy),
      );
    });

    testWidgets('retrait : la piste visée disparaît, les autres restent', (
      tester,
    ) async {
      final spy = await _pumpPanel(
        tester,
        queue: [
          _musicPad(11, 'Alpha'),
          _musicPad(12, 'Bravo'),
          _musicPad(13, 'Charlie'),
        ],
      );

      await tester.tap(findStrokeIcon(AppIcons.close).at(1));
      await tester.pump(const Duration(milliseconds: 300));

      expect(spy.removed, [12]);
      expect(find.text('Bravo'), findsNothing);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
    });

    testWidgets('retirer la dernière piste ramène l\'état vide', (
      tester,
    ) async {
      await _pumpPanel(tester, queue: [_musicPad(11, 'Alpha')]);

      await tester.tap(findStrokeIcon(AppIcons.close));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Alpha'), findsNothing);
      expect(
        find.text(
          'Préparez la musique suivante sans interrompre celle en cours.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('glisser une piste vers le bas la place en fin de file', (
      tester,
    ) async {
      final spy = await _pumpPanel(
        tester,
        queue: [
          _musicPad(11, 'Alpha'),
          _musicPad(12, 'Bravo'),
          _musicPad(13, 'Charlie'),
        ],
      );

      await tester.timedDrag(
        find.text('Alpha'),
        const Offset(0, 300),
        const Duration(milliseconds: 600),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(spy.reorders, [(0, 2)]);
      final order = ['Bravo', 'Charlie', 'Alpha'];
      for (var i = 0; i < order.length - 1; i++) {
        expect(
          tester.getTopLeft(find.text(order[i])).dy,
          lessThan(tester.getTopLeft(find.text(order[i + 1])).dy),
          reason: '${order[i]} avant ${order[i + 1]}',
        );
      }
    });

    testWidgets('glisser une piste vers le haut la place en tête de file', (
      tester,
    ) async {
      final spy = await _pumpPanel(
        tester,
        queue: [
          _musicPad(11, 'Alpha'),
          _musicPad(12, 'Bravo'),
          _musicPad(13, 'Charlie'),
        ],
      );

      await tester.timedDrag(
        find.text('Charlie'),
        const Offset(0, -300),
        const Duration(milliseconds: 600),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(spy.reorders, [(2, 0)]);
      expect(
        tester.getTopLeft(find.text('Charlie')).dy,
        lessThan(tester.getTopLeft(find.text('Alpha')).dy),
      );
    });

    testWidgets('beaucoup de pistes : la file défile sans déborder', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        queue: [for (var i = 0; i < 12; i++) _musicPad(20 + i, 'Piste $i')],
      );

      // Un débordement de RenderFlex ferait échouer le test ; le bouton
      // d'ajout reste visible sous la liste.
      expect(find.text('Ajouter à la file'), findsOneWidget);
      final view = tester.view.physicalSize;
      expect(
        tester.getBottomLeft(find.text('Ajouter à la file')).dy,
        lessThanOrEqualTo(view.height),
      );
    });

    testWidgets('mobile : glisser une piste vers la gauche la retire', (
      tester,
    ) async {
      final spy = await _pumpPanel(
        tester,
        isDesktop: false,
        width: 700,
        queue: [_musicPad(11, 'Alpha'), _musicPad(12, 'Bravo')],
      );

      expect(
        findStrokeIcon(AppIcons.close),
        findsNothing,
        reason: 'au tactile, le retrait est un balayage, pas un bouton',
      );

      await tester.fling(find.text('Alpha'), const Offset(-250, 0), 2000);
      // Glissement (200 ms) puis réduction de la ligne (300 ms) : chaque
      // animation ne démarre qu'à la frame qui suit, d'où les pas successifs.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));

      expect(spy.removed, [11]);
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Bravo'), findsOneWidget);
    });
  });

  group('bascule réduit / avancé', () {
    testWidgets('avancé : le chevron réduit, le bandeau n\'a plus la file', (
      tester,
    ) async {
      final spy = await _pumpPanel(tester);

      expect(find.byTooltip('Développer la régie'), findsNothing);
      expect(find.text('FILE DE PASSAGE'), findsOneWidget);

      await tester.tap(find.byTooltip('Réduire la régie'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(spy.advanced, [false]);
      expect(find.text('FILE DE PASSAGE'), findsNothing);
      expect(find.byTooltip('Développer la régie'), findsOneWidget);
    });

    testWidgets('réduit : le chevron développe', (tester) async {
      final spy = await _pumpPanel(tester, isAdvanced: false);

      expect(find.text('FILE DE PASSAGE'), findsNothing);
      await tester.tap(find.byTooltip('Développer la régie'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(spy.advanced, [true]);
      expect(find.text('FILE DE PASSAGE'), findsOneWidget);
      expect(find.byTooltip('Réduire la régie'), findsOneWidget);
    });

    testWidgets('réduit : toucher le bandeau développe, une seule fois', (
      tester,
    ) async {
      final spy = await _pumpPanel(tester, isAdvanced: false);

      await tester.tap(find.text('Aucune piste sélectionnée'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(spy.advanced, [true]);
      expect(find.text('FILE DE PASSAGE'), findsOneWidget);
    });

    testWidgets('avancé : toucher le corps du tiroir ne le réduit pas', (
      tester,
    ) async {
      final spy = await _pumpPanel(tester);

      await tester.tap(find.text('Aucune musique lancée'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(spy.advanced, isEmpty);
      expect(find.text('FILE DE PASSAGE'), findsOneWidget);
    });
  });

  group('mise en page du mode avancé', () {
    // Seuil : 260 + 16 + 32 + 16 + 260 = 584 de contenu, + 32 de marges = 616.
    Offset topLeftOf(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text));

    testWidgets('616 px : deux colonnes, la file à droite de la lecture', (
      tester,
    ) async {
      await _pumpPanel(tester, width: 616);

      final ambiance = topLeftOf(tester, 'AMBIANCE');
      final queue = topLeftOf(tester, 'FILE DE PASSAGE');
      expect(queue.dx, greaterThan(616 / 2));
      expect(queue.dx, greaterThan(ambiance.dx));
      expect(find.byTooltip('Réduire la régie'), findsOneWidget);
    });

    testWidgets('615 px : une colonne, la file sous la lecture', (
      tester,
    ) async {
      await _pumpPanel(tester, width: 615);

      final ambiance = topLeftOf(tester, 'AMBIANCE');
      final queue = topLeftOf(tester, 'FILE DE PASSAGE');
      // Même colonne (le libellé de la file est aligné sur celui de
      // l'ambiance), mais plus bas.
      expect(queue.dx, lessThan(615 / 2));
      expect(queue.dy, greaterThan(ambiance.dy));
      expect(find.byTooltip('Réduire la régie'), findsOneWidget);
    });

    testWidgets('une colonne : le chevron réduit toujours le tiroir', (
      tester,
    ) async {
      final spy = await _pumpPanel(tester, width: 500);

      await tester.tap(find.byTooltip('Réduire la régie'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(spy.advanced, [false]);
      expect(find.text('FILE DE PASSAGE'), findsNothing);
    });

    testWidgets('une colonne : la file reste utilisable', (tester) async {
      final spy = await _pumpPanel(
        tester,
        width: 500,
        queue: [_musicPad(11, 'Alpha'), _musicPad(12, 'Bravo')],
      );

      await tester.tap(findStrokeIcon(AppIcons.close).first);
      await tester.pump(const Duration(milliseconds: 300));

      expect(spy.removed, [11]);
      expect(find.text('Alpha'), findsNothing);
    });
  });
}
