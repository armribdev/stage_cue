import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/core/sync/audio_cache_manager.dart';
import 'package:stage_cue/core/sync/drive_account_profile.dart';
import 'package:stage_cue/core/sync/drive_client.dart';
import 'package:stage_cue/core/sync/library_sync_service.dart';
import 'package:stage_cue/features/sampler/data/datasources/local_library_datasource.dart';
import 'package:stage_cue/features/sampler/data/datasources/local_sound_datasource.dart';
import 'package:stage_cue/features/sampler/data/repositories/library_repository.dart';

class MockDriveClient extends Mock implements DriveClient {}

class MockLibrarySyncService extends Mock implements LibrarySyncService {}

class _FakeDriveClient extends Fake implements DriveClient {}

class _FakeAuthenticator implements DriveAuthenticator {
  final DriveClient client;
  _FakeAuthenticator(this.client);

  @override
  Future<DriveClient?> connectSilently() async => client;

  @override
  Future<DriveClient?> connect() async => client;

  @override
  Future<void> restoreAccountProfile() async {}

  @override
  Future<void> refreshAccountProfile() async {}

  @override
  Future<void> signOut() async {}

  @override
  String? get accountEmail => 'test@example.com';

  @override
  DriveAccountProfile? get accountProfile => null;
}

/// La date « Synchronisé … » d'une bibliothèque doit avancer à chaque pull
/// concluant, y compris quand il n'y avait rien à fusionner : c'est le cas
/// courant, et la date restait figée sur le dernier push ou la dernière fusion.
void main() {
  late MockLibrarySyncService syncService;
  late db.AppDatabase database;
  late Directory cacheRoot;
  late LibraryRepository repository;
  late int libraryId;

  setUpAll(() {
    registerFallbackValue(_FakeDriveClient());
    registerFallbackValue(<FolderPullTarget>[]);
  });

  setUp(() async {
    syncService = MockLibrarySyncService();
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    cacheRoot = await Directory.systemTemp.createTemp('stagecue_stamp_test');
    libraryId = await database
        .into(database.libraries)
        .insert(
          db.LibrariesCompanion.insert(
            name: 'Lib',
            localRootPath: cacheRoot.path,
            driveFolderId: const Value('root'),
            lastSyncedAt: Value(DateTime(2020)),
          ),
        );
    repository = LibraryRepository(
      LocalLibraryDataSource(database),
      _FakeAuthenticator(MockDriveClient()),
      syncService,
      AudioCacheManager(
        availableDiskBytes: (_) async => 100 * 1024 * 1024 * 1024,
      ),
      LocalSoundDataSource(database),
    );
    expect(await repository.reconnectSilently(), isTrue);
    when(
      () => syncService.pullFolders(
        client: any(named: 'client'),
        folders: any(named: 'folders'),
      ),
    ).thenAnswer((_) async => {});
  });

  tearDown(() async {
    await database.close();
    if (await cacheRoot.exists()) await cacheRoot.delete(recursive: true);
  });

  void stubRootPull(PullOutcome outcome) {
    when(
      () => syncService.pull(
        client: any(named: 'client'),
        libraryId: any(named: 'libraryId'),
        libraryFolderId: any(named: 'libraryFolderId'),
        knownRevision: any(named: 'knownRevision'),
      ),
    ).thenAnswer((_) async => outcome);
  }

  Future<DateTime?> storedSyncedAt() async {
    final library = await LocalLibraryDataSource(
      database,
    ).getLibraryById(libraryId);
    return library?.lastSyncedAt;
  }

  test('pull « à jour » : la date de dernière synchro avance', () async {
    stubRootPull(const PullUpToDate());
    final library = (await repository.getLibraryById(libraryId))!;

    final outcome = await repository.pullLibrary(library);

    expect(outcome, isA<PullUpToDate>());
    expect((await storedSyncedAt())!.year, greaterThan(2020));
  });

  test('aucun snapshot distant : la date n\'est pas touchée', () async {
    // Rien n'a été synchronisé : afficher « à l'instant » mentirait, surtout
    // pour une bibliothèque dont le `.stagecue` a disparu.
    stubRootPull(const PullNoRemoteSnapshot());
    final library = (await repository.getLibraryById(libraryId))!;

    final outcome = await repository.pullLibrary(library);

    expect(outcome, isA<PullNoRemoteSnapshot>());
    expect(await storedSyncedAt(), DateTime(2020));
  });
}
