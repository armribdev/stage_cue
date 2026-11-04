// Bouton d'enregistrement du formulaire d'édition d'un son : un son « à traiter »
// peut être validé tel quel (sans modification), un son déjà traité exige une
// modification. En file de traitement, le libellé annonce l'enchaînement.

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/features/sampler/data/repositories/sound_repository.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';
import 'package:stage_cue/features/sampler/presentation/widgets/sound_edit_form.dart';

void main() {
  late db.AppDatabase database;
  late SoundRepository repository;
  late int soundId;

  setUp(() async {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    repository = SoundRepository.fromDatabase(database);
    soundId = await database
        .into(database.sounds)
        .insert(
          db.SoundsCompanion.insert(
            title: 'porte',
            filePath: '/introuvable/porte.wav',
            displayName: 'porte',
          ),
        );
  });

  tearDown(() => database.close());

  Sound soundOf({required bool processed}) => Sound(
    id: soundId,
    title: 'porte',
    filePath: '/introuvable/porte.wav',
    createdAt: DateTime(2026, 10, 8),
    isProcessed: processed,
  );

  Future<void> pumpForm(
    WidgetTester tester, {
    required bool processed,
    bool isQueueMode = false,
    VoidCallback? onSkip,
    VoidCallback? onSaved,
    VoidCallback? onMarkedUnprocessed,
    SoundEditFormController? controller,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SoundEditForm(
            sound: soundOf(processed: processed),
            tagCatalog: const [],
            repository: repository,
            isQueueMode: isQueueMode,
            onSkip: onSkip,
            onSaved: onSaved,
            onMarkedUnprocessed: onMarkedUnprocessed,
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder button(String label) => find.widgetWithText(ElevatedButton, label);

  bool isEnabled(WidgetTester tester, String label) =>
      tester.widget<ElevatedButton>(button(label)).onPressed != null;

  testWidgets('son à traiter : « Valider » actif sans aucune modification', (
    tester,
  ) async {
    await pumpForm(tester, processed: false);

    expect(button('Valider'), findsOneWidget);
    expect(isEnabled(tester, 'Valider'), isTrue);
  });

  testWidgets(
    'son déjà traité : « Enregistrer » inactif tant que rien ne change',
    (tester) async {
      await pumpForm(tester, processed: true);

      expect(button('Enregistrer'), findsOneWidget);
      expect(isEnabled(tester, 'Enregistrer'), isFalse);
    },
  );

  testWidgets('file de traitement : « Valider » et Passer', (tester) async {
    var skipped = 0;
    await pumpForm(
      tester,
      processed: false,
      isQueueMode: true,
      onSkip: () => skipped++,
    );

    expect(button('Valider'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Passer'));
    expect(skipped, 1);
  });

  testWidgets('hors file, pas de bouton « Passer »', (tester) async {
    await pumpForm(tester, processed: false);

    expect(find.text('Passer'), findsNothing);
  });

  testWidgets('valider tel quel marque le son traité en base', (tester) async {
    var saved = 0;
    await pumpForm(tester, processed: false, onSaved: () => saved++);

    await tester.runAsync(() async {
      await tester.tap(button('Valider'));
      // Laisse les écritures Drift (vraies E/S asynchrones) se terminer.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    final row = await tester.runAsync(
      () => (database.select(
        database.sounds,
      )..where((s) => s.id.equals(soundId))).getSingle(),
    );
    expect(row?.isProcessed, isTrue);
    expect(saved, 1);
    // Une fois validé, le bouton retombe sur « Enregistrer » (inactif).
    expect(button('Enregistrer'), findsOneWidget);
    expect(isEnabled(tester, 'Enregistrer'), isFalse);
  });

  testWidgets('un son traité peut être remis à traiter', (tester) async {
    await tester.runAsync(() => repository.markSoundsProcessed([soundId]));
    var marked = 0;
    await pumpForm(
      tester,
      processed: true,
      onMarkedUnprocessed: () => marked++,
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('Marquer non traité'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    final row = await tester.runAsync(
      () => (database.select(
        database.sounds,
      )..where((s) => s.id.equals(soundId))).getSingle(),
    );
    expect(row?.isProcessed, isFalse);
    expect(marked, 1);
    // Le formulaire repasse en « à traiter » : Valider actif, plus de bouton.
    expect(button('Valider'), findsOneWidget);
    expect(find.text('Marquer non traité'), findsNothing);
  });

  testWidgets("un son à traiter n'a pas de bouton « Marquer non traité »", (
    tester,
  ) async {
    await pumpForm(tester, processed: false);
    expect(find.text('Marquer non traité'), findsNothing);
  });

  testWidgets('le contrôleur déclenche l\'enregistrement (Ctrl+Entrée)', (
    tester,
  ) async {
    final controller = SoundEditFormController();
    await pumpForm(tester, processed: false, controller: controller);

    await tester.runAsync(() async {
      await controller.save();
    });
    await tester.pump();

    final row = await tester.runAsync(
      () => (database.select(
        database.sounds,
      )..where((s) => s.id.equals(soundId))).getSingle(),
    );
    expect(row?.isProcessed, isTrue);
  });

  group('tags de l’IA (décision 0030)', () {
    /// Laisse la lecture des tags (vraie E/S Drift) se terminer, puis redessine.
    Future<void> loadTags(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
    }

    Future<int> tagId(String name) async =>
        (await database
                .customSelect(
                  'SELECT id FROM tags WHERE name = ?',
                  variables: [Variable<String>(name)],
                )
                .getSingle())
            .read<int>('id');

    Future<void> autoTag(String name, {bool hidden = false}) async {
      await database
          .into(database.soundAutoTags)
          .insert(
            db.SoundAutoTagsCompanion.insert(
              soundId: soundId,
              tagId: await tagId(name),
              hidden: Value(hidden),
            ),
          );
    }

    Future<List<db.SoundAutoTag>> autoRows() =>
        database.select(database.soundAutoTags).get();

    testWidgets('les tags de l’IA s’affichent à part, avec l’invitation à '
        'vérifier tant que le son n’est pas traité', (tester) async {
      await autoTag('Sombre');
      await pumpForm(tester, processed: false);
      await loadTags(tester);

      expect(
        find.byKey(ValueKey('auto-tag-${await tagId('Sombre')}')),
        findsOneWidget,
      );
      expect(find.textContaining('vérifiez-les, puis validez'), findsOneWidget);
    });

    testWidgets('son traité : mêmes tags, sans invitation à valider', (
      tester,
    ) async {
      await autoTag('Sombre');
      await pumpForm(tester, processed: true);
      await loadTags(tester);

      expect(find.textContaining('Trouvés par l’IA'), findsOneWidget);
      expect(find.textContaining('vérifiez-les'), findsNothing);
    });

    testWidgets('aucun tag d’IA : aucune zone', (tester) async {
      await pumpForm(tester, processed: false);
      await loadTags(tester);
      expect(find.textContaining('Trouvés par l’IA'), findsNothing);
    });

    testWidgets('masquer : la ligne reste en base, masquée, et peut être '
        'rétablie', (tester) async {
      await autoTag('Sombre');
      final id = await tagId('Sombre');
      await pumpForm(tester, processed: false);
      await loadTags(tester);

      // Croix de la pastille (identifiée par son infobulle).
      await tester.tap(find.byTooltip('Masquer ce tag'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      var rows = await tester.runAsync(autoRows) ?? [];
      expect(rows, hasLength(1), reason: 'jamais supprimée');
      expect(rows.single.hidden, isTrue);
      expect(find.byKey(ValueKey('auto-tag-hidden-$id')), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('auto-tag-hidden-$id')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      rows = await tester.runAsync(autoRows) ?? [];
      expect(rows.single.hidden, isFalse);
      expect(find.byKey(ValueKey('auto-tag-$id')), findsOneWidget);
    });

    testWidgets('valider n’écrit jamais un tag de l’IA parmi ceux de '
        'l’utilisateur', (tester) async {
      await autoTag('Sombre');
      await pumpForm(tester, processed: false);
      await loadTags(tester);

      await tester.tap(button('Valider'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      final user = await tester.runAsync(
        () => database.select(database.soundTags).get(),
      );
      expect(user, isEmpty);
      expect(await tester.runAsync(autoRows), hasLength(1));
    });
  });
}
