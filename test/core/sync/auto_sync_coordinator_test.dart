// Verrouille la SÉQUENCE de lancement orchestrée par [AutoSyncCoordinator].
//
// Les unités qu'il assemble sont couvertes ailleurs ; ce qui n'était couvert
// nulle part, c'est leur ORDRE et leurs conditions — précisément là où vivent
// les invariants des décisions 0005 et 0021, dont la violation ne se manifeste
// que sur un appareil vierge ou un réseau lent (donc rarement en développement).
//
// L'invariant central : `pruneSoundsAbsentFromDrive` ne doit être appelé
// qu'avec l'ensemble issu d'un scan COMPLET. L'appeler après une passe
// incrémentale supprimerait tout ce qui n'a pas changé.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/core/settings/app_preferences.dart';
import 'package:stage_cue/core/sync/auto_sync_coordinator.dart';
import 'package:stage_cue/features/sampler/data/repositories/library_repository.dart';
import 'package:stage_cue/features/sampler/domain/entities/library.dart';
import 'package:stage_cue/features/sampler/presentation/providers/sync_controller.dart';

class MockLibraryRepository extends Mock implements LibraryRepository {}

class MockSyncController extends Mock implements SyncController {}

/// Préférences minimales : seul `allowsNetworkSync` intéresse le coordinateur.
class FakeAppPreferences extends AppPreferences {
  FakeAppPreferences({bool allowsNetworkSync = true})
      : _allows = allowsNetworkSync;

  bool _allows;

  @override
  bool get allowsNetworkSync => _allows;

  void setAllowsNetworkSync(bool value) {
    _allows = value;
    notifyListeners();
  }
}

Library _library(int id, {String? driveFolderId = 'drive-root'}) => Library(
      id: id,
      name: 'Lib$id',
      localRootPath: '/cache/$id',
      driveFolderId: driveFolderId,
      createdAt: DateTime(2026),
    );

