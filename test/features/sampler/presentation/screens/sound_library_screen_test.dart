import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/core/database/sounds.dart' show SoundType;
import 'package:stage_cue/core/theme/app_icons.dart';
import 'package:stage_cue/core/theme/app_theme.dart';
import 'package:stage_cue/features/sampler/data/repositories/sound_repository.dart';
import 'package:stage_cue/features/sampler/presentation/screens/sound_library_screen.dart';

import '../../../../support/find_stroke_icon.dart';

/// Écran « Ajouter un son » sur une vraie base Drift en mémoire : filtre par
/// type, recherche, rang des sons déjà posés, et les deux façons d'ajouter.
void main() {
  late db.AppDatabase database;
  late int boardId;
  SoundLibraryScreenResult? result;

  setUp(() async {
    result = null;
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    boardId = await database
        .into(database.soundBoards)
        .insert(db.SoundBoardsCompanion.insert(name: 'Scène'));
  });

  tearDown(() => database.close());

  Future<int> insertSound(String title, SoundType? type) => database
      .into(database.sounds)
      .insert(
        db.SoundsCompanion.insert(
          title: title,
          displayName: title,
          filePath: '/cache/$title.wav',
          type: Value(type),
        ),
      );

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

  /// Ouvre l'écran par-dessus une page hôte, pour recevoir son résultat.
  Future<void> openScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context)
                      .push<SoundLibraryScreenResult>(
                        MaterialPageRoute(
                          builder: (_) => SoundLibraryScreen(
                            database: database,
                            boardId: boardId,
                          ),
                        ),
                      );
                },
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pump(const Duration(milliseconds: 400));
    await flush(tester);
    // Laisse finir les entrées en fondu des lignes.
    await tester.pump(const Duration(seconds: 1));
  }

  Future<List<db.Pad>> padsOfBoard(WidgetTester tester) async =>
      (await tester.runAsync(
        () => (database.select(
          database.pads,
        )..where((p) => p.boardId.equals(boardId))).get(),
      ))!;

  Future<int> placeOnBoard(WidgetTester tester, int soundId) async =>
      (await tester.runAsync(
        () =>
            SoundRepository.fromDatabase(database).createPad(boardId, soundId),
      ))!;

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    // Anti-rebond de 250 ms, puis la requête de tags côté base.
    await tester.pump(const Duration(milliseconds: 300));
    await flush(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  Finder row(String title) => find.text(title);

  group('filtre par type', () {
    testWidgets('ne montre que les bruitages au départ, et pas les sons '
        'sans type', (tester) async {
      await insertSound('Porte', SoundType.soundEffect);
      await insertSound('Pluie', SoundType.ambiance);
      await insertSound('Thème', SoundType.music);
      await insertSound('Inconnu', null);
      await openScreen(tester);

      expect(row('Porte'), findsOneWidget);
      expect(row('Pluie'), findsNothing);
      expect(row('Thème'), findsNothing);
      expect(row('Inconnu'), findsNothing);
    });

    testWidgets('les onglets Ambiance et Musique changent la liste', (
      tester,
    ) async {
      await insertSound('Porte', SoundType.soundEffect);
      await insertSound('Pluie', SoundType.ambiance);
      await insertSound('Thème', SoundType.music);
      await openScreen(tester);

      // Deux frames : l'AnimatedSwitcher retire l'ancienne liste à la suivante.
      await tester.tap(find.text('Ambiance'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(row('Pluie'), findsOneWidget);
      expect(row('Porte'), findsNothing);

      await tester.tap(find.text('Musique'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(row('Thème'), findsOneWidget);
      expect(row('Pluie'), findsNothing);
    });

    testWidgets('un type sans son annonce qu\'il n\'y en a pas', (
      tester,
    ) async {
      await insertSound('Porte', SoundType.soundEffect);
      await openScreen(tester);

      await tester.tap(find.text('Musique'));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Aucun musique disponible'), findsOneWidget);
    });
  });

  group('recherche', () {
    setUp(() async {
      await insertSound('Porte grinçante', SoundType.soundEffect);
      await insertSound('Pas sur gravier', SoundType.soundEffect);
    });

    testWidgets('filtre par titre et dit quand rien ne correspond', (
      tester,
    ) async {
      await openScreen(tester);

      await search(tester, 'gravier');
      expect(row('Pas sur gravier'), findsOneWidget);
      expect(row('Porte grinçante'), findsNothing);

      await search(tester, 'zzzzzz');
      expect(find.text('Aucun bruitage trouvé'), findsOneWidget);
    });

    testWidgets('ignore les accents et la casse', (tester) async {
      await openScreen(tester);

      await search(tester, 'GRINCANTE');

      expect(row('Porte grinçante'), findsOneWidget);
      expect(row('Pas sur gravier'), findsNothing);
    });

    testWidgets('plusieurs mots : tous doivent correspondre', (tester) async {
      await openScreen(tester);

      await search(tester, 'porte gravier');
      expect(find.text('Aucun bruitage trouvé'), findsOneWidget);

      await search(tester, 'porte grin');
      expect(row('Porte grinçante'), findsOneWidget);
    });

    testWidgets('la croix vide la recherche et rend la liste entière', (
      tester,
    ) async {
      await openScreen(tester);
      await search(tester, 'gravier');
      expect(row('Porte grinçante'), findsNothing);

      await tester.tap(findStrokeIcon(AppIcons.close));
      await tester.pump(const Duration(seconds: 1));

      expect(row('Porte grinçante'), findsOneWidget);
      expect(row('Pas sur gravier'), findsOneWidget);
    });

    testWidgets('la recherche reste dans le type choisi', (tester) async {
      await insertSound('Porte de grange', SoundType.ambiance);
      await openScreen(tester);

      await search(tester, 'porte');
      expect(row('Porte de grange'), findsNothing);

      await tester.tap(find.text('Ambiance'));
      await tester.pump(const Duration(milliseconds: 300));
      await flush(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(row('Porte de grange'), findsOneWidget);
      expect(row('Porte grinçante'), findsNothing);
    });
  });

  group('sons déjà sur la scène', () {
    late int posedId;

    setUp(() async {
      posedId = await insertSound('Porte avant', SoundType.soundEffect);
      await insertSound('Porte cochère', SoundType.soundEffect);
    });

    double top(WidgetTester tester, String title) =>
        tester.getTopLeft(row(title)).dy;

    testWidgets('relégués en bas tant que la recherche est courte', (
      tester,
    ) async {
      await placeOnBoard(tester, posedId);
      await openScreen(tester);

      expect(
        top(tester, 'Porte cochère'),
        lessThan(top(tester, 'Porte avant')),
      );

      await search(tester, 'port');
      expect(
        top(tester, 'Porte cochère'),
        lessThan(top(tester, 'Porte avant')),
      );
    });

    testWidgets('gardent leur rang d\'origine dès qu\'une recherche est '
        'précise ($kMinPreciseSoundLibrarySearchLength+ caractères)', (
      tester,
    ) async {
      await placeOnBoard(tester, posedId);
      await openScreen(tester);

      await search(tester, 'porte');

      expect(
        top(tester, 'Porte avant'),
        lessThan(top(tester, 'Porte cochère')),
      );
    });
  });

  group('ajout', () {
    testWidgets('GO sur un nouveau son crée le pad et rend son id', (
      tester,
    ) async {
      await insertSound('Porte', SoundType.soundEffect);
      await openScreen(tester);

      await tester.tap(find.text('GO'));
      await tester.pump(const Duration(milliseconds: 300));
      await flush(tester);
      await tester.pump(const Duration(seconds: 1));

      final pads = await padsOfBoard(tester);
      expect(pads, hasLength(1));
      expect(result?.wasAdded, isTrue);
      expect(result?.highlightPadId, pads.single.id);
      expect(find.text('Ajouter un son'), findsNothing, reason: 'écran fermé');
    });

    testWidgets('GO sur un son déjà posé ne crée rien : il désigne son pad', (
      tester,
    ) async {
      final soundId = await insertSound('Porte', SoundType.soundEffect);
      final padId = await placeOnBoard(tester, soundId);
      await openScreen(tester);

      await tester.tap(find.text('GO'));
      await tester.pump(const Duration(milliseconds: 300));
      await flush(tester);

      expect(result?.wasAdded, isFalse);
      expect(result?.highlightPadId, padId);
      expect(await padsOfBoard(tester), hasLength(1));
    });

    testWidgets('le bouton secondaire ajoute sans fermer, une seule fois', (
      tester,
    ) async {
      await insertSound('Porte', SoundType.soundEffect);
      await openScreen(tester);

      expect(findStrokeIcon(AppIcons.allSounds), findsOneWidget);
      await tester.tap(findStrokeIcon(AppIcons.allSounds));
      await tester.pump(const Duration(milliseconds: 300));
      await flush(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(await padsOfBoard(tester), hasLength(1));
      expect(
        find.text('Ajouter un son'),
        findsOneWidget,
        reason: 'reste ouvert',
      );
      expect(result, isNull);
      expect(findStrokeIcon(AppIcons.check), findsOneWidget);
      expect(findStrokeIcon(AppIcons.allSounds), findsNothing);

      await tester.tap(findStrokeIcon(AppIcons.check), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      await flush(tester);
      expect(await padsOfBoard(tester), hasLength(1));
    });
  });
}
