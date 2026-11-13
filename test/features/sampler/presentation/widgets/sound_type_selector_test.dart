// Sélecteur de type : replié sur le type courant, déplié en trois cercles.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';
import 'package:stage_cue/features/sampler/presentation/widgets/sound_type_selector.dart';

void main() {
  Future<List<SoundType>> pump(WidgetTester tester, SoundType? type) async {
    final picked = <SoundType>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SoundTypeSelector(type: type, onChanged: picked.add),
          ),
        ),
      ),
    );
    return picked;
  }

  testWidgets('replié : un seul cercle, les autres types sont cachés', (
    tester,
  ) async {
    await pump(tester, SoundType.music);
    expect(find.byType(CircleAvatar), findsOneWidget);
  });

  testWidgets('déplié : trois cercles, choisir un type le notifie et replie', (
    tester,
  ) async {
    final picked = await pump(tester, SoundType.music);

    await tester.tap(find.byType(CircleAvatar));
    await tester.pumpAndSettle();
    expect(find.byType(CircleAvatar), findsNWidgets(3));

    await tester.tap(find.byTooltip('Bruitage'));
    await tester.pumpAndSettle();
    expect(picked, [SoundType.soundEffect]);
    expect(find.byType(CircleAvatar), findsOneWidget);
  });

  testWidgets('son non classé : cercle neutre remplacé par les trois types', (
    tester,
  ) async {
    await pump(tester, null);
    expect(find.byType(CircleAvatar), findsOneWidget);

    await tester.tap(find.byType(CircleAvatar));
    await tester.pumpAndSettle();
    expect(find.byType(CircleAvatar), findsNWidgets(3));
  });

  testWidgets('toucher à côté replie le sélecteur', (tester) async {
    await pump(tester, SoundType.ambiance);
    await tester.tap(find.byType(CircleAvatar));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(CircleAvatar), findsOneWidget);
  });
}