void main() {
  late db.AppDatabase database;
  late MockLibraryRepository repository;
  late MockSyncController syncController;
  late FakeAppPreferences preferences;
  late AutoSyncCoordinator coordinator;

  /// Ordre d'appel observé, pour vérifier la séquence et pas seulement le fait.
  late List<String> calls;

  setUpAll(() {
    registerFallbackValue(_library(0));
    registerFallbackValue(<String>{});
  });

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    repository = MockLibraryRepository();
    syncController = MockSyncController();
    preferences = FakeAppPreferences();
    calls = [];

    when(() => repository.cleanupPartialDownloads()).thenAnswer((_) async {});
    when(() => repository.markInitialSyncSettled()).thenReturn(null);
    when(() => repository.reconnectSilently()).thenAnswer((_) async => true);
    when(() => repository.getLibraries()).thenAnswer((_) async => []);
    when(() => syncController.markOffline()).thenReturn(null);
    when(() => syncController.schedulePush(any())).thenReturn(null);

    coordinator = AutoSyncCoordinator(
      database,
      repository,
      syncController,
      preferences,
    );
  });

  tearDown(() async {
    coordinator.dispose();
    await database.close();
  });

  /// Branche les collaborateurs en enregistrant l'ordre des appels.
  void stubSequence({
    required List<Library> libraries,
    DriveSyncOutcome Function(Library)? onApplyChanges,
    Set<String> Function(Library)? onIndex,
    Object? indexThrows,
  }) {
    when(() => repository.getLibraries()).thenAnswer((_) async => libraries);

    when(() => repository.applyDriveChanges(library: any(named: 'library')))
        .thenAnswer((invocation) async {
      final library = invocation.namedArguments[#library] as Library;
      calls.add('apply:${library.id}');
      return onApplyChanges?.call(library) ??
          const DriveSyncNeedsFullScan('test');
    });

    when(() => repository.indexDriveFolder(library: any(named: 'library')))
        .thenAnswer((invocation) async {
      final library = invocation.namedArguments[#library] as Library;
      calls.add('index:${library.id}');
      if (indexThrows != null) throw indexThrows;
      return DriveIndexResult(
        newFileCount: 0,
        presentDriveFileIds: onIndex?.call(library) ?? {'f1'},
      );
    });

    when(() => syncController.pullForLaunch(any())).thenAnswer((
      invocation,
    ) async {
      final library = invocation.positionalArguments.first as Library;
      calls.add('pull:${library.id}');
    });

    when(() => repository.pruneSoundsAbsentFromDrive(
          library: any(named: 'library'),
          presentDriveFileIds: any(named: 'presentDriveFileIds'),
        )).thenAnswer((invocation) async {
      final library = invocation.namedArguments[#library] as Library;
      calls.add('prune:${library.id}');
      return 0;
    });
  }

  /// Lance la passe et attend qu'elle se termine (elle est `unawaited`).
  Future<void> runInitialPull() async {
    final settled = <bool>[];
    coordinator.onInitialPullSettled = () => settled.add(true);
    coordinator.start();
    // Laisse les futures en vol se résoudre.
    for (var i = 0; i < 20 && settled.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(settled, isNotEmpty, reason: 'la passe doit toujours se conclure');
  }

  group('séquence de lancement', () {
    test('ordre strict : indexer, puis tirer, puis ré-élaguer', () async {
      final library = _library(1);
      stubSequence(libraries: [library]);

      await runInitialPull();

      expect(calls, ['apply:1', 'index:1', 'pull:1', 'prune:1']);
    });

    test('scan complet : l\'élagage reçoit l\'ensemble DU SCAN', () async {
      final library = _library(1);
      stubSequence(
        libraries: [library],
        onIndex: (_) => {'a', 'b', 'c'},
      );

      await runInitialPull();

      final captured = verify(
        () => repository.pruneSoundsAbsentFromDrive(
          library: any(named: 'library'),
          presentDriveFileIds: captureAny(named: 'presentDriveFileIds'),
        ),
      ).captured.single as Set<String>;
      expect(captured, {'a', 'b', 'c'});
    });

    test('passe INCRÉMENTALE : aucun scan, et surtout AUCUN élagage', () async {
      final library = _library(1);
      stubSequence(
        libraries: [library],
        onApplyChanges: (_) =>
            const DriveSyncApplied(upserted: 2, removed: 1),
      );

      await runInitialPull();

      // Le pull a bien lieu, mais sans scan ni élagage : un delta ne connaît
      // pas l'ensemble des fichiers présents, l'élaguer par différence
      // supprimerait tout ce qui n'a pas bougé (cf. décision 0021).
      expect(calls, ['apply:1', 'pull:1']);
      verifyNever(() => repository.indexDriveFolder(library: any(named: 'library')));
      verifyNever(
        () => repository.pruneSoundsAbsentFromDrive(
          library: any(named: 'library'),
          presentDriveFileIds: any(named: 'presentDriveFileIds'),
        ),
      );
    });

    test('index en échec : la bibliothèque est écartée du pull, les autres '
        'continuent', () async {
      final ok = _library(1);
      final broken = _library(2);
      when(() => repository.getLibraries())
          .thenAnswer((_) async => [broken, ok]);

      when(() => repository.applyDriveChanges(library: any(named: 'library')))
          .thenAnswer((invocation) async {
        final library = invocation.namedArguments[#library] as Library;
        calls.add('apply:${library.id}');
        return const DriveSyncNeedsFullScan('test');
      });
      when(() => repository.indexDriveFolder(library: any(named: 'library')))
          .thenAnswer((invocation) async {
        final library = invocation.namedArguments[#library] as Library;
        calls.add('index:${library.id}');
        if (library.id == 2) throw StateError('dossier injoignable');
        return const DriveIndexResult(
          newFileCount: 0,
          presentDriveFileIds: {'f1'},
        );
      });
      when(() => syncController.pullForLaunch(any())).thenAnswer((inv) async {
        calls.add('pull:${(inv.positionalArguments.first as Library).id}');
      });
      when(() => repository.pruneSoundsAbsentFromDrive(
            library: any(named: 'library'),
            presentDriveFileIds: any(named: 'presentDriveFileIds'),
          )).thenAnswer((inv) async {
        calls.add('prune:${(inv.namedArguments[#library] as Library).id}');
        return 0;
      });

      await runInitialPull();

      // La bibliothèque 2 est indexée puis abandonnée : ni pull ni élagage.
      // Un index partiel suivi d'un pull racine purgerait ses boards et les
      // recâblerait sur un sous-ensemble de sons (cf. décision 0005).
      expect(calls, ['apply:2', 'index:2', 'apply:1', 'index:1', 'pull:1',
          'prune:1']);
    });
  });

  group('conditions d\'entrée', () {
    test('mode local : aucune synchro déclenchée', () async {
      preferences = FakeAppPreferences(allowsNetworkSync: false);
      coordinator.dispose();
      coordinator = AutoSyncCoordinator(
        database,
        repository,
        syncController,
        preferences,
      );
      stubSequence(libraries: [_library(1)]);

      await runInitialPull();

      expect(calls, isEmpty);
      verifyNever(() => repository.reconnectSilently());
    });

    test('aucune bibliothèque connectée : reste idle, pas de hors-ligne',
        () async {
      when(() => repository.getLibraries())
          .thenAnswer((_) async => [_library(1, driveFolderId: null)]);

      await runInitialPull();

      verifyNever(() => syncController.markOffline());
      expect(calls, isEmpty);
    });

    test('bibliothèque configurée mais sans session : hors-ligne, pas de pull',
        () async {
      when(() => repository.reconnectSilently()).thenAnswer((_) async => false);
      stubSequence(libraries: [_library(1)]);

      await runInitialPull();

      verify(() => syncController.markOffline()).called(1);
      expect(calls, isEmpty);
    });

    test('erreur inattendue : bascule hors-ligne, la passe se conclut quand '
        'même', () async {
      when(() => repository.reconnectSilently())
          .thenThrow(StateError('panne'));

      await runInitialPull(); // `runInitialPull` assère déjà que ça se conclut.

      verify(() => syncController.markOffline()).called(1);
      verify(() => repository.markInitialSyncSettled()).called(1);
    });
  });

  group('push déclenché par les écritures', () {
    test('les écritures de la passe initiale ne déclenchent AUCUN push',
        () async {
      final library = _library(1);
      stubSequence(
        libraries: [library],
        onApplyChanges: (_) => const DriveSyncApplied(upserted: 1, removed: 0),
      );

      await runInitialPull();

      // Le contenu vient du distant, pas d'une édition locale : le pousser
      // renverrait à Drive ce qu'on vient d'en recevoir.
      verifyNever(() => syncController.schedulePush(any()));
    });

    test('une écriture de bookkeeping seule ne déclenche pas de push', () async {
      when(() => repository.getLibraries())
          .thenAnswer((_) async => [_library(1)]);
      final rowId = await database.into(database.libraries).insert(
            db.LibrariesCompanion.insert(name: 'L', localRootPath: '/c'),
          );
      await runInitialPull();
      clearInteractions(syncController);

      // `libraries` et `library_folders` ne voyagent dans aucun snapshot : une
      // écriture qui ne touche qu'elles n'a rien à pousser, et déclencher un
      // push ici le ferait se relancer en boucle. Écriture par l'API typée de
      // Drift, seule à émettre un événement `tableUpdates` — un
      // `customStatement` n'en émet aucun et rendrait ce test vacuous.
      await (database.update(database.libraries)
            ..where((l) => l.id.equals(rowId)))
          .write(const db.LibrariesCompanion(
        lastSyncedRevision: Value(2),
      ));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      verifyNever(() => syncController.schedulePush(any()));
    });

    test('une écriture de données utilisateur déclenche un push', () async {
      when(() => repository.getLibraries())
          .thenAnswer((_) async => [_library(1)]);
      await runInitialPull();
      clearInteractions(syncController);

      // Contre-épreuve du test précédent : même mécanique d'écriture, table
      // non-bookkeeping. Sans ce cas, un filtre trop large (qui bloquerait
      // TOUT push) passerait le test ci-dessus sans qu'on s'en aperçoive.
      await database.into(database.soundBoards).insert(
            db.SoundBoardsCompanion.insert(name: 'Scène 1'),
          );
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      verify(() => syncController.schedulePush(any())).called(1);
    });
  });
}
