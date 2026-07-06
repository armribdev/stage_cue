import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/sync/audio_cache_manager.dart';
import 'package:stage_cue/core/sync/drive_client.dart';
import 'package:stage_cue/core/sync/drive_models.dart';
import 'package:stage_cue/features/sampler/domain/entities/library.dart';

class MockDriveClient extends Mock implements DriveClient {}

void main() {
  late MockDriveClient client;
  late Directory rootDir;
  late Library library;

  setUpAll(() {
    registerFallbackValue(const Stream<List<int>>.empty());
  });

  setUp(() {
    client = MockDriveClient();
    rootDir = Directory.systemTemp.createTempSync('cache_test');
    library = Library(
      id: 1,
      name: 'Lib',
      localRootPath: rootDir.path,
      driveFolderId: 'folder-root',
      createdAt: DateTime.now(),
    );
  });

  tearDown(() {
    if (rootDir.existsSync()) rootDir.deleteSync(recursive: true);
  });

  DriveFile file(String id, String name) => DriveFile(id: id, name: name);

  /// Stub de téléchargement : écrit [size] octets à la destination demandée.
  void stubDownloadWriting(int size) {
    when(() => client.downloadToFile(
          fileId: any(named: 'fileId'),
          destinationPath: any(named: 'destinationPath'),
        )).thenAnswer((invocation) async {
      final dest =
          invocation.namedArguments[#destinationPath] as String;
      final f = File(dest);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(List.filled(size, 1));
    });
  }

  test('localPathFor convertit les / en séparateur de plateforme', () {
    final manager = AudioCacheManager();
    final result = manager.localPathFor(library, 'sounds/porte.wav');
    expect(result, p.join(rootDir.path, 'sounds', 'porte.wav'));
  });

  test('ensureCached : fichier déjà présent, pas de téléchargement', () async {
    final manager = AudioCacheManager();
    final localPath = manager.localPathFor(library, 'a.wav');
    await File(localPath).parent.create(recursive: true);
    await File(localPath).writeAsBytes([1, 2, 3]);

    final result = await manager.ensureCached(
      client: client,
      library: library,
      relativePath: 'a.wav',
    );

    expect(result, localPath);
    verifyNever(() => client.downloadToFile(
          fileId: any(named: 'fileId'),
          destinationPath: any(named: 'destinationPath'),
        ));
  });

  test('ensureCached normalise le préfixe legacy sounds/', () async {
    final manager = AudioCacheManager();
    when(() => client.findInFolder(
          parentId: 'folder-root',
          name: 'porte.wav',
        )).thenAnswer((_) async => file('remote', 'porte.wav'));
    stubDownloadWriting(50);

    final result = await manager.ensureCached(
      client: client,
      library: library,
      relativePath: 'sounds/porte.wav',
    );

    expect(result, p.join(rootDir.path, 'porte.wav'));
    expect(await File(result).exists(), isTrue);
  });

  test('ensureCached : repli insensible à la casse sur le nom de fichier',
      () async {
    final manager = AudioCacheManager();
    when(() => client.findInFolder(
          parentId: any(named: 'parentId'),
          name: any(named: 'name'),
        )).thenAnswer((invocation) async {
      final parentId = invocation.namedArguments[#parentId] as String;
      final name = invocation.namedArguments[#name] as String;
      if (parentId == 'folder-root' && name == '08 Green Hornet.m4a') {
        return null;
      }
      return null;
    });
    when(() => client.listFolder(
          any(),
          sharedDriveId: any(named: 'sharedDriveId'),
        )).thenAnswer((invocation) async {
      final folderId = invocation.positionalArguments[0] as String;
      if (folderId == 'folder-root') {
        return [file('remote', '08 Green Hornet.M4A')];
      }
      return [];
    });
    stubDownloadWriting(50);

    final result = await manager.ensureCached(
      client: client,
      library: library,
      relativePath: '08 Green Hornet.m4a',
    );

    expect(result, p.join(rootDir.path, '08 Green Hornet.m4a'));
    expect(await File(result).exists(), isTrue);
  });

  test('ensureCached : repli par nom de fichier si chemin dossier incorrect',
      () async {
    final manager = AudioCacheManager();
    when(() => client.findInFolder(
          parentId: any(named: 'parentId'),
          name: any(named: 'name'),
        )).thenAnswer((invocation) async {
      final parentId = invocation.namedArguments[#parentId] as String;
      final name = invocation.namedArguments[#name] as String;
      if (parentId == 'folder-root' && name == 'Ancien dossier') {
        return null;
      }
      if (parentId == 'folder-root' && name == 'porte.wav') {
        return null;
      }
      if (parentId == 'sub-folder' && name == 'porte.wav') {
        return file('remote', 'porte.wav');
      }
      if (parentId == 'folder-root' && name == 'Nouveau dossier') {
        return DriveFile(
          id: 'sub-folder',
          name: 'Nouveau dossier',
          mimeType: driveFolderMimeType,
        );
      }
      return null;
    });
    when(() => client.listFolder(
          any(),
          sharedDriveId: any(named: 'sharedDriveId'),
        )).thenAnswer((invocation) async {
      final folderId = invocation.positionalArguments[0] as String;
      if (folderId == 'folder-root') {
        return [
          DriveFile(
            id: 'sub-folder',
            name: 'Nouveau dossier',
            mimeType: driveFolderMimeType,
          ),
        ];
      }
      if (folderId == 'sub-folder') {
        return [file('remote', 'porte.wav')];
      }
      return [];
    });
    stubDownloadWriting(50);

    final result = await manager.ensureCached(
      client: client,
      library: library,
      relativePath: 'Ancien dossier/porte.wav',
    );

    expect(result, p.join(rootDir.path, 'Nouveau dossier', 'porte.wav'));
    expect(await File(result).exists(), isTrue);
  });

  test('ensureCached : fichier absent, télécharge depuis Drive', () async {
    final manager = AudioCacheManager();
    when(() => client.findInFolder(
          parentId: any(named: 'parentId'),
          name: any(named: 'name'),
        )).thenAnswer((_) async => file('remote', 'a.wav'));
    stubDownloadWriting(50);

    final result = await manager.ensureCached(
      client: client,
      library: library,
      relativePath: 'a.wav',
    );

    expect(await File(result).exists(), isTrue);
    verify(() => client.downloadToFile(
          fileId: 'remote',
          destinationPath: result,
        )).called(1);
  });

  test('importFile : upload Drive + copie dans le cache local', () async {
    final manager = AudioCacheManager();
    // Sous-dossier "sounds" : absent puis créé.
    when(() => client.findInFolder(parentId: 'folder-root', name: 'sounds'))
        .thenAnswer((_) async => null);
    when(() => client.createFolder(name: 'sounds', parentId: 'folder-root'))
        .thenAnswer((_) async => DriveFile(
              id: 'sounds-folder',
              name: 'sounds',
              mimeType: driveFolderMimeType,
            ));
    when(() => client.uploadFile(
          name: any(named: 'name'),
          parentId: any(named: 'parentId'),
          data: any(named: 'data'),
          length: any(named: 'length'),
          mimeType: any(named: 'mimeType'),
        )).thenAnswer((_) async => file('uploaded', 'porte.wav'));

    final source = File(p.join(rootDir.path, 'source.wav'));
    await source.writeAsBytes(List.filled(10, 7));

    final imported = await manager.importFile(
      client: client,
      library: library,
      source: source,
      relativePath: 'sounds/porte.wav',
    );

    expect(imported.driveFileId, 'uploaded');
    expect(imported.relativePath, 'sounds/porte.wav');
    // Le fichier a bien été copié dans le cache local.
    final cached = manager.localPathFor(library, 'sounds/porte.wav');
    expect(await File(cached).exists(), isTrue);
    verify(() => client.uploadFile(
          name: 'porte.wav',
          parentId: 'sounds-folder',
          data: any(named: 'data'),
          length: 10,
          mimeType: 'audio/wav',
        )).called(1);
  });

  test('éviction LRU : le fichier le moins récemment utilisé est supprimé',
      () async {
    var tick = 0;
    final manager = AudioCacheManager(
      maxCacheBytes: 100,
      clock: () => ++tick, // horloge déterministe et croissante
    );
    when(() => client.findInFolder(
          parentId: any(named: 'parentId'),
          name: any(named: 'name'),
        )).thenAnswer((_) async => file('remote', 'x'));
    stubDownloadWriting(80);

    // a.wav (tick 1), puis b.wav (tick 2) -> total 160 > 100 -> évince a.
    await manager.ensureCached(
      client: client,
      library: library,
      relativePath: 'a.wav',
    );
    await manager.ensureCached(
      client: client,
      library: library,
      relativePath: 'b.wav',
    );

    expect(await File(manager.localPathFor(library, 'a.wav')).exists(), isFalse);
    expect(await File(manager.localPathFor(library, 'b.wav')).exists(), isTrue);
  });

  test('éviction LRU : un favori épinglé n\'est jamais évincé', () async {
    var tick = 0;
    final manager = AudioCacheManager(
      maxCacheBytes: 100,
      clock: () => ++tick,
      pinnedPaths: (_) async => {'a.wav'}, // a.wav = favori épinglé
    );
    when(() => client.findInFolder(
          parentId: any(named: 'parentId'),
          name: any(named: 'name'),
        )).thenAnswer((_) async => file('remote', 'x'));
    stubDownloadWriting(80);

    // a (tick1), b (tick2), c (tick3) ; budget 100, 80 chacun.
    await manager.ensureCached(
        client: client, library: library, relativePath: 'a.wav');
    await manager.ensureCached(
        client: client, library: library, relativePath: 'b.wav');
    await manager.ensureCached(
        client: client, library: library, relativePath: 'c.wav');

    // a.wav est le plus ancien mais épinglé -> conservé ; b évincé à sa place.
    expect(await File(manager.localPathFor(library, 'a.wav')).exists(), isTrue);
    expect(await File(manager.localPathFor(library, 'b.wav')).exists(), isFalse);
    expect(await File(manager.localPathFor(library, 'c.wav')).exists(), isTrue);
  });

  test('evictCachedFile : supprime le fichier et libère le budget LRU',
      () async {
    final manager = AudioCacheManager(maxCacheBytes: 100, clock: () => 1);
    when(() => client.findInFolder(
          parentId: any(named: 'parentId'),
          name: any(named: 'name'),
        )).thenAnswer((_) async => file('remote', 'x'));
    stubDownloadWriting(80);

    await manager.ensureCached(
        client: client, library: library, relativePath: 'gone.wav');
    expect(
        await File(manager.localPathFor(library, 'gone.wav')).exists(), isTrue);

    await manager.evictCachedFile(library, 'gone.wav');

    // Fichier supprimé.
    expect(await File(manager.localPathFor(library, 'gone.wav')).exists(),
        isFalse);
    // Budget LRU libéré : un nouveau fichier de 80 octets tient sans évincer.
    stubDownloadWriting(80);
    await manager.ensureCached(
        client: client, library: library, relativePath: 'fresh.wav');
    expect(await File(manager.localPathFor(library, 'fresh.wav')).exists(),
        isTrue);
  });

  test('evictCachedFile : sans fichier ni entrée LRU, ne lève pas', () async {
    final manager = AudioCacheManager();
    await manager.evictCachedFile(library, 'jamais_mis_en_cache.wav');
  });
}
