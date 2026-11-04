// Bouton d'enregistrement du formulaire d'édition d'un son : un son « à traiter »
// peut être validé tel quel (sans modification), un son déjà traité exige une
// modification. En file de traitement, le libellé annonce l'enchaînement.

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/autotag/auto_tag_analysis.dart';
import 'package:stage_cue/core/autotag/auto_tag_status.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/features/sampler/data/repositories/sound_repository.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';
import 'package:stage_cue/features/sampler/presentation/widgets/sound_edit_form.dart';

/// Vue d'analyse factice : l'état est piloté par le test.
class FakeAutoTagAnalysis implements AutoTagAnalysis {
  SoundAnalysisStatus? status;
  String? refusal;
  final started = <int>[];
  @override
  final ValueNotifier<AutoTagActivity> activity = ValueNotifier(
    AutoTagActivity.idle,
  );

  FakeAutoTagAnalysis(this.status);

  @override
  Future<SoundAnalysisStatus?> statusOf(int soundId) async => status;

  @override
  String? start(int soundId) {
    started.add(soundId);
    return refusal;
  }
}

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
    AutoTagAnalysis? autoTag,
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
            autoTag: autoTag,
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

  group('suggestions de l’IA (décision 0031)', () {
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

    Future<void> autoTag(String name, {double score = 0.42}) async {
      await database
          .into(database.soundAutoTags)
          .insert(
            db.SoundAutoTagsCompanion.insert(
              soundId: soundId,
              tagId: await tagId(name),
              score: score,
            ),
          );
    }

    Future<List<db.SoundAutoTag>> autoRows() =>
        database.select(database.soundAutoTags).get();

    Future<List<db.SoundTag>> userRows(WidgetTester tester) async =>
        await tester.runAsync(
          () => database.select(database.soundTags).get(),
        ) ??
        [];

    for (final processed in [false, true]) {
      testWidgets('suggestion toujours affichée avec sa confiance '
          '(son ${processed ? 'traité' : 'à traiter'})', (tester) async {
        await autoTag('Sombre', score: 0.42);
        await pumpForm(tester, processed: processed);
        await loadTags(tester);

        expect(
          find.byKey(ValueKey('auto-tag-${await tagId('Sombre')}')),
          findsOneWidget,
        );
        expect(find.text('42 %'), findsOneWidget);
        expect(find.textContaining('touchez pour ajouter'), findsNothing);
      });
    }

    testWidgets('aucune suggestion : aucune zone', (tester) async {
      await pumpForm(tester, processed: false);
      await loadTags(tester);
      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('toucher une suggestion l’ajoute aux tags et la masque, '
        'enregistrée avec le formulaire ; la suggestion reste en base', (
      tester,
    ) async {
      await autoTag('Sombre');
      final id = await tagId('Sombre');
      await pumpForm(tester, processed: false);
      await loadTags(tester);

      await tester.tap(find.byKey(ValueKey('auto-tag-$id')));
      await tester.pump();
      expect(find.byKey(ValueKey('auto-tag-$id')), findsNothing);
      expect(await userRows(tester), isEmpty, reason: 'pas encore enregistré');

      await tester.tap(button('Valider'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      expect((await userRows(tester)).map((r) => r.tagId), [id]);
      expect(await tester.runAsync(autoRows), hasLength(1));
    });

    testWidgets('valider sans toucher la suggestion n’écrit rien parmi les '
        'tags de l’utilisateur', (tester) async {
      await autoTag('Sombre');
      await pumpForm(tester, processed: false);
      await loadTags(tester);

      await tester.tap(button('Valider'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      expect(await userRows(tester), isEmpty);
      expect(await tester.runAsync(autoRows), hasLength(1));
    });
  });

  group('état de l’analyse IA', () {
    Future<void> load(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
    }

    Future<FakeAutoTagAnalysis> pumpWith(
      WidgetTester tester,
      SoundAnalysisStatus? status,
    ) async {
      final analysis = FakeAutoTagAnalysis(status);
      await pumpForm(tester, processed: false, autoTag: analysis);
      await load(tester);
      return analysis;
    }

    testWidgets('sans analyse (mobile) : aucune zone', (tester) async {
      await pumpForm(tester, processed: false);
      await load(tester);
      expect(find.textContaining('Analyse IA'), findsNothing);
    });

    testWidgets('pas encore analysé : le dit et propose « Analyser »', (
      tester,
    ) async {
      final analysis = await pumpWith(tester, SoundAnalysisStatus.pending);
      expect(find.textContaining('pas encore analysé'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('auto-tag-start')));
      await tester.pump();

      expect(analysis.started, [soundId]);
      // Demandé : en attente, plus de bouton.
      expect(find.textContaining('en attente'), findsOneWidget);
      expect(find.byKey(const ValueKey('auto-tag-start')), findsNothing);
    });

    testWidgets('lancement refusé : la raison est affichée, le bouton reste', (
      tester,
    ) async {
      final analysis = await pumpWith(tester, SoundAnalysisStatus.pending);
      analysis.refusal = 'Mode Spectacle';

      await tester.tap(find.byKey(const ValueKey('auto-tag-start')));
      await tester.pump();

      expect(find.textContaining('Mode Spectacle'), findsOneWidget);
      expect(find.byKey(const ValueKey('auto-tag-start')), findsOneWidget);
      // Laisse la snackbar expirer (son minuteur ne doit pas rester en suspens).
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('analysé : rien n’est affiché', (tester) async {
      await pumpWith(tester, SoundAnalysisStatus.analyzed);
      expect(find.byKey(const ValueKey('auto-tag-status')), findsNothing);
      expect(find.byKey(const ValueKey('auto-tag-start')), findsNothing);
      expect(find.textContaining('Analyse IA'), findsNothing);
    });

    for (final status in SoundAnalysisStatus.values.where(
      (s) =>
          s != SoundAnalysisStatus.pending && s != SoundAnalysisStatus.analyzed,
    )) {
      testWidgets('${status.name} : texte, jamais de bouton', (tester) async {
        await pumpWith(tester, status);
        expect(find.byKey(const ValueKey('auto-tag-status')), findsOneWidget);
        expect(find.byKey(const ValueKey('auto-tag-start')), findsNothing);
      });
    }

    testWidgets('la fin d’un passage rafraîchit l’état', (tester) async {
      final analysis = await pumpWith(tester, SoundAnalysisStatus.pending);

      analysis.status = SoundAnalysisStatus.analyzed;
      analysis.activity.value = const AutoTagActivity(running: true);
      analysis.activity.value = AutoTagActivity.idle;
      await load(tester);

      expect(find.byKey(const ValueKey('auto-tag-status')), findsNothing);
      expect(find.byKey(const ValueKey('auto-tag-start')), findsNothing);
    });
  });
}
