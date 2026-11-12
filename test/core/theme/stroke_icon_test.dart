import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/theme/app_icons.dart';
import 'package:stage_cue/core/theme/stroke_icon.dart';

void main() {
  testWidgets('prend taille et couleur de l\'IconTheme comme un Icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: IconTheme(
          data: const IconThemeData(size: 18, color: Colors.red),
          child: Center(child: StrokeIcon(AppIcons.cloud)),
        ),
      ),
    );

    expect(tester.getSize(find.byType(StrokeIcon)), const Size.square(18));
  });

  testWidgets('une taille explicite l\'emporte sur celle de l\'IconTheme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: IconTheme(
          data: const IconThemeData(size: 18, color: Colors.red),
          child: Center(child: StrokeIcon(AppIcons.cloud, size: 30)),
        ),
      ),
    );

    expect(tester.getSize(find.byType(StrokeIcon)), const Size.square(30));
  });

  testWidgets('sans libellé l\'icône est décorative, avec libellé elle est '
      'annoncée', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            StrokeIcon(AppIcons.cloud, color: Colors.red),
            StrokeIcon(
              AppIcons.cloudOff,
              color: Colors.red,
              semanticLabel: 'Hors ligne',
            ),
          ],
        ),
      ),
    );

    expect(find.bySemanticsLabel('Hors ligne'), findsOneWidget);
    handle.dispose();
  });
}
