// Verrouille la place de l'analyse automatique des tags (décision 0029) dans
// l'orchestration de [AutoSyncCoordinator] : APRÈS le pull, jamais pendant le
// Mode Spectacle ni en arrière-plan, sans retenir une passe de synchro, et suivie
// d'un push quand elle a écrit quelque chose.

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stage_cue/core/autotag/auto_tag_service.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/core/settings/app_preferences.dart';
import 'package:stage_cue/core/sync/auto_sync_coordinator.dart';
import 'package:stage_cue/features/sampler/data/repositories/library_repository.dart';
import 'package:stage_cue/features/sampler/domain/entities/library.dart';
import 'package:stage_cue/features/sampler/presentation/providers/sync_controller.dart';

class MockLibraryRepository extends Mock implements LibraryRepository {}

class MockSyncController extends Mock implements SyncController {}

class MockAutoTagService extends Mock implements AutoTagService {}

class FakePreferences extends AppPreferences {
  bool allows = true;

  @override
  bool get allowsNetworkSync => allows;
}

Library _library(int id) => Library(
  id: id,
  name: 'Lib$id',
  localRootPath: '/cache/$id',
  driveFolderId: 'drive-root',
  createdAt: DateTime(2026),
);

void main() {
  late db.AppDatabase database;
  late MockLibraryRepository repository;
  late MockSyncController syncController;
  late MockAutoTagService autoTag;
  late FakePreferences preferences;
  late AutoSyncCoordinator coordinator;
  late List<String> events;
  late String? Function() lastStopReason;
  var paused = false;

  setUpAll(() {
    registerFallbackValue(_library(0));
  });

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    repository = MockLibraryRepository();
    syncController = MockSyncController();
    autoTag = MockAutoTagService();
    preferences = FakePreferences();
    events = [];
    paused = false;

    when(() => repository.cleanupPartialDownloads()).thenAnswer((_) async {});
    when(() => repository.markInitialSyncSettled()).thenReturn(null);
    when(() => repository.reconnectSilently()).thenAnswer((_) async => true);
    when(() => repository.getLibraries()).thenAnswer((_) async => []);
    when(() => syncController.markOffline()).thenReturn(null);
    when(() => syncController.schedulePush(any())).thenAnswer((i) {
      events.add('push');
    });
    when(() => syncController.isAutoSyncPaused).thenAnswer((_) => paused);
    when(
      () => autoTag.run(
        stopReason: any(named: 'stopReason'),
        firstSoundId: any(named: 'firstSoundId'),
      ),
    ).thenAnswer((invocation) async {
      lastStopReason =
          invocation.namedArguments[#stopReason] as String? Function();
      events.add('autotag');
      return const AutoTagReport();
    });

    coordinator = AutoSyncCoordinator(
      database,
      repository,
      syncController,
      preferences,
      autoTag: autoTag,
      autoTagDelay: const Duration(milliseconds: 30),
    );
  });

  tearDown(() async {
    coordinator.dispose();
    await database.close();
  });

  Future<void> pump() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('une passe de synchro est suivie d\'un passage d\'analyse', () async {
    await coordinator.refreshNow();
    await pump();
    expect(events, ['autotag']);
  });

  test('l\'analyse vient APRÈS le pull', () async {
    final library = _library(1);
    when(() => repository.getLibraries()).thenAnswer((_) async => [library]);
    when(
      () => repository.applyDriveChanges(library: any(named: 'library')),
    ).thenAnswer((_) async {
      events.add('apply');
      return const DriveSyncApplied(upserted: 0, removed: 0);
    });
    when(() => syncController.pullForLaunch(any())).thenAnswer((_) async {
      events.add('pull');
    });

    await coordinator.refreshNow();
    await pump();

    expect(events, ['apply', 'pull', 'autotag']);
  });

  test('mode local : l\'analyse tourne quand même', () async {
    preferences.allows = false;
    await coordinator.refreshNow();
    await pump();
    expect(events, ['autotag']);
  });

  test('Mode Spectacle : aucun passage', () async {
    paused = true;
    await coordinator.refreshNow();
    await pump();
    expect(events, isEmpty);
  });

  test('app en arrière-plan : aucun passage', () async {
    coordinator.onAppBackgrounded();
    await coordinator.refreshNow();
    await pump();
    expect(events, isEmpty);
  });

  test('le retour au premier plan relance l\'analyse', () async {
    coordinator.onAppBackgrounded();
    await coordinator.refreshNow();
    await pump();
    expect(events, isEmpty);

    coordinator.onAppResumed();
    await pump();
    expect(events, contains('autotag'));
  });

  test(
    'la raison d\'arrêt suit l\'état de l\'app pendant le passage',
    () async {
      await coordinator.refreshNow();
      await pump();
      expect(lastStopReason(), isNull);
      paused = true;
      expect(lastStopReason(), 'Mode Spectacle');
      paused = false;
      coordinator.onAppBackgrounded();
      expect(lastStopReason(), 'app en arrière-plan');
    },
  );

  test(
    'un passage long ne retient pas « Actualiser » et ne se double pas',
    () async {
      final gate = Completer<AutoTagReport>();
      when(
        () => autoTag.run(
          stopReason: any(named: 'stopReason'),
          firstSoundId: any(named: 'firstSoundId'),
        ),
      ).thenAnswer((_) {
        events.add('autotag');
        return gate.future;
      });

      // La passe de synchro se termine pendant que l'analyse tourne encore.
      await coordinator.refreshNow();
      await pump();
      await coordinator.refreshNow();
      await pump();

      expect(events, ['autotag'], reason: 'un seul passage à la fois');
      gate.complete(const AutoTagReport());
      await pump();
      await coordinator.refreshNow();
      await pump();
      expect(events, ['autotag', 'autotag']);
    },
  );

  test('tags posés : l\'UI est prévenue et un push est planifié', () async {
    final library = _library(1);
    when(() => repository.getLibraries()).thenAnswer((_) async => [library]);
    when(
      () => repository.applyDriveChanges(library: any(named: 'library')),
    ).thenAnswer((_) async => const DriveSyncApplied(upserted: 0, removed: 0));
    when(() => syncController.pullForLaunch(any())).thenAnswer((_) async {});
    when(
      () => autoTag.run(
        stopReason: any(named: 'stopReason'),
        firstSoundId: any(named: 'firstSoundId'),
      ),
    ).thenAnswer((_) async {
      events.add('autotag');
      return const AutoTagReport(
        analyzed: 60,
        soundsTagged: 12,
        tagsInserted: 20,
      );
    });
    var uiNotified = 0;
    coordinator.onTagsAutoApplied = () => uiNotified++;

    await coordinator.refreshNow();
    await pump();

    expect(uiNotified, 1);
    expect(events, ['autotag', 'push']);
  });

  test('passage sans écriture : ni notification ni push', () async {
    final library = _library(1);
    when(() => repository.getLibraries()).thenAnswer((_) async => [library]);
    when(
      () => repository.applyDriveChanges(library: any(named: 'library')),
    ).thenAnswer((_) async => const DriveSyncApplied(upserted: 0, removed: 0));
    when(() => syncController.pullForLaunch(any())).thenAnswer((_) async {});
    var uiNotified = 0;
    coordinator.onTagsAutoApplied = () => uiNotified++;

    await coordinator.refreshNow();
    await pump();

    expect(uiNotified, 0);
    expect(events, ['autotag']);
  });

  group('demande depuis la fiche d’un son', () {
    test('lance un passage avec le son en tête de file', () async {
      int? first;
      when(
        () => autoTag.run(
          stopReason: any(named: 'stopReason'),
          firstSoundId: any(named: 'firstSoundId'),
        ),
      ).thenAnswer((invocation) async {
        first = invocation.namedArguments[#firstSoundId] as int?;
        return const AutoTagReport();
      });

      expect(coordinator.autoTagAnalysis!.start(42), isNull);
      await pump();

      expect(first, 42);
    });

    test('refus expliqué : Mode Spectacle, passage déjà en cours', () async {
      paused = true;
      expect(coordinator.autoTagAnalysis!.start(1), 'Mode Spectacle');
      paused = false;

      final gate = Completer<AutoTagReport>();
      when(
        () => autoTag.run(
          stopReason: any(named: 'stopReason'),
          firstSoundId: any(named: 'firstSoundId'),
        ),
      ).thenAnswer((_) => gate.future);
      expect(coordinator.autoTagAnalysis!.start(1), isNull);
      expect(
        coordinator.autoTagAnalysis!.start(2),
        'une analyse est déjà en cours',
      );
      gate.complete(const AutoTagReport());
      await pump();
    });

    test('sans service : pas de vue d’analyse', () {
      final plain = AutoSyncCoordinator(
        database,
        repository,
        syncController,
        preferences,
      );
      addTearDown(plain.dispose);
      expect(plain.autoTagAnalysis, isNull);
    });
  });

  test('sans service (tests, mobile) : rien ne change', () async {
    final plain = AutoSyncCoordinator(
      database,
      repository,
      syncController,
      preferences,
    );
    addTearDown(plain.dispose);
    await plain.refreshNow();
    await pump();
    expect(events, isEmpty);
  });

  group('indexation de sons', () {
    Future<void> insertSound(String name) => database
        .into(database.sounds)
        .insert(
          db.SoundsCompanion.insert(
            title: name,
            displayName: name,
            filePath: '/x/$name.mp3',
          ),
        );

    Future<void> afterDelay() =>
        Future<void>.delayed(const Duration(milliseconds: 150));

    test('des sons insérés déclenchent l’analyse après le délai de grâce, '
        'une seule fois pour tout le lot', () async {
      coordinator.start();
      await pump();
      events.clear(); // le lancement a déjà passé son propre passage

      for (var i = 0; i < 20; i++) {
        await insertSound('s$i');
      }
      await pump();
      expect(events, isEmpty, reason: 'pas avant le délai de grâce');
      await afterDelay();

      expect(events.where((e) => e == 'autotag'), hasLength(1));
    });

    test(
      'mode local : l’indexation de sons déclenche aussi l’analyse',
      () async {
        preferences.allows = false;
        coordinator.start();
        await pump();
        events.clear();

        await insertSound('local');
        await afterDelay();

        expect(events, contains('autotag'));
      },
    );

    test('une simple modification de son ne déclenche rien', () async {
      await insertSound('a');
      coordinator.start();
      await pump();
      events.clear();

      await (database.update(
        database.sounds,
      )).write(const db.SoundsCompanion(isFavorite: Value(true)));
      await afterDelay();

      expect(events, isEmpty);
    });
  });
}
