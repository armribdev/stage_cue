import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/core/theme/app_theme.dart';
import 'package:stage_cue/features/sampler/data/repositories/sound_repository.dart';
import 'package:stage_cue/features/sampler/domain/entities/pad.dart';
import 'package:stage_cue/features/sampler/domain/usecases/load_sounds_usecase.dart';
import 'package:stage_cue/features/sampler/presentation/providers/sampler_provider.dart';
import 'package:stage_cue/features/sampler/presentation/widgets/saved_multipad_edit_form.dart';
import 'package:stage_cue/features/sampler/presentation/widgets/sound_picker_overlay.dart';

/// Multipads enregistrés (décision 0051) dans la gestion de la bibliothèque,
/// sur une vraie base en mémoire : ils sont des lignes de la liste comme les
/// sons, avec suppression (confirmée) et édition. Aucun pad posé n'est touché —
/// ce sont des copies.
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
    tester.view.physicalSize = const Size(2400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => SoundPickerOverlay.showForManage(
                  context,
                  notifier: notifier,
                  repository: repository,
                ),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await flush(tester);
  }

  /// Le champ du nom, dans le volet d'édition (la liste a aussi son champ).
  Finder editField() => find.descendant(
    of: find.byType(SavedMultipadEditForm),
    matching: find.byType(TextField),
  );

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

  testWidgets('liste les modèles parmi les sons, avec leur nombre de sons', (
    tester,
  ) async {
    await seed(tester, 'Porte qui grince', [1, 2, 3]);
    await openScreen(tester);

    expect(find.text('Porte qui grince'), findsOneWidget);
    expect(find.textContaining('Multipad · 3 sons'), findsOneWidget);
    expect(find.text('grincement A'), findsOneWidget);
  });

  testWidgets('un modèle sans son reste listé pour être complété', (
    tester,
  ) async {
    // Un modèle se vide quand son dernier son disparaît de la bibliothèque.
    await seed(tester, 'Vide', [1]);
    await tester.runAsync(
      () => database.customStatement('DELETE FROM sounds WHERE id = 1'),
    );
    await openScreen(tester);

    expect(find.text('Vide'), findsOneWidget);
    expect(find.textContaining('aucun son'), findsOneWidget);
  });

  testWidgets('la recherche filtre les modèles par leur nom', (tester) async {
    await seed(tester, 'Porte', [1]);
    await openScreen(tester);

    await tester.enterText(find.byType(TextField).first, 'zzz');
    await flush(tester);

    expect(find.text('Porte'), findsNothing);
  });

  testWidgets('supprimer demande confirmation, puis retire le modèle seul', (
    tester,
  ) async {
    await seed(tester, 'Porte', [1]);
    await openScreen(tester);

    await tester.tap(find.text('Porte'));
    await flush(tester);
    await tester.tap(find.text('Supprimer…'));
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
    expect(find.text('Porte'), findsNothing);
    expect(find.byType(SavedMultipadEditForm), findsNothing);
  });

  testWidgets('modifier : renommer et retirer un son s\'enregistre', (
    tester,
  ) async {
    await seed(tester, 'Porte', [1, 2, 3]);
    await openScreen(tester);

    await tester.tap(find.text('Porte'));
    await flush(tester);
    // Le volet de droite, comme pour un son — sans waveform ni gain, juste la
    // liste des sons.
    expect(find.byType(SavedMultipadEditForm), findsOneWidget);
    expect(find.text('SONS'), findsOneWidget);
    expect(find.text('GAIN'), findsNothing);

    await tester.enterText(editField(), 'Porte qui grince');
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

    await tester.enterText(editField(), '   ');
    await tester.pump();

    final save = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Enregistrer'),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('modifier : un son retiré se referme avant de disparaître', (
    tester,
  ) async {
    await seed(tester, 'Porte', [1, 2]);
    await openScreen(tester);
    await tester.tap(find.text('Porte'));
    await flush(tester);

    final inForm = find.descendant(
      of: find.byType(SavedMultipadEditForm),
      matching: find.text('grincement A'),
    );
    expect(inForm, findsOneWidget);

    await tester.tap(find.byTooltip('Retirer').first);
    await tester.pump(const Duration(milliseconds: 60));
    expect(inForm, findsOneWidget, reason: 'la ligne se referme encore');

    await tester.pump(const Duration(milliseconds: 400));
    expect(inForm, findsNothing);
    expect(find.byTooltip('Retirer'), findsNothing, reason: 'un son reste');
  });

  testWidgets(
    'modifier : glisser un son réordonne la liste sans erreur',
    (tester) async {
      await seed(
        tester,
        'Porte qui grince très longuement dans la nuit noire de la maison hantée',
        [1, 2, 3],
      );
      await openScreen(tester);
      tester.view.physicalSize = const Size(2400, 500);
      await tester.pump();

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.textContaining('Porte qui grince')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await mouse.down(
        tester.getCenter(find.textContaining('Porte qui grince')),
      );
      await mouse.up();
      await flush(tester);

      // Desktop : la ligne entière se glisse, sans appui long.
      final row = find.descendant(
        of: find.byType(SavedMultipadEditForm),
        matching: find.text('grincement A'),
      );
      await mouse.moveTo(tester.getCenter(row));
      await tester.pump(const Duration(milliseconds: 100));
      await mouse.down(tester.getCenter(row));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 12; i++) {
        await mouse.moveBy(const Offset(0, 30));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await mouse.up();
      // Pas de `pumpAndSettle` : le nom long de la ligne survolée défile en
      // boucle.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Enregistrer'));
      await flush(tester);
      final saved = (await tester.runAsync(
        () => repository.getSavedMultipads(),
      ))!.single;
      expect(saved.sounds.map((s) => s.displayName).toList(), [
        'grincement B',
        'grincement C',
        'grincement A',
      ]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
