// Les pastilles d'un AnimatedPillWrap s'animent à l'ajout et au retrait, mais
// pas à la première image ; une pastille retirée garde sa place le temps de sa
// disparition et ne réagit plus au toucher.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/features/sampler/presentation/widgets/animated_pill_wrap.dart';

void main() {
  Widget host(
    List<String> ids, {
    void Function(String)? onTap,
    Key? wrapKey,
    PillMemory? memory,
    bool animateInitial = false,
  }) => MaterialApp(
    home: Scaffold(
      body: AnimatedPillWrap(
        key: wrapKey,
        memory: memory,
        animateInitial: animateInitial,
        entries: [
          for (final id in ids)
            PillEntry(
              ValueKey(id),
              GestureDetector(
                onTap: () => onTap?.call(id),
                child: SizedBox(
                  key: ValueKey('pill-$id'),
                  width: 60,
                  height: 30,
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Finder pill(String id) => find.byKey(ValueKey('pill-$id'));

  testWidgets('présentes à la première image : pleines, sans animation', (
    tester,
  ) async {
    await tester.pumpWidget(host(['a', 'b']));
    expect(tester.getSize(pill('a')).width, 60);
    expect(tester.getSize(pill('b')).width, 60);
  });

  testWidgets('un ajout s’ouvre en s’animant', (tester) async {
    await tester.pumpWidget(host(['a']));
    await tester.pumpWidget(host(['a', 'b']));
    await tester.pump(const Duration(milliseconds: 60));

    final width = tester.getSize(pill('b')).width;
    // Mi-course : ni absente ni pleine (la boîte rognée reste de 60 de large,
    // c'est l'espace pris dans la rangée qui grandit).
    final slot = tester.getSize(find.byType(Wrap)).width;
    expect(width, 60);
    expect(slot, greaterThan(68));
    expect(slot, lessThan(68 + 68));

    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Wrap)).width, 68 + 68);
  });

  testWidgets('un retrait se referme puis quitte l’arbre, sans réagir au '
      'toucher', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(host(['a', 'b', 'c'], onTap: tapped.add));
    await tester.pumpWidget(host(['a', 'c'], onTap: tapped.add));
    await tester.pump(const Duration(milliseconds: 60));

    expect(pill('b'), findsOneWidget, reason: 'encore là pendant la fermeture');
    await tester.tap(pill('b'), warnIfMissed: false);
    expect(tapped, isEmpty);

    await tester.pumpAndSettle();
    expect(pill('b'), findsNothing);
    expect(pill('a'), findsOneWidget);
    expect(pill('c'), findsOneWidget);
  });

  testWidgets('une pastille qui revient pendant sa fermeture reste', (
    tester,
  ) async {
    await tester.pumpWidget(host(['a', 'b']));
    await tester.pumpWidget(host(['a']));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(host(['a', 'b']));
    await tester.pumpAndSettle();

    expect(pill('b'), findsOneWidget);
    expect(tester.getSize(find.byType(Wrap)).width, 68 + 68);
  });

  testWidgets('au passage d’un formulaire à l’autre : celles qui partent se '
      'referment, les nouvelles s’ouvrent, les communes ne bougent pas', (
    tester,
  ) async {
    final memory = PillMemory();
    await tester.pumpWidget(
      host(['a', 'b'], wrapKey: const ValueKey('un'), memory: memory),
    );
    // Autre État, comme un formulaire recréé pour un autre son.
    await tester.pumpWidget(
      host(
        ['b', 'c'],
        wrapKey: const ValueKey('deux'),
        memory: memory,
        animateInitial: true,
      ),
    );

    expect(pill('a'), findsOneWidget, reason: 'ouverte à la première image');
    expect(tester.getSize(find.byType(Wrap)).width, 68 * 2);
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getSize(find.byType(Wrap)).width, lessThan(68 * 3));

    await tester.pumpAndSettle();
    expect(pill('a'), findsNothing);
    expect(pill('b'), findsOneWidget);
    expect(pill('c'), findsOneWidget);
    expect(memory.entries.map((e) => e.key), [
      const ValueKey('b'),
      const ValueKey('c'),
    ]);
  });

  testWidgets('la dernière pastille libère aussi sa hauteur en se refermant', (
    tester,
  ) async {
    await tester.pumpWidget(host(['a']));
    expect(tester.getSize(find.byType(Wrap)).height, 30);

    await tester.pumpWidget(host([]));
    await tester.pump(const Duration(milliseconds: 90));
    final mid = tester.getSize(find.byType(Wrap)).height;
    expect(mid, greaterThan(0));
    expect(mid, lessThan(30));

    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Wrap)).height, 0);
  });

  group('AnimatedRevealColumn', () {
    Widget column(List<String> ids) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: AnimatedRevealColumn(
            entries: [
              for (final id in ids)
                PillEntry(
                  ValueKey(id),
                  SizedBox(key: ValueKey('row-$id'), height: 40),
                ),
            ],
          ),
        ),
      ),
    );

    Finder row(String id) => find.byKey(ValueKey('row-$id'));
    double height(WidgetTester tester) =>
        tester.getSize(find.byType(AnimatedRevealColumn)).height;

    testWidgets('présentes à la première image : pleines, sans animation', (
      tester,
    ) async {
      await tester.pumpWidget(column(['a', 'b']));
      expect(height(tester), 80);
    });

    testWidgets('un ajout s’ouvre en hauteur', (tester) async {
      await tester.pumpWidget(column(['a']));
      await tester.pumpWidget(column(['a', 'b']));
      await tester.pump(const Duration(milliseconds: 60));
      expect(height(tester), allOf(greaterThan(40), lessThan(80)));

      await tester.pumpAndSettle();
      expect(height(tester), 80);
    });

    testWidgets('un retrait se referme puis quitte l’arbre', (tester) async {
      await tester.pumpWidget(column(['a', 'b']));
      await tester.pumpWidget(column(['b']));
      await tester.pump(const Duration(milliseconds: 60));
      expect(row('a'), findsOneWidget);
      expect(height(tester), allOf(greaterThan(40), lessThan(80)));

      await tester.pumpAndSettle();
      expect(row('a'), findsNothing);
      expect(height(tester), 40);
    });

    testWidgets('glisser une ligne la déplace parmi les lignes affichées', (
      tester,
    ) async {
      final moves = <(int, int)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: AnimatedRevealColumn(
                onReorder: (from, to) => moves.add((from, to)),
                entries: [
                  for (final id in ['a', 'b', 'c'])
                    PillEntry(
                      ValueKey(id),
                      SizedBox(
                        key: ValueKey('row-$id'),
                        height: 40,
                        width: 200,
                        // Un contenu touchable, comme une vraie ligne.
                        child: const ColoredBox(color: Colors.blueGrey),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.drag(row('a'), const Offset(0, 130));
      await tester.pumpAndSettle();

      expect(moves, [(0, 2)]);
    });
  });
}
