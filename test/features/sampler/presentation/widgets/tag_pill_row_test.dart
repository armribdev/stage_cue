import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/features/sampler/presentation/widgets/tag_pill.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required bool compact}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            child: TagPillRow(
              maxVisible: 2,
              compact: compact,
              tags: const [
                (label: TextSpan(text: 'Épique'), color: Colors.purple),
                (label: TextSpan(text: 'Combat'), color: Colors.red),
                (label: TextSpan(text: 'Nuit'), color: null),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<bool> compactFlags(WidgetTester tester) => [
    for (final p in tester.widgetList<TagPill>(find.byType(TagPill))) p.compact,
  ];

  for (final compact in [false, true]) {
    testWidgets('taille ${compact ? 'compacte' : 'normale'} imposée par '
        'l’appelant, « +N » du reste', (tester) async {
      await pump(tester, compact: compact);

      expect(compactFlags(tester), [compact, compact]);
      expect(find.text('Nuit'), findsNothing, reason: 'au-delà de maxVisible');
      expect(find.text('+1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
