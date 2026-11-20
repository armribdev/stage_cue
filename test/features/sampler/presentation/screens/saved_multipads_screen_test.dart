import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/core/theme/app_theme.dart';
import 'package:stage_cue/features/sampler/data/repositories/sound_repository.dart';
import 'package:stage_cue/features/sampler/domain/entities/pad.dart';
import 'package:stage_cue/features/sampler/domain/usecases/load_sounds_usecase.dart';
import 'package:stage_cue/features/sampler/presentation/providers/sampler_provider.dart';
import 'package:stage_cue/features/sampler/presentation/screens/saved_multipads_screen.dart';

/// Gestion des multipads enregistrés (décision 0051) sur une vraie base en
/// mémoire : la liste, la suppression (avec confirmation) et l'édition. Aucun
/// pad posé n'est touché — ce sont des copies.
void main() {
  late db.AppDatabase database;
  late SoundRepository repository;
  late SamplerNotifier notifier;

  setUp(() async {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    repository = SoundRepository.fromDatabase(database);
    notifier = SamplerNotifier(repository, LoadSoundsUseCase(repository));
    for (final title in ['grincement A', 'grincement B', 'grincement C']) {
      await database.customStatement(
        "INSERT INTO sounds (title, file_path, display_name) "
        "VALUES ('$title', '/$title.wav', '$title')",
      );
    }
  });

  tearDown(() async {
    notifier.dispose();
    await database.close();
  });

  /// Les I/O de la base ne progressent que sur l'horloge réelle : on alterne
  /// `runAsync` et `pump`, comme `sampler_flow_test`.
  Future<void> flush(WidgetTester tester, {int rounds = 6}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> openScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: SavedMultipadsScreen(notifier: notifier),
      ),
    );
    await flush(tester);
  }

  /// Enregistre un modèle de [soundIds] (1 à 3 : les sons du `setUp`).
  Future<void> seed(
    WidgetTester tester,
    String name,
    List<int> soundIds,
  ) async {
    await tester.runAsync(() async {
      await repository.saveMultipad(
        Pad(
          id: -1,
          boardId: -1,
          sortOrder: 0,
          createdAt: DateTime(2026),
          sounds: [
            for (final id in soundIds) (await repository.getSoundById(id))!,
          ],
        ),
        name: name,
      );
    });
  }

  testWidgets('sans modèle, un message explique comment en créer', (
    tester,
  ) async {
    await openScreen(tester);

    expect(find.textContaining('Aucun multipad enregistré'), findsOneWidget);
  });

  testWidgets('liste les modèles avec leur nombre de sons', (tester) async {
    await seed(tester, 'Porte qui grince', [1, 2, 3]);
    await openScreen(tester);

    expect(find.text('Porte qui grince'), findsOneWidget);
    expect(find.textContaining('3 sons'), findsOneWidget);
  });

  testWidgets('supprimer demande confirmation, puis retire le modèle seul', (
    tester,
  ) async {
    await seed(tester, 'Porte', [1]);
    await openScreen(tester);

    await tester.tap(find.byTooltip('Supprimer'));
    await flush(tester);
    expect(find.text('Supprimer le multipad enregistré'), findsOneWidget);
    expect(
      await tester.runAsync(() => repository.getSavedMultipads()),
      hasLength(1),
      reason: 'rien n\'est supprimé avant la confirmation',
    );

    await tester.tap(find.text('Supprimer'));
    await flush(tester);

    expect(
      await tester.runAsync(() => repository.getSavedMultipads()),
      isEmpty,
    );
    expect(
      await tester.runAsync(() => repository.getAllSounds()),
      hasLength(3),
      reason: 'les sons de la bibliothèque restent',
    );
    expect(find.textContaining('Aucun multipad enregistré'), findsOneWidget);
  });

  testWidgets('modifier : renommer et retirer un son s\'enregistre', (
    tester,
  ) async {
    await seed(tester, 'Porte', [1, 2, 3]);
    await openScreen(tester);

    await tester.tap(find.text('Porte'));
    await flush(tester);
    expect(find.text('Multipad enregistré'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Porte qui grince');
    await tester.tap(find.byTooltip('Retirer').first);
    await tester.pump();
    await tester.tap(find.text('Enregistrer'));
    await flush(tester);

    final saved = (await tester.runAsync(
      () => repository.getSavedMultipads(),
    ))!.single;
    expect(saved.name, 'Porte qui grince');
    expect(saved.sounds.map((s) => s.displayName), [
      'grincement B',
      'grincement C',
    ]);
  });

  testWidgets('modifier : un nom vide désactive « Enregistrer »', (
    tester,
  ) async {
    await seed(tester, 'Porte', [1]);
    await openScreen(tester);
    await tester.tap(find.text('Porte'));
    await flush(tester);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();

    final save = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Enregistrer'),
    );
    expect(save.onPressed, isNull);
  });
}
