import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/app/app_services.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/core/database/sounds.dart' show SoundType;
// `PadPlayMode` existe en DEUX exemplaires distincts : celui de la base
// (`core/database/sounds.dart`) et celui du domaine
// (`features/sampler/domain/entities/pad.dart`). Une ligne Drift porte le
// premier, l'API des repositories parle le second — les comparer sans préfixe
// donne un échec illisible où les deux valeurs s'affichent à l'identique.
import 'package:stage_cue/core/database/sounds.dart' as dbe show PadPlayMode;
import 'package:stage_cue/core/settings/app_preferences.dart'
    show ConnectivityMode;
import 'package:stage_cue/core/theme/app_theme.dart';
import 'package:stage_cue/features/sampler/domain/entities/pad.dart'
    show PadPlayMode;
import 'package:stage_cue/features/sampler/presentation/screens/sampler_screen.dart';
import 'package:stage_cue/features/sampler/presentation/widgets/pad_item.dart'
    show PadCard;
import 'package:stage_cue/features/sampler/presentation/widgets/threshold_draggable.dart'
    show kPadDragSlop;

/// Tests d'intégration UI : montent le VRAI `SamplerScreen` sur la vraie stack
/// (base Drift en mémoire, repositories et `SamplerNotifier` réels) et vérifient
/// des scénarios bout-en-bout. Les tests unitaires et de widget existants
/// remplacent justement ces couches par des mocks — ce fichier couvre ce que
/// cette substitution laisse échapper : leur câblage.
///
/// Trois contraintes d'environnement, à connaître avant d'ajouter un scénario :
///
/// 1. **Aucun son n'est joué.** flutter_soloud est un moteur natif, absent de la
///    VM de test : tout préchargement échoue et marque le chemin illisible
///    (`markPathUnloadable`). Un scénario « je tape le pad, j'entends le son »
///    est hors de portée ici et reste un test manuel sur machine.
/// 2. **Le mode est forcé sur [ConnectivityMode.offline]** (catalogue complet,
///    sans réseau). Le défaut applicatif est `liveOffline`, qui masque les pads
///    dont aucun son n'est disponible localement — or le point 1 rend *tous* les
///    sons indisponibles sous test. En `liveOffline` la grille serait donc
///    toujours vide, et une assertion « le pad est masqué » passerait pour la
///    mauvaise raison.
/// 3. **`pumpAndSettle` est proscrit** : l'écran porte des animations
///    perpétuelles (régie musique) qui ne se stabilisent jamais. On pompe un
///    nombre borné de frames, en alternant avec [WidgetTester.runAsync] — sans
///    quoi les I/O disque réelles (sonde de disponibilité des pads) ne se
///    termineraient jamais sous l'horloge simulée de `testWidgets`.
void main() {
  late db.AppDatabase database;
  late AppServices services;
  late Directory fixturesDir;

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    services = AppServices.forTesting(database);
    services.appPreferences.debugSetConnectivityMode(ConnectivityMode.offline);
    fixturesDir = Directory.systemTemp.createTempSync('stage_cue_it_');
  });

  tearDown(() async {
    await database.close();
    if (fixturesDir.existsSync()) {
      fixturesDir.deleteSync(recursive: true);
    }
  });

  /// Laisse les I/O disque réelles se terminer, puis rend une frame.
  ///
  /// `testWidgets` exécute le corps du test sous une horloge simulée où les
  /// futures adossées à l'event loop de l'OS ne se complètent pas ; `runAsync`
  /// rebascule le temps de ces attentes sur l'event loop réel.
  /// [rounds] est empirique : le chargement d'un plateau enchaîne plusieurs
  /// allers-retours base ↔ disque (boards, pads, puis sonde de disponibilité par
  /// son), et chacun ne progresse que d'un cran par cycle. Trop peu de cycles et
  /// la grille est encore vide au moment des assertions.
  Future<void> flushIo(WidgetTester tester, {int rounds = 20}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Monte l'écran sur une fenêtre large (layout desktop, sidebar visible).
  ///
  /// Chaque appel force un `State` neuf via une clé unique. Sans elle, Flutter
  /// réutilise l'état existant et `initState` — donc `loadBoards` — ne rejoue
  /// pas : un second appel n'observerait jamais les données écrites entre-temps.
  /// Avec la clé, remonter l'écran relit réellement la base, ce qui est
  /// exactement le scénario « je relance l'app » que l'on veut couvrir.
  Future<void> pumpSampler(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: SamplerScreen(key: UniqueKey(), services: services),
      ),
    );
    await flushIo(tester);
  }

  /// Fichier audio factice mais *plausible* : en-tête RIFF/WAVE et taille
  /// au-dessus de `kMinimumValidAudioFileBytes`. Aucun décodage réel n'a lieu.
  File writeFakeWav(String name) {
    final file = File(p.join(fixturesDir.path, '$name.wav'));
    final bytes = BytesBuilder()
      ..add('RIFF'.codeUnits)
      ..add(Uint8List(4))
      ..add('WAVEfmt '.codeUnits)
      ..add(Uint8List(1024));
    file.writeAsBytesSync(bytes.takeBytes());
    return file;
  }

  Future<int> insertSound(String title) {
    return database.into(database.sounds).insert(
          db.SoundsCompanion.insert(
            title: title,
            filePath: writeFakeWav(title).path,
            type: const Value(SoundType.soundEffect),
          ),
        );
  }

  /// Noms des pads en base, dans leur ordre d'affichage (`sortOrder`).
  Future<List<String?>> padNamesInOrder() async {
    final pads = await database.select(database.pads).get()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return pads.map((pad) => pad.name).toList();
  }

  /// Identifiant du plateau créé d'office au premier lancement.
  Future<int> firstBoardId() async {
    final boards = await database.select(database.soundBoards).get();
    return boards.first.id;
  }

  Future<void> addPad(
    int boardId, {
    required String name,
    required String soundTitle,
    int sortOrder = 0,
    int? colorValue,
    PadPlayMode playMode = PadPlayMode.random,
  }) async {
    await services.soundRepository.createPadWithSettings(
      boardId: boardId,
      soundIds: [await insertSound(soundTitle)],
      name: name,
      colorValue: colorValue,
      playMode: playMode,
      sortOrder: sortOrder,
    );
  }

  /// Croix de suppression du pad portant [padName].
  Finder removeCrossOf(String padName) => find.descendant(
        of: find.ancestor(
          of: find.text(padName),
          matching: find.byType(PadCard),
        ),
        matching: find.byIcon(Icons.close),
      );

  /// Glisse le pad [from] sur la position du pad [to].
  ///
  /// Le drop n'est pas résolu par un `DragTarget` mais géométriquement, à
  /// partir de la position globale du pointeur — d'où le `moveTo` sur le centre
  /// de la cible plutôt qu'un simple `drag` par delta.
  Future<void> dragPadOnto(WidgetTester tester, String from, String to) async {
    final start = tester.getCenter(find.text(from));
    final end = tester.getCenter(find.text(to));

    final gesture = await tester.startGesture(start);
    // `ThresholdDraggable` n'accroche le geste qu'au-delà de [kPadDragSlop] ;
    // un premier mouvement franchit ce seuil et déclenche `onDragStarted`.
    await gesture.moveBy(const Offset(kPadDragSlop + 8, 0));
    await tester.pump();
    // `_editDragUiReady` est posé dans un post-frame : sans cette 2e frame, la
    // grille de drop n'est pas encore montée.
    await tester.pump();

    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await flushIo(tester);
  }

  /// Bascule sur la scène [boardName].
  ///
  /// En layout desktop les plateaux ne sont pas listés à l'écran : ils vivent
  /// dans le menu porté par le titre de la scène courante. Il faut donc ouvrir
  /// ce menu avant de pouvoir choisir.
  Future<void> selectBoard(WidgetTester tester, String boardName) async {
    await tester.tap(find.byType(PopupMenuButton<Object>).first);
    await flushIo(tester);
    // `.last` : le nom apparaît aussi dans le titre si c'est la scène courante.
    await tester.tap(find.text(boardName).last);
    await flushIo(tester);
  }

  /// Envoie `Ctrl` + [key] à l'écran focalisé.
  Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await flushIo(tester);
    // Plusieurs actions (annulation, validation d'une recherche-éclair) mettent
    // le pad concerné en surbrillance via un timer différé de
    // `_padEmphasisDuration` (2,2 s). `flutter_test` refuse de terminer un test
    // sur un timer en vol : on laisse le temps simulé s'écouler au-delà.
    await tester.pump(const Duration(milliseconds: 2500));
  }

  Future<void> pressCtrlZ(WidgetTester tester) =>
      pressCtrl(tester, LogicalKeyboardKey.keyZ);

  group('Lancement', () {
    testDesktopWidgets(
      'base vide → une scène par défaut est créée, affichée et persistée',
      (tester) async {
        expect(await database.select(database.soundBoards).get(), isEmpty);

        await pumpSampler(tester);

        expect(find.text('Scène 1'), findsWidgets);
        final boards = await database.select(database.soundBoards).get();
        expect(boards, hasLength(1));
        expect(boards.first.name, 'Scène 1');
      },
    );

    testDesktopWidgets(
      'les pads du plateau sont relus depuis la base au montage',
      (tester) async {
        await pumpSampler(tester);
        final boardId = await firstBoardId();
        await addPad(boardId, name: 'Porte qui claque', soundTitle: 'porte');
        await addPad(
          boardId,
          name: 'Tonnerre',
          soundTitle: 'tonnerre',
          sortOrder: 1,
        );

        await pumpSampler(tester);

        expect(find.text('Porte qui claque'), findsOneWidget);
        expect(find.text('Tonnerre'), findsOneWidget);
      },
    );
  });

  group('Suppression et annulation', () {
    testDesktopWidgets(
      'retirer un pad le fait disparaître de l UI et de la base',
      (tester) async {
        await pumpSampler(tester);
        final boardId = await firstBoardId();
        await addPad(boardId, name: 'Porte qui claque', soundTitle: 'porte');
        await pumpSampler(tester);
        expect(find.text('Porte qui claque'), findsOneWidget);

        await tester.tap(removeCrossOf('Porte qui claque'));
        await flushIo(tester);

        expect(find.text('Porte qui claque'), findsNothing);
        expect(await database.select(database.pads).get(), isEmpty);
      },
    );

    testDesktopWidgets(
      'Ctrl+Z restaure le pad supprimé avec sa position et ses réglages',
      (tester) async {
        await pumpSampler(tester);
        final boardId = await firstBoardId();
        for (final (index, name) in ['Un', 'Deux', 'Trois'].indexed) {
          await addPad(
            boardId,
            name: name,
            soundTitle: 'son$index',
            sortOrder: index,
            colorValue: 0xFF00FF00,
            playMode: PadPlayMode.sequential,
          );
        }
        await pumpSampler(tester);

        // Le pad du milieu : la restauration a une vraie position à retrouver,
        // et pas simplement « à la fin ».
        await tester.tap(removeCrossOf('Deux'));
        await flushIo(tester);
        expect(find.text('Deux'), findsNothing);

        await pressCtrlZ(tester);

        expect(find.text('Deux'), findsOneWidget);

        // Les réglages du pad restauré sont relus en base, pas dans l'UI.
        final pads = await database.select(database.pads).get();
        final restored = pads.firstWhere((pad) => pad.name == 'Deux');
        expect(restored.sortOrder, 1, reason: 'position d origine');
        expect(restored.color, 0xFF00FF00);
        expect(restored.playMode, dbe.PadPlayMode.sequential);
      },
    );

    testDesktopWidgets(
      'un second Ctrl+Z ne duplique pas le pad restauré',
      (tester) async {
        await pumpSampler(tester);
        final boardId = await firstBoardId();
        await addPad(boardId, name: 'Porte qui claque', soundTitle: 'porte');
        await pumpSampler(tester);

        await tester.tap(removeCrossOf('Porte qui claque'));
        await flushIo(tester);

        await pressCtrlZ(tester);
        await pressCtrlZ(tester);

        // Le snapshot est consommé par la première annulation : la seconde ne
        // doit rien recréer, sous peine de doublons à chaque frappe répétée.
        expect(find.text('Porte qui claque'), findsOneWidget);
        final pads = await database.select(database.pads).get();
        expect(pads.where((pad) => pad.name == 'Porte qui claque'), hasLength(1));
      },
    );
  });

  group('Réorganisation', () {
    testDesktopWidgets(
      'glisser un pad en fin de rangée persiste le nouvel ordre',
      (tester) async {
        await pumpSampler(tester);
        final boardId = await firstBoardId();
        for (final (index, name) in ['Un', 'Deux', 'Trois'].indexed) {
          await addPad(
            boardId,
            name: name,
            soundTitle: 'son$index',
            sortOrder: index,
          );
        }
        await pumpSampler(tester);
        expect(await padNamesInOrder(), ['Un', 'Deux', 'Trois']);

        await dragPadOnto(tester, 'Un', 'Trois');

        expect(await padNamesInOrder(), ['Deux', 'Trois', 'Un']);

        // L'ordre doit être persisté, pas seulement réarrangé à l'écran :
        // on remonte l'écran, ce qui le relit depuis la base.
        await pumpSampler(tester);
        expect(await padNamesInOrder(), ['Deux', 'Trois', 'Un']);
      },
    );
  });

  group('Recherche-éclair', () {
    testDesktopWidgets(
      'Ctrl+F puis Ctrl+Entrée pose le son trouvé sur le plateau',
      (tester) async {
        await pumpSampler(tester);
        // Son présent en bibliothèque mais absent du plateau.
        await insertSound('tonnerre');
        await pumpSampler(tester);
        expect(await database.select(database.pads).get(), isEmpty);

        await pressCtrl(tester, LogicalKeyboardKey.keyF);
        expect(
          find.byType(TextField),
          findsOneWidget,
          reason: 'Ctrl+F doit ouvrir la recherche-éclair',
        );

        await tester.enterText(find.byType(TextField), 'tonnerre');
        await flushIo(tester);

        // Le tap sur un résultat ne fait que pré-écouter ; c'est Ctrl+Entrée
        // qui valide et pose le son sur le plateau.
        await pressCtrl(tester, LogicalKeyboardKey.enter);

        final pads = await database.select(database.pads).get();
        expect(pads, hasLength(1));
        final padSounds = await database.select(database.padSounds).get();
        expect(padSounds, hasLength(1));
      },
    );
  });

  group('Plateaux multiples', () {
    testDesktopWidgets('changer de scène recharge les pads correspondants', (
      tester,
    ) async {
      await pumpSampler(tester);
      final boardA = await firstBoardId();
      final boardB = await services.soundRepository.createSoundBoard('Scène 2');
      await addPad(boardA, name: 'Pad de A', soundTitle: 'a');
      await addPad(boardB, name: 'Pad de B', soundTitle: 'b');

      await pumpSampler(tester);
      expect(find.text('Pad de A'), findsOneWidget);
      expect(find.text('Pad de B'), findsNothing);

      await selectBoard(tester, 'Scène 2');

      expect(find.text('Pad de B'), findsOneWidget);
      expect(find.text('Pad de A'), findsNothing);
    });
  });
}

/// `testWidgets` présentant la plateforme comme un poste desktop natif.
///
/// Les chemins desktop de `SamplerScreen` (raccourcis clavier, sidebar) sont
/// gardés par `isNativeDesktopPlatform()` ; sans override, `flutter_test` se
/// présente comme Android et ces branches resteraient mortes.
///
/// L'override est remis à zéro **dans le corps du test** et non dans un
/// `tearDown` : `flutter_test` vérifie qu'aucune variable de debug ne survit au
/// corps du test, contrôle qui s'exécute avant les `tearDown`.
void testDesktopWidgets(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    // Sous test, aucun son n'est chargeable (pas de moteur natif) : chaque pad
    // affiche donc en permanence son libellé d'indisponibilité, plus long que
    // ce que la tuile réserve — d'où un débordement de layout qui n'a rien à
    // voir avec le scénario joué. On ne masque QUE ce cas ; toute autre erreur
    // de rendu continue de faire échouer le test.
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
        return;
      }
      previousOnError?.call(details);
    };
    try {
      await body(tester);
    } finally {
      FlutterError.onError = previousOnError;
      debugDefaultTargetPlatformOverride = null;
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
