// Badge « à traiter » des menus et compteur de l'index de recherche qui
// l'alimente.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/features/sampler/data/repositories/sound_repository.dart';
import 'package:stage_cue/features/sampler/presentation/providers/sound_search_index.dart';
import 'package:stage_cue/features/sampler/presentation/widgets/unprocessed_badge.dart';

void main() {
  testWidgets('la pastille suit le compteur et disparaît à zéro',
      (tester) async {
    final count = ValueNotifier<int>(3);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UnprocessedCountPill(count: count)),
      ),
    );
    expect(find.text('3 à traiter'), findsOneWidget);

    count.value = 1;
    await tester.pump();
    expect(find.text('1 à traiter'), findsOneWidget);

    count.value = 0;
    await tester.pump();
    expect(find.textContaining('à traiter'), findsNothing);
  });

  testWidgets('le point n\'apparaît que s\'il reste des sons à traiter',
      (tester) async {
    final count = ValueNotifier<int>(0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnprocessedDot(
            count: count,
            child: const SizedBox(width: 32, height: 32),
          ),
        ),
      ),
    );
    Finder dot() => find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).shape == BoxShape.circle,
        );
    expect(dot(), findsNothing);

    count.value = 2;
    await tester.pump();
    expect(dot(), findsOneWidget);
  });

  test('l\'index publie le nombre de sons non traités à chaque reconstruction',
      () async {
    final database = db.AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final ids = [
      for (final name in ['a', 'b', 'c'])
        await database.into(database.sounds).insert(
              db.SoundsCompanion.insert(
                title: name,
                filePath: '/introuvable/$name.wav',
                displayName: name,
              ),
            ),
    ];
    final repository = SoundRepository.fromDatabase(database);
    final index = SoundSearchIndex(repository, null);

    expect(index.unprocessedCount.value, 0, reason: 'avant tout chargement');

    await index.refresh();
    expect(index.unprocessedCount.value, 3);

    await repository.markSoundsProcessed([ids[0], ids[1]]);
    await index.refresh();
    expect(index.unprocessedCount.value, 1);
  });
}
