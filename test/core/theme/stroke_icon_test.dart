import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('filled remplit le tracé : le centre de l\'étoile est coloré', (
    tester,
  ) async {
    Future<void> pumpStar({required bool filled}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: const ValueKey('star'),
            child: Center(
              child: StrokeIcon(
                AppIcons.favorite,
                size: 48,
                color: Colors.red,
                filled: filled,
              ),
            ),
          ),
        ),
      );
    }

    Future<Color> centerPixel() async {
      final image = await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('star')),
        );
        final img = await boundary.toImage();
        final data = await img.toByteData();
        final x = img.width ~/ 2, y = img.height ~/ 2;
        final i = (y * img.width + x) * 4;
        return Color.fromARGB(
          data!.getUint8(i + 3),
          data.getUint8(i),
          data.getUint8(i + 1),
          data.getUint8(i + 2),
        );
      });
      return image!;
    }

    await pumpStar(filled: false);
    expect((await centerPixel()).a, 0, reason: 'contour seul : centre vide');

    await pumpStar(filled: true);
    final filledCenter = await centerPixel();
    expect(filledCenter.a, 1);
    expect(filledCenter.r, closeTo(Colors.red.r, 0.01));
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
