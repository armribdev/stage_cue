import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/settings/app_preferences.dart';
import 'package:stage_cue/features/sampler/domain/entities/pad.dart';
import 'package:stage_cue/features/sampler/presentation/models/keyboard_layout.dart';
import 'package:stage_cue/features/sampler/presentation/providers/sampler_provider.dart';
import 'package:stage_cue/features/sampler/presentation/widgets/keyboard_pads_view.dart';

PadItem _pad(int id, String name) => PadItem(
  pad: Pad(
    id: id,
    boardId: 1,
    name: name,
    sortOrder: id,
    createdAt: DateTime(2026, 1, 1),
    sounds: const [],
  ),
);

int _key(String char) => char.runes.first;

/// Carte factice du panneau : remplit sa cellule, pour mesurer sa position.
class _CardProbe extends StatelessWidget {
  final String label;

  const _CardProbe(this.label);

  @override
  Widget build(BuildContext context) => Center(child: Text(label));
}

void main() {
  group('assignPadsToKeys', () {
    test('pose chaque pad sur sa touche, le reste dans loose', () {
      final a = _pad(1, 'A');
      final b = _pad(2, 'B');
      final none = _pad(3, 'Sans touche');
      final arrow = _pad(4, 'Flèche');
      final keys = {
        1: _key('a'),
        2: _key('é'),
        4: LogicalKeyboardKey.arrowUp.keyId,
      };

      final result = assignPadsToKeys([a, b, none, arrow], (id) => keys[id]);

      expect(result.onKeys, {_key('a'): a, _key('é'): b});
      // Une touche non dessinée (flèche) n'est pas perdue : elle est listée.
      expect(result.loose, [none, arrow]);
    });

    test('collision : le premier pad garde la touche, comme le raccourci', () {
      final first = _pad(1, 'Premier');
      final second = _pad(2, 'Second');

      final result = assignPadsToKeys([first, second], (_) => _key('z'));

      expect(result.onKeys, {_key('z'): first});
      expect(result.loose, [second]);
    });

    test('aucune touche n\'apparaît deux fois dans la disposition', () {
      final ids = [
        for (final row in kAzertyRows)
          for (final key in row.keys) key.keyId,
      ];
      expect(ids.toSet().length, ids.length);
    });
  });

  group('planPadDrop', () {
    final a = _pad(1, 'A');
    final b = _pad(2, 'B');
    final loose = _pad(3, 'Libre');

    Map<int, int?> plan(
      PadItem dragged,
      int? target,
      Map<int, int> hotkeys,
      List<PadItem> pads,
    ) {
      int? hotkeyFor(int id) => hotkeys[id];
      return planPadDrop(
        dragged: dragged,
        targetKeyId: target,
        assignment: assignPadsToKeys(pads, hotkeyFor),
        hotkeyForPad: hotkeyFor,
      );
    }

    test("touche vide : le pad s'y place", () {
      expect(plan(loose, _key('e'), {1: _key('a')}, [a, loose]), {
        3: _key('e'),
      });
    });

    test('touche occupée : les deux pads échangent leurs touches', () {
      final hotkeys = {1: _key('a'), 2: _key('z')};
      expect(plan(a, _key('z'), hotkeys, [a, b]), {1: _key('z'), 2: _key('a')});
    });

    test(
      'touche occupée, pad déposé sans touche dessinée : le pad délogé la perd',
      () {
        expect(plan(loose, _key('a'), {1: _key('a')}, [a, loose]), {
          3: _key('a'),
          1: null,
        });
      },
    );

    test("lâché hors d'une touche : retire la touche, sinon rien à faire", () {
      expect(plan(a, null, {1: _key('a')}, [a]), {1: null});
      expect(plan(loose, null, {}, [loose]), isEmpty);
    });

    test('déposer un pad sur sa propre touche ne change rien', () {
      expect(plan(a, _key('a'), {1: _key('a')}, [a]), isEmpty);
    });
  });

  group('BoardView', () {
    test('une valeur absente ou inconnue retombe sur la grille', () {
      expect(BoardView.fromStorageKey(null), BoardView.grid);
      expect(BoardView.fromStorageKey('hologramme'), BoardView.grid);
      expect(BoardView.fromStorageKey('keyboard'), BoardView.keyboard);
    });
  });

  group('KeyboardPadsView', () {
    Widget host({
      required List<PadItem> pads,
      required Map<int, int> hotkeys,
      required void Function(PadItem) onTap,
      void Function(PadItem)? onEdit,
      Future<void> Function(Map<int, int?>)? onAssign,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 700,
            child: KeyboardPadsView(
              pads: pads,
              hotkeyForPad: (id) => hotkeys[id],
              onTap: onTap,
              onAssign: onAssign,
              onEdit: onEdit,
            ),
          ),
        ),
      );
    }

    testWidgets('affiche le pad sur sa touche et déclenche au clic', (
      tester,
    ) async {
      final pad = _pad(1, 'Tonnerre');
      PadItem? tapped;

      await tester.pumpWidget(
        host(
          pads: [pad],
          hotkeys: {1: _key('a')},
          onTap: (item) => tapped = item,
        ),
      );

      expect(find.text('Tonnerre'), findsOneWidget);

      await tester.tap(find.text('Tonnerre'));
      expect(tapped, pad);
    });

    testWidgets("un pad sans touche n'est pas affiché dans la vue", (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          pads: [_pad(1, 'Sur touche'), _pad(2, 'Orphelin')],
          hotkeys: {1: _key('q')},
          onTap: (_) {},
        ),
      );

      expect(find.text('Sur touche'), findsOneWidget);
      expect(find.text('Orphelin'), findsNothing);
    });

    testWidgets("lâcher un pad hors d'une touche lui retire sa touche", (
      tester,
    ) async {
      final pad = _pad(1, 'Tonnerre');
      Map<int, int?>? changes;

      await tester.pumpWidget(
        host(
          pads: [pad],
          hotkeys: {1: _key('a')},
          onTap: (_) {},
          onAssign: (c) async => changes = c,
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Tonnerre')),
      );
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      // Bas de l'écran de test (800×600), sous le clavier : aucune touche.
      await gesture.moveTo(const Offset(400, 560));
      await tester.pump();
      expect(find.textContaining('Lâchez hors'), findsOneWidget);
      await gesture.up();
      await tester.pump();

      expect(changes, {1: null});
    });

    testWidgets('appui long ouvre les réglages, sauf édition verrouillée', (
      tester,
    ) async {
      final pad = _pad(1, 'Tonnerre');
      PadItem? edited;

      await tester.pumpWidget(
        host(
          pads: [pad],
          hotkeys: {1: _key('a')},
          onTap: (_) {},
          onEdit: (item) => edited = item,
        ),
      );
      await tester.longPress(find.text('Tonnerre'));
      expect(edited, pad);

      edited = null;
      await tester.pumpWidget(
        host(pads: [pad], hotkeys: {1: _key('a')}, onTap: (_) {}),
      );
      await tester.longPress(find.text('Tonnerre'));
      expect(edited, isNull);
    });

    testWidgets("glisser un pad sur une touche vide l'y assigne", (
      tester,
    ) async {
      final pad = _pad(1, 'Tonnerre');
      Map<int, int?>? changes;

      await tester.pumpWidget(
        host(
          pads: [pad],
          // Sur « Q » : la touche « A » est vide.
          hotkeys: {1: _key('q')},
          onTap: (_) {},
          onAssign: (c) async => changes = c,
        ),
      );

      final target = tester.getCenter(find.text('A'));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Tonnerre')),
      );
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      await gesture.moveTo(target);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(changes, {1: _key('a')});
    });

    testWidgets('cliquer une touche vide propose les pads sans touche', (
      tester,
    ) async {
      final onKey = _pad(1, 'Sur touche');
      final loose = _pad(2, 'Orphelin');
      Map<int, int?>? changes;

      await tester.pumpWidget(
        host(
          pads: [onKey, loose],
          hotkeys: {1: _key('q')},
          onTap: (_) {},
          onAssign: (c) async => changes = c,
        ),
      );

      await tester.tap(find.text('Z'));
      await tester.pumpAndSettle();
      expect(find.text('ASSIGNER À Z'), findsOneWidget);
      // Le pad déjà sur une touche n'est pas proposé dans le menu.
      expect(find.text('Sur touche'), findsOneWidget);

      await tester.tap(find.text('Orphelin').last);
      await tester.pumpAndSettle();
      expect(changes, {2: _key('z')});
    });

    group('panneau de pads', () {
      Widget hostWithTray({
        required List<PadItem> pads,
        required Map<int, int> hotkeys,
        Future<void> Function(Map<int, int?>)? onAssign,
      }) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 700,
              child: KeyboardPadsView(
                pads: pads,
                hotkeyForPad: (id) => hotkeys[id],
                onTap: (_) {},
                onAssign: onAssign,
                trayCardBuilder: (context, item) =>
                    _CardProbe('carte ${item.displayName}'),
              ),
            ),
          ),
        );
      }

      testWidgets('liste tous les pads, ceux sur une touche estompés', (
        tester,
      ) async {
        await tester.pumpWidget(
          hostWithTray(
            pads: [_pad(1, 'Placé'), _pad(2, 'Libre')],
            hotkeys: {1: _key('q')},
            onAssign: (_) async {},
          ),
        );

        double opacityOf(String name) => tester
            .widget<Opacity>(
              find
                  .ancestor(
                    of: find.text('carte $name'),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity;

        expect(opacityOf('Placé'), lessThan(1));
        expect(opacityOf('Libre'), 1);
      });

      testWidgets('les cartes partent du bord gauche, comme la grille', (
        tester,
      ) async {
        await tester.pumpWidget(
          hostWithTray(
            pads: [_pad(1, 'Libre')],
            hotkeys: const {},
            onAssign: (_) async {},
          ),
        );

        // Marge de 16 px de la grille, pas un panneau centré.
        expect(tester.getTopLeft(find.byType(_CardProbe)).dx, 16);
      });

      testWidgets('glisser une carte du panneau sur une touche vide', (
        tester,
      ) async {
        Map<int, int?>? changes;
        await tester.pumpWidget(
          hostWithTray(
            pads: [_pad(1, 'Libre')],
            hotkeys: const {},
            onAssign: (c) async => changes = c,
          ),
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.text('carte Libre')),
        );
        await gesture.moveBy(const Offset(0, -40));
        await tester.pump();
        await gesture.moveTo(tester.getCenter(find.text('A')));
        await tester.pump();
        await gesture.up();
        await tester.pump();

        expect(changes, {1: _key('a')});
      });

      testWidgets('absent quand l’assignation est verrouillée', (tester) async {
        await tester.pumpWidget(
          hostWithTray(pads: [_pad(1, 'Libre')], hotkeys: const {}),
        );

        expect(find.text('carte Libre'), findsNothing);
      });
    });

    testWidgets('assignation verrouillée : clic sur touche vide sans effet', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(pads: [_pad(1, 'Orphelin')], hotkeys: const {}, onTap: (_) {}),
      );

      await tester.tap(find.text('Z'));
      await tester.pumpAndSettle();
      expect(find.text('ASSIGNER À Z'), findsNothing);
    });

    testWidgets('le clavier est centré verticalement dans la vue', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          pads: [_pad(1, 'Tonnerre')],
          hotkeys: {1: _key('a')},
          onTap: (_) {},
        ),
      );

      // Cellules de la 1re rangée (« & ») et de la barre d'espace (« ␣ »).
      Rect cell(String label) => tester.getRect(
        find
            .ancestor(of: find.text(label), matching: find.byType(SizedBox))
            .first,
      );
      final view = tester.getRect(find.byType(KeyboardPadsView));
      final topMargin = cell('&').top - view.top;
      final bottomMargin = view.bottom - cell('␣').bottom;

      expect(topMargin, greaterThan(40));
      expect(topMargin, closeTo(bottomMargin, 1));
    });
  });
}
