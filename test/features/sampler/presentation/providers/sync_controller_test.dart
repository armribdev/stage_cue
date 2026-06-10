import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stage_cue/core/sync/library_sync_service.dart';
import 'package:stage_cue/core/sync/sync_manifest.dart';
import 'package:stage_cue/features/sampler/data/repositories/library_repository.dart';
import 'package:stage_cue/features/sampler/domain/entities/library.dart';
import 'package:stage_cue/features/sampler/presentation/providers/sync_controller.dart';

class MockLibraryRepository extends Mock implements LibraryRepository {}

Library _library() => Library(
      id: 1,
      name: 'Lib',
      localRootPath: '/tmp/lib',
      driveFolderId: 'folder',
      lastSyncedRevision: 2,
      createdAt: DateTime(2026),
    );

SyncManifest _remote(int revision) => SyncManifest(
      revision: revision,
      deviceId: 'other',
      updatedAt: DateTime(2026),
      schemaVersion: 11,
    );

void main() {
  late MockLibraryRepository repo;
  late Library library;

  setUpAll(() {
    registerFallbackValue(_library());
  });

  setUp(() {
    repo = MockLibraryRepository();
    library = _library();
    when(() => repo.isConnected).thenReturn(true);
  });

  group('syncNow', () {
    test('push réussi -> synced + horodatage', () async {
      when(() => repo.pushLibrary(any(),
              overrideKnownRevision: any(named: 'overrideKnownRevision')))
          .thenAnswer((_) async => const PushSuccess(3));
      final controller = SyncController(repo);

      await controller.syncNow(library);

      expect(controller.state.status, SyncStatus.synced);
      expect(controller.state.lastSyncedAt, isNotNull);
    });

    test('push en conflit -> conflict + révision distante mémorisée', () async {
      when(() => repo.pushLibrary(any(),
              overrideKnownRevision: any(named: 'overrideKnownRevision')))
          .thenAnswer((_) async => PushConflict(_remote(5)));
      final controller = SyncController(repo);

      await controller.syncNow(library);

      expect(controller.state.status, SyncStatus.conflict);
      expect(controller.state.conflictRemoteRevision, 5);
    });

    test('non connecté et reconnexion impossible -> offline', () async {
      when(() => repo.isConnected).thenReturn(false);
      when(() => repo.reconnectSilently()).thenAnswer((_) async => false);
      final controller = SyncController(repo);

      await controller.syncNow(library);

      expect(controller.state.status, SyncStatus.offline);
      verifyNever(() => repo.pushLibrary(any()));
    });
  });

  group('résolution de conflit', () {
    test('keepLocal force le push avec la révision distante', () async {
      when(() => repo.pushLibrary(any(),
              overrideKnownRevision: any(named: 'overrideKnownRevision')))
          .thenAnswer((invocation) async {
        final override =
            invocation.namedArguments[#overrideKnownRevision] as int?;
        // 1er appel (syncNow) : conflit. 2e appel (keepLocal) : override fourni.
        return override == 5 ? const PushSuccess(6) : PushConflict(_remote(5));
      });
      final controller = SyncController(repo);
      await controller.syncNow(library);
      expect(controller.state.status, SyncStatus.conflict);

      await controller.keepLocal(library);

      expect(controller.state.status, SyncStatus.synced);
      expect(controller.state.conflictRemoteRevision, isNull);
      verify(() => repo.pushLibrary(any(), overrideKnownRevision: 5)).called(1);
    });

    test('takeRemote tire le distant et fusionne immédiatement', () async {
      when(() => repo.pullLibrary(any()))
          .thenAnswer((_) async => const PullStaged(5));
      final controller = SyncController(repo);

      await controller.takeRemote(library);

      expect(controller.state.status, SyncStatus.synced);
    });
  });

  group('pullForLaunch', () {
    test('snapshot plus récent -> synced', () async {
      when(() => repo.pullLibrary(any()))
          .thenAnswer((_) async => const PullStaged(7));
      final controller = SyncController(repo);

      await controller.pullForLaunch(library);

      expect(controller.state.status, SyncStatus.synced);
    });

    test('déjà à jour -> synced', () async {
      when(() => repo.pullLibrary(any()))
          .thenAnswer((_) async => const PullUpToDate());
      final controller = SyncController(repo);

      await controller.pullForLaunch(library);

      expect(controller.state.status, SyncStatus.synced);
    });

    test('PullStaged déclenche onLibraryMerged', () async {
      when(() => repo.pullLibrary(any()))
          .thenAnswer((_) async => const PullStaged(7));
      final controller = SyncController(repo);
      var mergedCalled = false;
      controller.onLibraryMerged = () => mergedCalled = true;

      await controller.pullForLaunch(library);

      expect(mergedCalled, isTrue);
    });

    test('PullUpToDate ne déclenche pas onLibraryMerged', () async {
      when(() => repo.pullLibrary(any()))
          .thenAnswer((_) async => const PullUpToDate());
      final controller = SyncController(repo);
      var mergedCalled = false;
      controller.onLibraryMerged = () => mergedCalled = true;

      await controller.pullForLaunch(library);

      expect(mergedCalled, isFalse);
    });
  });

  group('markOffline', () {
    test('passe à offline pour la pastille ambiante', () {
      final controller = SyncController(repo);

      controller.markOffline();

      expect(controller.state.status, SyncStatus.offline);
    });

    test('idempotent : pas de notification redondante', () {
      final controller = SyncController(repo);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.markOffline();
      controller.markOffline();

      expect(notifications, 1);
    });
  });

  group('Mode Spectacle (pause auto-sync)', () {
    test('schedulePush en pause -> aucun push, rejoué à la reprise', () async {
      when(() => repo.pushLibrary(any(),
              overrideKnownRevision: any(named: 'overrideKnownRevision')))
          .thenAnswer((_) async => const PushSuccess(3));
      final controller =
          SyncController(repo, debounce: const Duration(milliseconds: 20));

      controller.pauseAutoSync();
      controller.schedulePush(library);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      verifyNever(() => repo.pushLibrary(any()));

      controller.resumeAutoSync();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      verify(() => repo.pushLibrary(any())).called(1);
    });

    test('un push débouncé en attente est différé puis rejoué à la reprise',
        () async {
      when(() => repo.pushLibrary(any(),
              overrideKnownRevision: any(named: 'overrideKnownRevision')))
          .thenAnswer((_) async => const PushSuccess(3));
      final controller =
          SyncController(repo, debounce: const Duration(milliseconds: 30));

      controller.schedulePush(library); // timer armé
      controller.pauseAutoSync(); // entre en spectacle : annule mais diffère
      await Future<void>.delayed(const Duration(milliseconds: 60));
      verifyNever(() => repo.pushLibrary(any())); // rien pendant le show

      controller.resumeAutoSync();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      verify(() => repo.pushLibrary(any())).called(1);
    });
  });

  group('schedulePush (anti-rebond)', () {
    test('plusieurs appels rapprochés -> un seul push', () async {
      when(() => repo.pushLibrary(any(),
              overrideKnownRevision: any(named: 'overrideKnownRevision')))
          .thenAnswer((_) async => const PushSuccess(3));
      final controller =
          SyncController(repo, debounce: const Duration(milliseconds: 20));

      controller.schedulePush(library);
      controller.schedulePush(library);
      controller.schedulePush(library);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      verify(() => repo.pushLibrary(any())).called(1);
    });

    test('syncNow supersède un push débouncé en attente', () async {
      when(() => repo.pushLibrary(any(),
              overrideKnownRevision: any(named: 'overrideKnownRevision')))
          .thenAnswer((_) async => const PushSuccess(3));
      final controller =
          SyncController(repo, debounce: const Duration(milliseconds: 50));

      controller.schedulePush(library);
      await controller.syncNow(library); // push immédiat
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // Seul le push immédiat a eu lieu ; le push débouncé a été annulé.
      verify(() => repo.pushLibrary(any())).called(1);
    });
  });
}
