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

    // Défaut : tout fichier non explicitement stubé est absent. Les snapshots
    // portent désormais un nom unique (uuid) qu'un test ne peut pas prédire ;
    // les stubs spécifiques des tests, enregistrés après, restent prioritaires.
    when(() => client.findInFolder(
          parentId: any(named: 'parentId'),
          name: any(named: 'name'),
        )).thenAnswer((_) async => null);
    // Même défaut pour la sonde groupée : rien trouvé nulle part.
    when(() => client.findInFolders(
          parentIds: any(named: 'parentIds'),
          name: any(named: 'name'),
        )).thenAnswer((_) async => const <String, DriveFile>{});
    when(() => client.deleteFile(any())).thenAnswer((_) async {});

    when(() => store.schemaVersion).thenReturn(11);
    when(() => store.exportLibrarySnapshot(any(), any()))
        .thenAnswer((_) async => 1024);
    when(
      () => store.mergeLibrarySnapshot(
        any(),
        any(),
        driveFolderId: any(named: 'driveFolderId'),
      ),
    ).thenAnswer((_) async {});
    when(() => store.exportFolderSnapshot(any(), any()))
        .thenAnswer((_) async => 2048);
    when(() => store.mergeFolderSnapshot(any(), any()))
        .thenAnswer((_) async {});
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
      when(() => client.findInFolder(
              parentId: 'stage', name: 'boards-manifest.json'))
          .thenAnswer((_) async => null);
      when(() => client.findInFolder(parentId: 'stage', name: 'boards.db'))
          .thenAnswer((_) async => null);
      stubUpload();

      final outcome = await service.push(
        client: client,
        libraryId: 1,
        libraryFolderId: 'lib',
        knownRevision: 0,
      );

      expect(outcome, isA<PushSuccess>());
      expect((outcome as PushSuccess).revision, 1);
      verify(() => store.exportLibrarySnapshot(1, any())).called(1);
      // Snapshot RACINE : boards.db, distinct de library.db (snapshot dossier).
      verify(() => client.uploadFile(
            // Nom unique par push (`boards-<uuid>.db`) : plus jamais écrasable.
            name: any(named: 'name', that: startsWith('boards-')),
            parentId: 'stage',
            data: any(named: 'data'),
            length: 1024,
            mimeType: any(named: 'mimeType'),
          )).called(1);
      verify(() => client.uploadFile(
            name: 'boards-manifest.json',
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
      when(() => client.findInFolder(
              parentId: 'stage', name: 'boards-manifest.json'))
          .thenAnswer((_) async => file('m', 'boards-manifest.json'));
      when(() => client.downloadBytes('m'))
          .thenAnswer((_) async => utf8.encode(remote.encode()));
      when(() => client.findInFolder(parentId: 'stage', name: 'boards.db'))
          .thenAnswer((_) async => file('db', 'boards.db'));
      stubUpload();

      final outcome = await service.push(
        client: client,
        libraryId: 1,
        libraryFolderId: 'lib',
        knownRevision: 3,
      );

      expect(outcome, isA<PushSuccess>());
      expect((outcome as PushSuccess).revision, 4);
      // Le snapshot n'est PLUS jamais écrasé : chaque push crée son propre blob
      // et seul le manifest est mis à jour en place.
      verify(() => client.uploadFile(
            name: any(named: 'name', that: startsWith('boards-')),
            parentId: 'stage',
            data: any(named: 'data'),
            length: 1024,
            mimeType: any(named: 'mimeType'),
          )).called(1);
      verifyNever(() => client.updateFileContent(
            fileId: 'db',
            data: any(named: 'data'),
            length: any(named: 'length'),
            mimeType: any(named: 'mimeType'),
          ));
    });

    test('budget de requêtes : un push nominal ne cherche le manifest QU\'UNE '
        'fois de trop', () async {
      final remote = SyncManifest(
        revision: 3,
        deviceId: 'other',
        updatedAt: DateTime.now().toUtc(),
        schemaVersion: 11,
      );
      when(() => client.findInFolder(parentId: 'lib', name: '.stagecue'))
          .thenAnswer((_) async => folder('stage', '.stagecue'));
      when(() => client.findInFolder(
              parentId: 'stage', name: 'boards-manifest.json'))
          .thenAnswer((_) async => file('m', 'boards-manifest.json'));
      when(() => client.downloadBytes('m'))
          .thenAnswer((_) async => utf8.encode(remote.encode()));
      stubUpload();

      await service.push(
        client: client,
        libraryId: 1,
        libraryFolderId: 'lib',
        knownRevision: 3,
      );

      // DEUX recherches de manifest, pas trois : la lecture initiale et la
      // relecture d'avant publication. L'écriture qui suit réutilise l'id que
      // la relecture vient de rendre, au lieu de rechercher un fichier qu'elle
      // vient de voir.
      verify(() => client.findInFolder(
            parentId: 'stage',
            name: 'boards-manifest.json',
          )).called(2);
      // Le manifest est mis à jour EN PLACE, par son id.
      verify(() => client.updateFileContent(
            fileId: 'm',
            data: any(named: 'data'),
            length: any(named: 'length'),
            mimeType: any(named: 'mimeType'),
          )).called(1);
      // Aucune recherche de blob : ni avant l'upload (nom neuf), et pas de
      // nettoyage ici puisque le manifest précédent ne désignait aucun blob.
      verifyNever(() => client.findInFolder(
            parentId: 'stage',
            name: any(
              named: 'name',
              that: allOf(startsWith('boards-'), endsWith('.db')),
            ),
          ));
    });

    test('publication concurrente pendant l\'upload : conflit détecté, '
        'snapshot du gagnant intact', () async {
      when(() => client.findInFolder(parentId: 'lib', name: '.stagecue'))
          .thenAnswer((_) async => folder('stage', '.stagecue'));
      when(() => client.findInFolder(
              parentId: 'stage', name: 'boards-manifest.json'))
          .thenAnswer((_) async => file('m', 'boards-manifest.json'));

      SyncManifest at(int revision) => SyncManifest(
            revision: revision,
            deviceId: 'other',
            updatedAt: DateTime(2026),
            schemaVersion: 11,
          );

      // 1re lecture : révision 3, la garde passe. 2e lecture (juste avant
      // publication) : un autre appareil a publié la 4 pendant notre upload.
      var reads = 0;
      when(() => client.downloadBytes('m')).thenAnswer((_) async {
        reads++;
        return utf8.encode(at(reads == 1 ? 3 : 4).encode());
      });
      stubUpload();

      // Un SEUL lookup de blob dans toute la séquence : celui du nettoyage de
      // notre orphelin, une fois le conflit détecté. L'upload, lui, crée
      // directement — son nom porte un UUID neuf, chercher un homonyme ne
      // pouvait rien donner.
      var blobLookups = 0;
      when(() => client.findInFolder(
            parentId: 'stage',
            name: any(
              named: 'name',
              that: allOf(startsWith('boards-'), endsWith('.db')),
            ),
          )).thenAnswer((invocation) async {
        blobLookups++;
        return file('orphan', invocation.namedArguments[#name] as String);
      });

      final outcome = await service.push(
        client: client,
        libraryId: 1,
        libraryFolderId: 'lib',
        knownRevision: 3,
      );

      expect(outcome, isA<PushConflict>());
      expect((outcome as PushConflict).remote.revision, 4);
      // Le manifest n'est PAS republié : la révision 4 du gagnant reste en place
      // et son snapshot n'a jamais pu être écrasé (nom distinct du nôtre).
      verifyNever(() => client.updateFileContent(
            fileId: 'm',
            data: any(named: 'data'),
            length: any(named: 'length'),
            mimeType: any(named: 'mimeType'),
          ));
      // Notre snapshot, que plus rien ne référence, est nettoyé.
      verify(() => client.deleteFile('orphan')).called(1);
      // Et ce nettoyage est le SEUL lookup de blob : réintroduire une recherche
      // avant l'upload rendrait un aller-retour Drive garanti stérile à chaque
      // sauvegarde.
      expect(blobLookups, 1);
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
      when(() => client.findInFolder(
              parentId: 'stage', name: 'boards-manifest.json'))
          .thenAnswer((_) async => file('m', 'boards-manifest.json'));
      when(() => client.downloadBytes('m'))
          .thenAnswer((_) async => utf8.encode(remote.encode()));

      final outcome = await service.push(
        client: client,
        libraryId: 1,
        libraryFolderId: 'lib',
        knownRevision: 2,
      );

      expect(outcome, isA<PushConflict>());
      expect((outcome as PushConflict).remote.revision, 5);
      verifyNever(() => store.exportLibrarySnapshot(any(), any()));
    });

    test('deux push concurrents téléversent chacun LEUR snapshot', () async {
      when(() => client.findInFolder(parentId: 'lib', name: '.stagecue'))
          .thenAnswer((_) async => folder('stage', '.stagecue'));
      when(() => client.findInFolder(
              parentId: 'stage', name: 'boards-manifest.json'))
          .thenAnswer((_) async => null);
      when(() => client.findInFolder(parentId: 'stage', name: 'boards.db'))
          .thenAnswer((_) async => null);

      // L'export écrit un contenu propre à la bibliothèque ; la pause force
      // l'entrelacement des deux push (cas réel : le coordinateur planifie un
      // push par bibliothèque connectée, les anti-rebonds échoient ensemble).
      when(() => store.exportLibrarySnapshot(any(), any()))
          .thenAnswer((invocation) async {
        final libraryId = invocation.positionalArguments[0] as int;
        final path = invocation.positionalArguments[1] as String;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final content = 'snapshot-$libraryId';
        await File(path).writeAsString(content);
        return content.length;
      });

      // Capture le contenu RÉELLEMENT téléversé pour chaque boards.db.
      final uploaded = <String>[];
      when(() => client.uploadFile(
            name: any(named: 'name'),
            parentId: any(named: 'parentId'),
            data: any(named: 'data'),
            length: any(named: 'length'),
            mimeType: any(named: 'mimeType'),
          )).thenAnswer((invocation) async {
        final name = invocation.namedArguments[#name] as String;
        if (name.startsWith('boards-') && name.endsWith('.db')) {
          final data = invocation.namedArguments[#data] as Stream<List<int>>;
          uploaded.add(utf8.decode(await data.expand((c) => c).toList()));
        }
        return file('new', 'new');
      });

      await Future.wait([
        service.push(
          client: client,
          libraryId: 1,
          libraryFolderId: 'lib',
          knownRevision: 0,
        ),
        service.push(
          client: client,
          libraryId: 2,
          libraryFolderId: 'lib',
          knownRevision: 0,
        ),
      ]);

      // Avec un nom de fichier temporaire fixe, le second export écrasait le
      // premier : les deux push téléversaient le même contenu (ou échouaient
      // sur un fichier supprimé par le `finally` de l'autre).
      expect(uploaded, unorderedEquals(['snapshot-1', 'snapshot-2']));
    });
  });

  group('pull', () {
    test('pas de dossier .stagecue : AUCUN snapshot distant, pas « à jour »',
        () async {
      when(() => client.findInFolder(parentId: 'lib', name: '.stagecue'))
          .thenAnswer((_) async => null);

      final outcome = await service.pull(
        client: client,
        libraryId: 1,
        libraryFolderId: 'lib',
        knownRevision: 0,
      );

      // Rien n'a pu être comparé : confondre ce cas avec PullUpToDate faisait
      // afficher « Synchronisé » sur un dossier distant vide.
      expect(outcome, isA<PullNoRemoteSnapshot>());
      verifyNever(
        () => store.mergeLibrarySnapshot(any(), any(), driveFolderId: any(named: 'driveFolderId')),
      );
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
      when(() => client.findInFolder(
              parentId: 'stage', name: 'boards-manifest.json'))
          .thenAnswer((_) async => file('m', 'boards-manifest.json'));
      when(() => client.downloadBytes('m'))
          .thenAnswer((_) async => utf8.encode(remote.encode()));

      final outcome = await service.pull(
        client: client,
        libraryId: 1,
        libraryFolderId: 'lib',
        knownRevision: 2,
      );

      expect(outcome, isA<PullUpToDate>());
      verifyNever(
        () => store.mergeLibrarySnapshot(any(), any(), driveFolderId: any(named: 'driveFolderId')),
      );
    });

    test('révision distante plus récente : télécharge et fusionne',
        () async {
      final remote = SyncManifest(
        revision: 7,
        deviceId: 'other',
        updatedAt: DateTime.now().toUtc(),
        schemaVersion: 11,
      );
      when(() => client.findInFolder(parentId: 'lib', name: '.stagecue'))
          .thenAnswer((_) async => folder('stage', '.stagecue'));
      when(() => client.findInFolder(
              parentId: 'stage', name: 'boards-manifest.json'))
          .thenAnswer((_) async => file('m', 'boards-manifest.json'));
      when(() => client.downloadBytes('m'))
          .thenAnswer((_) async => utf8.encode(remote.encode()));
      when(() => client.findInFolder(parentId: 'stage', name: 'boards.db'))
          .thenAnswer((_) async => file('db', 'boards.db'));
      when(() => client.downloadToFile(
            fileId: any(named: 'fileId'),
            destinationPath: any(named: 'destinationPath'),
          )).thenAnswer((_) async {});

      final outcome = await service.pull(
        client: client,
        libraryId: 1,
        libraryFolderId: 'lib',
        knownRevision: 2,
      );

      expect(outcome, isA<PullStaged>());
      expect((outcome as PullStaged).revision, 7);
      verify(
        () => store.mergeLibrarySnapshot(
          1,
          any(),
          driveFolderId: 'lib',
        ),
      ).called(1);
    });

    test('le manifest désigne son snapshot : c\'est CE blob qui est tiré',
        () async {
      final remote = SyncManifest(
        revision: 7,
        deviceId: 'other',
        updatedAt: DateTime.now().toUtc(),
        schemaVersion: 11,
        dbFileName: 'boards-abc.db',
      );
      when(() => client.findInFolder(parentId: 'lib', name: '.stagecue'))
          .thenAnswer((_) async => folder('stage', '.stagecue'));
      when(() => client.findInFolder(
              parentId: 'stage', name: 'boards-manifest.json'))
          .thenAnswer((_) async => file('m', 'boards-manifest.json'));
      when(() => client.downloadBytes('m'))
          .thenAnswer((_) async => utf8.encode(remote.encode()));
      when(() => client.findInFolder(parentId: 'stage', name: 'boards-abc.db'))
          .thenAnswer((_) async => file('blob-7', 'boards-abc.db'));
      // Le nom historique traîne encore (dossier poussé par une version
      // antérieure) : il ne doit PAS être tiré à la place du blob désigné.
      when(() => client.findInFolder(parentId: 'stage', name: 'boards.db'))
          .thenAnswer((_) async => file('legacy', 'boards.db'));
      when(() => client.downloadToFile(
            fileId: any(named: 'fileId'),
            destinationPath: any(named: 'destinationPath'),
          )).thenAnswer((_) async {});

      final outcome = await service.pull(
        client: client,
        libraryId: 1,
        libraryFolderId: 'lib',
        knownRevision: 2,
      );

      expect(outcome, isA<PullStaged>());
      verify(() => client.downloadToFile(
            fileId: 'blob-7',
            destinationPath: any(named: 'destinationPath'),
          )).called(1);
      verifyNever(() => client.downloadToFile(
            fileId: 'legacy',
            destinationPath: any(named: 'destinationPath'),
          ));
    });
  });

  group('pushFolder / pullFolder (par-dossier)', () {
    test('pushFolder sans manifest : exporte le dossier, révision 1', () async {
      when(() => client.findInFolder(parentId: 'yy', name: '.stagecue'))
          .thenAnswer((_) async => folder('stage', '.stagecue'));
      when(() => client.findInFolder(parentId: 'stage', name: 'manifest.json'))
          .thenAnswer((_) async => null);
      when(() => client.findInFolder(parentId: 'stage', name: 'library.db'))
          .thenAnswer((_) async => null);
      stubUpload();

      final outcome = await service.pushFolder(
        client: client,
        folderId: 42,
        folderDriveId: 'yy',
        knownRevision: 0,
      );

      expect(outcome, isA<PushSuccess>());
      expect((outcome as PushSuccess).revision, 1);
      verify(() => store.exportFolderSnapshot(42, any())).called(1);
      verifyNever(() => store.exportLibrarySnapshot(any(), any()));
      verify(() => client.uploadFile(
            name: any(named: 'name', that: startsWith('library-')),
            parentId: 'stage',
            data: any(named: 'data'),
            length: 2048,
            mimeType: any(named: 'mimeType'),
          )).called(1);
    });

    test('pushFolder révision distante divergente : conflit, pas d\'export',
        () async {
      final remote = SyncManifest(
        revision: 5,
        deviceId: 'other',
        updatedAt: DateTime.now().toUtc(),
        schemaVersion: 11,
      );
      when(() => client.findInFolder(parentId: 'yy', name: '.stagecue'))
          .thenAnswer((_) async => folder('stage', '.stagecue'));
      when(() => client.findInFolder(parentId: 'stage', name: 'manifest.json'))
          .thenAnswer((_) async => file('m', 'manifest.json'));
      when(() => client.downloadBytes('m'))
          .thenAnswer((_) async => utf8.encode(remote.encode()));

      final outcome = await service.pushFolder(
        client: client,
        folderId: 42,
        folderDriveId: 'yy',
        knownRevision: 2,
      );

      expect(outcome, isA<PushConflict>());
      expect((outcome as PushConflict).remote.revision, 5);
      verifyNever(() => store.exportFolderSnapshot(any(), any()));
    });

    test('pullFolder révision plus récente : télécharge et fusionne le dossier',
        () async {
      final remote = SyncManifest(
        revision: 7,
        deviceId: 'other',
        updatedAt: DateTime.now().toUtc(),
        schemaVersion: 11,
      );
      when(() => client.findInFolders(
            parentIds: any(named: 'parentIds'),
            name: '.stagecue',
          )).thenAnswer((_) async => {'yy': folder('stage', '.stagecue')});
      when(() => client.findInFolders(
            parentIds: any(named: 'parentIds'),
            name: 'manifest.json',
          )).thenAnswer((_) async => {'stage': file('m', 'manifest.json')});
      when(() => client.downloadBytes('m'))
          .thenAnswer((_) async => utf8.encode(remote.encode()));
      when(() => client.findInFolder(parentId: 'stage', name: 'library.db'))
          .thenAnswer((_) async => file('db', 'library.db'));
      when(() => client.downloadToFile(
            fileId: any(named: 'fileId'),
            destinationPath: any(named: 'destinationPath'),
          )).thenAnswer((_) async {});

      final outcome = await service.pullFolder(
        client: client,
        folderId: 42,
        folderDriveId: 'yy',
        knownRevision: 2,
      );

      expect(outcome, isA<PullStaged>());
      expect((outcome as PullStaged).revision, 7);
      verify(() => store.mergeFolderSnapshot(42, any())).called(1);
      verifyNever(
        () => store.mergeLibrarySnapshot(
          any(),
          any(),
          driveFolderId: any(named: 'driveFolderId'),
        ),
      );
    });
  });

  group('pullFolders (groupé)', () {
    SyncManifest manifest(int revision) => SyncManifest(
          revision: revision,
          deviceId: 'other',
          updatedAt: DateTime.now().toUtc(),
          schemaVersion: 11,
        );

    test('les sondes .stagecue et manifest sont GROUPÉES : deux requêtes pour '
        'trois dossiers, pas six', () async {
      when(() => client.findInFolders(
                parentIds: any(named: 'parentIds'),
                name: '.stagecue',
              ))
          .thenAnswer((_) async => {
                'da': folder('sa', '.stagecue'),
                'db': folder('sb', '.stagecue'),
                'dc': folder('sc', '.stagecue'),
              });
      when(() => client.findInFolders(
                parentIds: any(named: 'parentIds'),
                name: 'manifest.json',
              ))
          .thenAnswer((_) async => {
                'sa': file('ma', 'manifest.json'),
                'sb': file('mb', 'manifest.json'),
                'sc': file('mc', 'manifest.json'),
              });
      // Tous à jour : aucun snapshot n'est tiré.
      for (final id in ['ma', 'mb', 'mc']) {
        when(() => client.downloadBytes(id))
            .thenAnswer((_) async => utf8.encode(manifest(1).encode()));
      }

      final outcomes = await service.pullFolders(
        client: client,
        folders: const [
          FolderPullTarget(folderId: 1, folderDriveId: 'da', knownRevision: 5),
          FolderPullTarget(folderId: 2, folderDriveId: 'db', knownRevision: 5),
          FolderPullTarget(folderId: 3, folderDriveId: 'dc', knownRevision: 5),
        ],
      );

      expect(outcomes[1]?.outcome, isA<PullUpToDate>());
      expect(outcomes[2]?.outcome, isA<PullUpToDate>());
      expect(outcomes[3]?.outcome, isA<PullUpToDate>());

      // Le cœur du gain : deux sondes au total, quel que soit le nombre de
      // dossiers. La sonde unitaire n'est plus employée sur ce chemin.
      verify(() => client.findInFolders(
            parentIds: any(named: 'parentIds'),
            name: any(named: 'name'),
          )).called(2);
      verifyNever(() => client.findInFolder(
            parentId: any(named: 'parentId'),
            name: any(named: 'name'),
          ));
    });

    test('chaque dossier reçoit SON issue : sans .stagecue, sans manifest, '
        'à jour, ou fusionné', () async {
      when(() => client.findInFolders(
                parentIds: any(named: 'parentIds'),
                name: '.stagecue',
              ))
          .thenAnswer((_) async => {
                // 'd1' absent : aucun `.stagecue`.
                'd2': folder('s2', '.stagecue'),
                'd3': folder('s3', '.stagecue'),
                'd4': folder('s4', '.stagecue'),
              });
      when(() => client.findInFolders(
                parentIds: any(named: 'parentIds'),
                name: 'manifest.json',
              ))
          .thenAnswer((_) async => {
                // 's2' absent : `.stagecue` présent mais rien publié dedans.
                's3': file('m3', 'manifest.json'),
                's4': file('m4', 'manifest.json'),
              });
      when(() => client.downloadBytes('m3'))
          .thenAnswer((_) async => utf8.encode(manifest(2).encode()));
      when(() => client.downloadBytes('m4'))
          .thenAnswer((_) async => utf8.encode(manifest(9).encode()));
      when(() => client.findInFolder(parentId: 's4', name: 'library.db'))
          .thenAnswer((_) async => file('db4', 'library.db'));
      when(() => client.downloadToFile(
            fileId: any(named: 'fileId'),
            destinationPath: any(named: 'destinationPath'),
          )).thenAnswer((_) async {});

      final outcomes = await service.pullFolders(
        client: client,
        folders: const [
          FolderPullTarget(folderId: 1, folderDriveId: 'd1', knownRevision: 0),
          FolderPullTarget(folderId: 2, folderDriveId: 'd2', knownRevision: 0),
          FolderPullTarget(folderId: 3, folderDriveId: 'd3', knownRevision: 7),
          FolderPullTarget(folderId: 4, folderDriveId: 'd4', knownRevision: 7),
        ],
      );

      expect(outcomes[1]?.outcome, isA<PullNoRemoteSnapshot>());
      expect(outcomes[2]?.outcome, isA<PullNoRemoteSnapshot>());
      expect(outcomes[3]?.outcome, isA<PullUpToDate>());
      expect(outcomes[4]?.outcome, isA<PullStaged>());
      expect((outcomes[4]?.outcome as PullStaged).revision, 9);

      // Seul le dossier réellement en retard est fusionné.
      verify(() => store.mergeFolderSnapshot(4, any())).called(1);
      verifyNever(() => store.mergeFolderSnapshot(3, any()));
      verifyNever(() => store.mergeFolderSnapshot(2, any()));
      verifyNever(() => store.mergeFolderSnapshot(1, any()));
    });

    test('les fusions restent SÉQUENTIELLES (ATTACH/DETACH partagé)', () async {
      when(() => client.findInFolders(
                parentIds: any(named: 'parentIds'),
                name: '.stagecue',
              ))
          .thenAnswer((_) async => {
                'da': folder('sa', '.stagecue'),
                'db': folder('sb', '.stagecue'),
              });
      when(() => client.findInFolders(
                parentIds: any(named: 'parentIds'),
                name: 'manifest.json',
              ))
          .thenAnswer((_) async => {
                'sa': file('ma', 'manifest.json'),
                'sb': file('mb', 'manifest.json'),
              });
      for (final id in ['ma', 'mb']) {
        when(() => client.downloadBytes(id))
            .thenAnswer((_) async => utf8.encode(manifest(9).encode()));
      }
      when(() => client.findInFolder(
            parentId: any(named: 'parentId'),
            name: 'library.db',
          )).thenAnswer((_) async => file('db', 'library.db'));
      when(() => client.downloadToFile(
            fileId: any(named: 'fileId'),
            destinationPath: any(named: 'destinationPath'),
          )).thenAnswer((_) async {});

      var merging = 0;
      var maxConcurrentMerges = 0;
      when(() => store.mergeFolderSnapshot(any(), any()))
          .thenAnswer((_) async {
        merging++;
        if (merging > maxConcurrentMerges) maxConcurrentMerges = merging;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        merging--;
      });

      await service.pullFolders(
        client: client,
        folders: const [
          FolderPullTarget(folderId: 1, folderDriveId: 'da', knownRevision: 0),
          FolderPullTarget(folderId: 2, folderDriveId: 'db', knownRevision: 0),
        ],
      );

      expect(maxConcurrentMerges, 1,
          reason: 'deux ATTACH concurrents sur la base partagée se '
              'télescoperaient (cf. décision 0004)');
    });
  });

  group('cache de sonde du manifest', () {
    // Millisecondes NON nulles à dessein : le jeton doit les préserver. Une
    // colonne `dateTime()` les perdrait (Drift stocke en secondes epoch) et le
    // cache ne serait jamais touché.
    final probedAt = DateTime.utc(2026, 7, 30, 12, 0, 0, 456);
    final probedToken = probedAt.toIso8601String();

    SyncManifest manifest(int revision) => SyncManifest(
          revision: revision,
          deviceId: 'other',
          updatedAt: DateTime.now().toUtc(),
          schemaVersion: 11,
        );

    /// Stubs communs : un dossier `da` avec `.stagecue` + manifest daté.
    void stubProbe({required DateTime? modifiedTime}) {
      when(() => client.findInFolders(
                parentIds: any(named: 'parentIds'),
                name: '.stagecue',
              ))
          .thenAnswer((_) async => {'da': folder('sa', '.stagecue')});
      when(() => client.findInFolders(
            parentIds: any(named: 'parentIds'),
            name: 'manifest.json',
          )).thenAnswer((_) async => {
            'sa': DriveFile(
              id: 'ma',
              name: 'manifest.json',
              modifiedTime: modifiedTime,
            ),
          });
    }

    test('manifest inchangé : AUCUN téléchargement, à jour', () async {
      stubProbe(modifiedTime: probedAt);

      final results = await service.pullFolders(
        client: client,
        folders: [
          FolderPullTarget(
            folderId: 1,
            folderDriveId: 'da',
            knownRevision: 3,
            knownProbeToken: probedToken,
          ),
        ],
      );

      expect(results[1]?.outcome, isA<PullUpToDate>());
      expect(results[1]?.probeToken, probedToken);
      // Le drapeau est la seule mesure de l'efficacité de la sonde : s'il ne se
      // lève jamais en production, le pull retélécharge tous les manifests.
      expect(results[1]?.skippedByProbe, isTrue);
      verifyNever(() => client.downloadBytes(any()));
    });

    test('manifest redaté : le téléchargement a bien lieu, sans saut compté',
        () async {
      stubProbe(modifiedTime: probedAt.add(const Duration(minutes: 1)));
      when(() => client.downloadBytes('ma'))
          .thenAnswer((_) async => utf8.encode(manifest(3).encode()));

      final results = await service.pullFolders(
        client: client,
        folders: [
          FolderPullTarget(
            folderId: 1,
            folderDriveId: 'da',
            knownRevision: 3,
            knownProbeToken: probedToken,
          ),
        ],
      );

      expect(results[1]?.outcome, isA<PullUpToDate>());
      expect(results[1]?.skippedByProbe, isFalse);
      verify(() => client.downloadBytes('ma')).called(1);
    });

    test('Drive sans modifiedTime : on ne saute jamais la sonde', () async {
      stubProbe(modifiedTime: null);
      when(() => client.downloadBytes('ma'))
          .thenAnswer((_) async => utf8.encode(manifest(3).encode()));

      final results = await service.pullFolders(
        client: client,
        folders: [
          FolderPullTarget(
            folderId: 1,
            folderDriveId: 'da',
            knownRevision: 3,
            knownProbeToken: probedToken,
          ),
        ],
      );

      expect(results[1]?.outcome, isA<PullUpToDate>());
      expect(results[1]?.probeToken, isNull);
      verify(() => client.downloadBytes('ma')).called(1);
    });

    test('fusion impossible (blob introuvable) : RIEN n\'est mémorisé, sinon '
        'le nœud resterait figé sur une révision jamais fusionnée', () async {
      stubProbe(modifiedTime: probedAt);
      when(() => client.downloadBytes('ma'))
          .thenAnswer((_) async => utf8.encode(manifest(9).encode()));
      // Le manifest annonce la révision 9 mais son blob est absent.
      when(() => client.findInFolder(
            parentId: 'sa',
            name: any(named: 'name'),
          )).thenAnswer((_) async => null);

      final results = await service.pullFolders(
        client: client,
        folders: [
          FolderPullTarget(
            folderId: 1,
            folderDriveId: 'da',
            knownRevision: 3,
            knownProbeToken: null,
          ),
        ],
      );

      expect(results[1]?.outcome, isA<PullNoRemoteSnapshot>());
      expect(results[1]?.probeToken, isNull,
          reason: 'mémoriser ici ferait sauter la sonde au pull suivant');
    });
  });
}
