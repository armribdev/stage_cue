// Étiquette de tag : la croix a une vraie zone de clic, et une suggestion a
// exactement le gabarit d'un tag posé.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/features/sampler/presentation/widgets/tag_pill.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );

  testWidgets('la croix offre une zone de clic d’au moins 22 px', (
    tester,
  ) async {
    await pump(
      tester,
      TagPill(label: 'Porte', onRemove: () {}, removeTooltip: 'Retirer Porte'),
    );

    final size = tester.getSize(find.byTooltip('Retirer Porte'));
    expect(size.width, greaterThanOrEqualTo(22));
    expect(size.height, greaterThanOrEqualTo(22));
  });

  testWidgets('toucher le bord de la zone de la croix retire le tag', (
    tester,
  ) async {
    var removed = 0;
    await pump(
      tester,
      TagPill(
        label: 'Porte',
        onRemove: () => removed++,
        removeTooltip: 'Retirer Porte',
      ),
    );

    // À 9 px du centre : hors du glyphe (13 px), dans la zone de clic.
    final center = tester.getCenter(find.byTooltip('Retirer Porte'));
    await tester.tapAt(center + const Offset(9, 9));
    expect(removed, 1);
  });

  testWidgets('une étiquette qui porte une croix ne grandit pas pour elle', (
    tester,
  ) async {
    await pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TagPill(key: const ValueKey('plain'), label: 'Porte'),
          TagPill(
            key: const ValueKey('removable'),
            label: 'Porte',
            onRemove: () {},
          ),
        ],
      ),
    );

    // À moins d'un pixel (l'arrondi de la hauteur de ligne du texte).
    expect(
      tester.getSize(find.byKey(const ValueKey('removable'))).height,
      closeTo(tester.getSize(find.byKey(const ValueKey('plain'))).height, 1),
    );
  });

  testWidgets('une suggestion a la hauteur d’un tag posé', (tester) async {
    await pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TagPill(
            key: const ValueKey('applied'),
            label: 'Porte',
            onRemove: () {},
          ),
          TagPill(
            key: const ValueKey('suggested'),
            label: 'Porte',
            suggestion: true,
            onTap: () {},
          ),
        ],
      ),
    );

    final applied = tester.getSize(find.byKey(const ValueKey('applied')));
    final suggested = tester.getSize(find.byKey(const ValueKey('suggested')));
    expect(suggested.height, applied.height);
    expect(suggested.width, applied.width);
  });
}
