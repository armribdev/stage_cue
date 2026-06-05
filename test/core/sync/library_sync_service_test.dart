import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stage_cue/core/sync/drive_client.dart';
import 'package:stage_cue/core/sync/drive_models.dart';
import 'package:stage_cue/core/sync/library_sync_service.dart';
import 'package:stage_cue/core/sync/snapshot_store.dart';
import 'package:stage_cue/core/sync/sync_manifest.dart';

class MockDriveClient extends Mock implements DriveClient {}

class MockSnapshotStore extends Mock implements SnapshotStore {}

void main() {
  late MockDriveClient client;
  late MockSnapshotStore store;
  late LibrarySyncService service;
  late Directory tempDir;

  setUpAll(() {
    registerFallbackValue(const Stream<List<int>>.empty());
  });

  setUp(() {
    client = MockDriveClient();
    store = MockSnapshotStore();
    tempDir = Directory.systemTemp.createTempSync('sync_test');
    service = LibrarySyncService(store, deviceId: 'device-1', tempDir: tempDir);

    when(() => store.schemaVersion).thenReturn(11);
    when(() => store.exportSnapshot(any())).thenAnswer((_) async => 1024);
    when(() => store.stageForImport(any())).thenAnswer((_) async {});
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  DriveFile folder(String id, String name) =>
      DriveFile(id: id, name: name, mimeType: driveFolderMimeType);
  DriveFile file(String id, String name) => DriveFile(id: id, name: name);

  void stubUpload() {
    when(() => client.uploadFile(
          name: any(named: 'name'),
          parentId: any(named: 'parentId'),
          data: any(named: 'data'),
          length: any(named: 'length'),
          mimeType: any(named: 'mimeType'),
        )).thenAnswer((_) async => file('new', 'new'));
    when(() => client.updateFileContent(
          fileId: any(named: 'fileId'),
          data: any(named: 'data'),
          length: any(named: 'length'),
          mimeType: any(named: 'mimeType'),
        )).thenAnswer((_) async => file('upd', 'upd'));
  }

  group('push', () {
    test('sans manifest distant : exporte, upload db + manifest, révision 1',
        () async {
      when(() => client.findInFolder(parentId: 'lib', name: '.stagecue'))
          .thenAnswer((_) async => folder('stage', '.stagecue'));
      when(() => client.findInFolder(parentId: 'stage', name: 'manifest.json'))
          .thenAnswer((_) async => null);
      when(() => client.findInFolder(parentId: 'stage', name: 'library.db'))
          .thenAnswer((_) async => null);
      stubUpload();

      final outcome = await service.push(
        client: client,
        libraryFolderId: 'lib',
        knownRevision: 0,
      );

      expect(outcome, isA<PushSuccess>());
      expect((outcome as PushSuccess).revision, 1);
      verify(() => store.exportSnapshot(any())).called(1);
      verify(() => client.uploadFile(
            name: 'library.db',
            parentId: 'stage',
            data: any(named: 'data'),
            length: 1024,
            mimeType: any(named: 'mimeType'),
          )).called(1);
      verify(() => client.uploadFile(
            name: 'manifest.json',
            parentId: 'stage',
            data: any(named: 'data'),
            length: any(named: 'length'),
            mimeType: any(named: 'mimeType'),
          )).called(1);
    });

    test('révision distante == connue : met à jour et incrémente', () async {
      final remote = SyncManifest(
        revision: 3,
        deviceId: 'other',
        updatedAt: DateTime.now().toUtc(),
        schemaVersion: 11,
      );
      when(() => client.findInFolder(parentId: 'lib', name: '.stagecue'))
          .thenAnswer((_) async => folder('stage', '.stagecue'));
      when(() => client.findInFolder(parentId: 'stage', name: 'manifest.json'))
          .thenAnswer((_) async => file('m', 'manifest.json'));
      when(() => client.downloadBytes('m'))
          .thenAnswer((_) async => utf8.encode(remote.encode()));
      when(() => client.findInFolder(parentId: 'stage', name: 'library.db'))
          .thenAnswer((_) async => file('db', 'library.db'));
      stubUpload();

      final outcome = await service.push(
        client: client,
        libraryFolderId: 'lib',
        knownRevision: 3,
      );

      expect(outcome, isA<PushSuccess>());
      expect((outcome as PushSuccess).revision, 4);
      // db existant -> updateFileContent, pas un upload neuf
      verify(() => client.updateFileContent(
            fileId: 'db',
            data: any(named: 'data'),
            length: 1024,
            mimeType: any(named: 'mimeType'),
          )).called(1);
    });

    test('révision distante différente : conflit, pas d\'export', () async {
      final remote = SyncManifest(
        revision: 5,
        deviceId: 'other',
        updatedAt: DateTime.now().toUtc(),
        schemaVersion: 11,
      );
      when(() => client.findInFolder(parentId: 'lib', name: '.stagecue'))
          .thenAnswer((_) async => folder('stage', '.stagecue'));
      when(() => client.findInFolder(parentId: 'stage', name: 'manifest.json'))
          .thenAnswer((_) async => file('m', 'manifest.json'));
      when(() => client.downloadBytes('m'))
          .thenAnswer((_) async => utf8.encode(remote.encode()));

      final outcome = await service.push(
        client: client,
        libraryFolderId: 'lib',
        knownRevision: 2,
      );

      expect(outcome, isA<PushConflict>());
      expect((outcome as PushConflict).remote.revision, 5);
      verifyNever(() => store.exportSnapshot(any()));
    });
  });

  group('pull', () {
    test('pas de dossier .stagecue : à jour', () async {
      when(() => client.findInFolder(parentId: 'lib', name: '.stagecue'))
          .thenAnswer((_) async => null);

      final outcome = await service.pull(
        client: client,
        libraryFolderId: 'lib',
        knownRevision: 0,
      );

      expect(outcome, isA<PullUpToDate>());
      verifyNever(() => store.stageForImport(any()));
    });

    test('révision distante <= connue : à jour', () async {
      final remote = SyncManifest(
        revision: 2,
        deviceId: 'other',
        updatedAt: DateTime.now().toUtc(),
        schemaVersion: 11,
      );
      when(() => client.findInFolder(parentId: 'lib', name: '.stagecue'))
          .thenAnswer((_) async => folder('stage', '.stagecue'));
      when(() => client.findInFolder(parentId: 'stage', name: 'manifest.json'))
          .thenAnswer((_) async => file('m', 'manifest.json'));
      when(() => client.downloadBytes('m'))
          .thenAnswer((_) async => utf8.encode(remote.encode()));

      final outcome = await service.pull(
        client: client,
        libraryFolderId: 'lib',
        knownRevision: 2,
      );

      expect(outcome, isA<PullUpToDate>());
      verifyNever(() => store.stageForImport(any()));
    });

    test('révision distante plus récente : télécharge et met en attente',
        () async {
      final remote = SyncManifest(
        revision: 7,
        deviceId: 'other',
        updatedAt: DateTime.now().toUtc(),
        schemaVersion: 11,
      );
      when(() => client.findInFolder(parentId: 'lib', name: '.stagecue'))
          .thenAnswer((_) async => folder('stage', '.stagecue'));
      when(() => client.findInFolder(parentId: 'stage', name: 'manifest.json'))
          .thenAnswer((_) async => file('m', 'manifest.json'));
      when(() => client.downloadBytes('m'))
          .thenAnswer((_) async => utf8.encode(remote.encode()));
      when(() => client.findInFolder(parentId: 'stage', name: 'library.db'))
          .thenAnswer((_) async => file('db', 'library.db'));
      when(() => client.downloadToFile(
            fileId: any(named: 'fileId'),
            destinationPath: any(named: 'destinationPath'),
          )).thenAnswer((_) async {});

      final outcome = await service.pull(
        client: client,
        libraryFolderId: 'lib',
        knownRevision: 2,
      );

      expect(outcome, isA<PullStaged>());
      expect((outcome as PullStaged).revision, 7);
      verify(() => store.stageForImport(any())).called(1);
    });
  });
}
