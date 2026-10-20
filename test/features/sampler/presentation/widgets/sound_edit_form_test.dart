// Bouton d'enregistrement du formulaire d'édition d'un son : un son « à traiter »
// peut être validé tel quel (sans modification), un son déjà traité exige une
// modification. En file de traitement, le libellé annonce l'enchaînement.

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
            queueRemaining: isQueueMode ? 12 : null,
            onSkip: onSkip,
            onSaved: onSaved,
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
    expect(find.text('À TRAITER'), findsOneWidget);
  });

  testWidgets(
    'son déjà traité : « Enregistrer » inactif tant que rien ne change',
    (tester) async {
      await pumpForm(tester, processed: true);

      expect(button('Enregistrer'), findsOneWidget);
      expect(isEnabled(tester, 'Enregistrer'), isFalse);
      expect(find.text('À TRAITER'), findsNothing);
    },
  );

  testWidgets(
    'file de traitement : « Valider et suivant », compteur et Passer',
    (tester) async {
      var skipped = 0;
      await pumpForm(
        tester,
        processed: false,
        isQueueMode: true,
        onSkip: () => skipped++,
      );

      expect(button('Valider et suivant'), findsOneWidget);
      expect(find.text('12 à traiter'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Passer'));
      expect(skipped, 1);
    },
  );

  testWidgets('hors file, pas de bouton « Passer » ni de compteur', (
    tester,
  ) async {
    await pumpForm(tester, processed: false);

    expect(find.text('Passer'), findsNothing);
    expect(find.textContaining('à traiter'), findsNothing);
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
    expect(find.text('À TRAITER'), findsNothing);
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
}
