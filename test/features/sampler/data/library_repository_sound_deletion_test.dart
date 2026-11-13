import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/core/sync/audio_cache_manager.dart';
import 'package:stage_cue/core/sync/drive_account_profile.dart';
import 'package:stage_cue/core/sync/drive_client.dart';
import 'package:stage_cue/core/sync/library_sync_service.dart';
import 'package:stage_cue/core/sync/snapshot_store.dart';
import 'package:stage_cue/features/sampler/data/datasources/local_library_datasource.dart';
import 'package:stage_cue/features/sampler/data/datasources/local_sound_datasource.dart';
import 'package:stage_cue/features/sampler/data/repositories/library_repository.dart';

class MockDriveClient extends Mock implements DriveClient {}

class _FakeAuthenticator implements DriveAuthenticator {
  final DriveClient? client;
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

/// Suppression d'un son de bibliothèque (décision 0035) : la corbeille Drive
/// passe AVANT la base. L'ordre inverse ferait revenir le son à la synchro
/// suivante dès que Drive refuse (hors-ligne, dossier partagé en lecture seule).
void main() {
  late MockDriveClient client;
  late db.AppDatabase database;
  late Directory cacheRoot;
  late LibraryRepository repository;
  late int libraryId;

  setUp(() async {
    client = MockDriveClient();
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    cacheRoot = await Directory.systemTemp.createTemp('stagecue_delete_test');
    libraryId = await database
        .into(database.libraries)
        .insert(
          db.LibrariesCompanion.insert(
            name: 'Lib',
            localRootPath: cacheRoot.path,
            driveFolderId: const Value('root'),
          ),
        );
    repository = LibraryRepository(
      LocalLibraryDataSource(database),
      _FakeAuthenticator(client),
      LibrarySyncService(DriftSnapshotStore(database)),
      AudioCacheManager(
        availableDiskBytes: (_) async => 100 * 1024 * 1024 * 1024,
      ),
      LocalSoundDataSource(database),
    );
    expect(await repository.reconnectSilently(), isTrue);
  });

  tearDown(() async {
    await database.close();
    if (await cacheRoot.exists()) await cacheRoot.delete(recursive: true);
  });

  Future<int> insertSound({String? driveFileId, String? relativePath}) {
    return database
        .into(database.sounds)
        .insert(
          db.SoundsCompanion.insert(
            title: 'boom',
            displayName: 'boom',
            filePath: p.join(cacheRoot.path, relativePath ?? 'boom.mp3'),
            libraryId: Value(libraryId),
            relativePath: Value(relativePath),
            driveFileId: Value(driveFileId),
          ),
        );
  }

  Future<int> insertPadWith(int soundId) async {
    final boardId = await database
        .into(database.soundBoards)
        .insert(db.SoundBoardsCompanion.insert(name: 'Scène'));
    final padId = await database
        .into(database.pads)
        .insert(db.PadsCompanion.insert(boardId: boardId));
    await database
        .into(database.padSounds)
        .insert(db.PadSoundsCompanion.insert(padId: padId, soundId: soundId));
    return padId;
  }

  Future<int> soundCount() async =>
      (await database.select(database.sounds).get()).length;

  test(
    'met le fichier à la corbeille, puis retire ligne, pads et cache',
    () async {
      final soundId = await insertSound(
        driveFileId: 'drive-1',
        relativePath: 'boom.mp3',
      );
      await insertPadWith(soundId);
      final cached = File(p.join(cacheRoot.path, 'boom.mp3'));
      await cached.writeAsBytes(List.filled(16, 1));
      when(() => client.trashFile('drive-1')).thenAnswer((_) async {});

      await repository.deleteLibrarySound(soundId);

      verify(() => client.trashFile('drive-1')).called(1);
      verifyNever(() => client.deleteFile(any()));
      expect(await soundCount(), 0);
      // Cascade émulée par déclencheur (décision 0032) : plus de pad_sounds.
      expect(await database.select(database.padSounds).get(), isEmpty);
      expect(cached.existsSync(), isFalse);
    },
  );

  test('échec Drive : rien n\'est touché en local', () async {
    final soundId = await insertSound(
      driveFileId: 'drive-1',
      relativePath: 'boom.mp3',
    );
    await insertPadWith(soundId);
    final cached = File(p.join(cacheRoot.path, 'boom.mp3'));
    await cached.writeAsBytes(List.filled(16, 1));
    when(
      () => client.trashFile('drive-1'),
    ).thenThrow(const DriveRequestException.denied());

    await expectLater(
      repository.deleteLibrarySound(soundId),
      throwsA(isA<DriveRequestException>()),
    );

    // Sinon le son reviendrait à la synchro suivante, qui ré-indexe Drive.
    expect(await soundCount(), 1);
    expect(await database.select(database.padSounds).get(), hasLength(1));
    expect(cached.existsSync(), isTrue);
  });

  test('son sans identité Drive : refusé, Drive jamais appelé', () async {
    final soundId = await insertSound(relativePath: 'local.mp3');

    await expectLater(
      repository.deleteLibrarySound(soundId),
      throwsA(isA<ArgumentError>()),
    );

    verifyNever(() => client.trashFile(any()));
    expect(await soundCount(), 1);
  });

  test('son déjà supprimé : sans effet, Drive jamais appelé', () async {
    await repository.deleteLibrarySound(999);

    verifyNever(() => client.trashFile(any()));
  });

  test(
    'countPadsUsingSound compte les pads distincts, toutes scènes',
    () async {
      final soundId = await insertSound(driveFileId: 'drive-1');
      final otherId = await insertSound(driveFileId: 'drive-2');
      await insertPadWith(soundId);
      await insertPadWith(soundId);
      await insertPadWith(otherId);
      final pads = LocalPadDataSource(database);

      expect(await pads.countPadsUsingSound(soundId), 2);
      expect(await pads.countPadsUsingSound(otherId), 1);
      expect(await pads.countPadsUsingSound(12345), 0);
    },
  );
}
