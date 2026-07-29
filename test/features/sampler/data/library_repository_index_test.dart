// Test de CARACTÉRISATION de `indexDriveFolder`.
//
// Il ne décrit pas un comportement souhaité mais le comportement ACTUEL, pour
// servir de filet avant l'optimisation de la boucle d'indexation (préchargement
// des maps + écriture en batch). Chaque cas verrouille une propriété dont la
// régression est silencieuse et destructrice : l'indexation supprime des sons
// et des fichiers de cache (cf. `pruneSoundsAbsentFromDrive`).
//
// Compte aussi les appels `listFolder` : la parallélisation du listing ne doit
// pas changer le nombre de requêtes, seulement leur ordonnancement.

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/core/sync/audio_cache_manager.dart';
import 'package:stage_cue/core/sync/drive_account_profile.dart';
import 'package:stage_cue/core/sync/drive_client.dart';
import 'package:stage_cue/core/sync/drive_models.dart';
import 'package:stage_cue/core/sync/library_sync_service.dart';
import 'package:stage_cue/core/sync/snapshot_store.dart';
import 'package:stage_cue/features/sampler/data/datasources/local_library_datasource.dart';
import 'package:stage_cue/features/sampler/data/datasources/local_sound_datasource.dart';
import 'package:stage_cue/features/sampler/data/repositories/library_repository.dart';
import 'package:stage_cue/features/sampler/domain/entities/library.dart';

/// Client Drive en mémoire : une arborescence `folderId -> enfants`.
class _FakeDriveClient implements DriveClient {
  /// Enfants directs par id de dossier.
  final Map<String, List<DriveFile>> tree;

  /// Nombre d'appels `listFolder` du dernier scan (budget de requêtes).
  int listFolderCalls = 0;

  /// Ids de dossiers listés, dans l'ordre d'appel.
  final List<String> listedFolders = [];

  /// Ids dont le listing doit échouer (simulation d'erreur réseau/quota).
  final Set<String> failingFolders = {};

  /// Latence simulée : sans elle, les futures se résolvent trop vite pour
  /// qu'un chevauchement soit observable.
  Duration latency = Duration.zero;

  /// Plus grand nombre de listings simultanés observé.
  int maxConcurrent = 0;
  int _inFlight = 0;

  _FakeDriveClient(this.tree);

  @override
  Future<List<DriveFile>> listFolder(
    String folderId, {
    String? sharedDriveId,
  }) async {
    listFolderCalls++;
    listedFolders.add(folderId);
    _inFlight++;
    if (_inFlight > maxConcurrent) maxConcurrent = _inFlight;
    try {
      if (latency > Duration.zero) await Future<void>.delayed(latency);
      if (failingFolders.contains(folderId)) {
        throw const DriveRequestException.offline();
      }
      return tree[folderId] ?? const [];
    } finally {
      _inFlight--;
    }
  }

  @override
  void dispose() {}

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'Appel Drive non prévu par le test : ${invocation.memberName}',
      );
}

/// Authentificateur qui rend toujours le même client fake.
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

DriveFile _folder(String id, String name) =>
    DriveFile(id: id, name: name, mimeType: driveFolderMimeType);

DriveFile _audio(String id, String name, {String? md5}) =>
    DriveFile(id: id, name: name, mimeType: 'audio/mpeg', md5Checksum: md5);

void main() {
  late db.AppDatabase database;
  late LocalSoundDataSource soundDataSource;
  late LocalLibraryDataSource libraryDataSource;
  late Directory cacheRoot;
  late Library library;

  /// Construit le repository autour d'un client fake déjà « connecté ».
  Future<LibraryRepository> repositoryFor(_FakeDriveClient client) async {
    final repository = LibraryRepository(
      libraryDataSource,
      _FakeAuthenticator(client),
      LibrarySyncService(DriftSnapshotStore(database)),
      AudioCacheManager(),
      soundDataSource,
    );
    // Passe par le chemin de production pour poser `_activeClient` : pas de
    // porte dérobée ajoutée à la classe pour les besoins du test.
    final connected = await repository.reconnectSilently();
    expect(connected, isTrue);
    return repository;
  }

  setUp(() async {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    soundDataSource = LocalSoundDataSource(database);
    libraryDataSource = LocalLibraryDataSource(database);
    cacheRoot = await Directory.systemTemp.createTemp('stagecue_index_test');

    final id = await database.into(database.libraries).insert(
          db.LibrariesCompanion.insert(
            name: 'Lib',
            localRootPath: cacheRoot.path,
            driveFolderId: const Value('root'),
          ),
        );
    library = Library(
      id: id,
      name: 'Lib',
      localRootPath: cacheRoot.path,
      driveFolderId: 'root',
      createdAt: DateTime.now(),
      // Laissé à false : `autoDownload` déclencherait le pré-téléchargement en
      // arrière-plan, hors périmètre de ce test.
      autoDownload: false,
    );
  });

  tearDown(() async {
    await database.close();
    if (await cacheRoot.exists()) {
      await cacheRoot.delete(recursive: true);
    }
  });

  Future<List<db.Sound>> soundsOf(int libraryId) =>
      (database.select(database.sounds)
            ..where((s) => s.libraryId.equals(libraryId)))
          .get();

  test('scan initial : crée nœuds, memberships et sons ; ignore .stagecue et '
      'les fichiers non audio', () async {
    final client = _FakeDriveClient({
      'root': [
        _audio('f1', 'intro.mp3'),
        _folder('d1', 'Portes'),
        _folder('stage', '.stagecue'),
        DriveFile(id: 'x1', name: 'notes.txt', mimeType: 'text/plain'),
      ],
      'd1': [_audio('f2', 'knock.wav')],
      // Ne doit jamais être listé.
      'stage': [_audio('f9', 'boards.db')],
    });
    final repository = await repositoryFor(client);

    final result = await repository.indexDriveFolder(library: library);

    expect(result.newFileCount, 2);
    expect(result.presentDriveFileIds, {'f1', 'f2'});
    expect(client.listedFolders, isNot(contains('stage')));

    final sounds = await soundsOf(library.id);
    expect(sounds.map((s) => s.relativePath), containsAll(<String>[
      'intro.mp3',
      'Portes/knock.wav',
    ]));

    // Un nœud dossier par dossier PORTEUR de fichiers (racine + Portes).
    final folders = await libraryDataSource.getFoldersForLibrary(library.id);
    expect(folders.map((f) => f.driveFolderId), containsAll(<String>[
      'root',
      'd1',
    ]));
    final memberships =
        await libraryDataSource.getMemberFolderIds(library.id);
    expect(memberships, hasLength(folders.length));
  });

  test('fichier déplacé (même driveFileId) : pas de doublon, chemin et nœud '
      'dossier réalignés', () async {
    final client = _FakeDriveClient({
      'root': [_folder('d1', 'Portes')],
      'd1': [_audio('f1', 'knock.mp3')],
    });
    final repository = await repositoryFor(client);
    await repository.indexDriveFolder(library: library);

    // Déplacement vers un autre dossier, id de fichier inchangé.
    client.tree['root'] = [_folder('d1', 'Portes'), _folder('d2', 'SFX')];
    client.tree['d1'] = [];
    client.tree['d2'] = [_audio('f1', 'knock.mp3')];

    final result = await repository.indexDriveFolder(library: library);

    expect(result.newFileCount, 0);
    final sounds = await soundsOf(library.id);
    expect(sounds, hasLength(1));
    expect(sounds.first.relativePath, 'SFX/knock.mp3');

    final folders = await libraryDataSource.getFoldersForLibrary(library.id);
    final sfx = folders.firstWhere((f) => f.driveFolderId == 'd2');
    expect(sounds.first.folderId, sfx.id);
  });

  test('édition en place (md5 changé) : waveform et contentHash invalidés, '
      'fichier de cache évincé', () async {
    final client = _FakeDriveClient({
      'root': [_audio('f1', 'intro.mp3', md5: 'aaa')],
    });
    final repository = await repositoryFor(client);
    await repository.indexDriveFolder(library: library);

    // Dérivés de contenu déjà calculés + fichier présent en cache.
    await (database.update(database.sounds)
          ..where((s) => s.driveFileId.equals('f1')))
        .write(db.SoundsCompanion(
      waveform: Value(Uint8List.fromList([0, 1, 0])),
      contentHash: const Value('hash-v1'),
    ));
    final cached = File('${cacheRoot.path}${Platform.pathSeparator}intro.mp3');
    await cached.writeAsString('audio-v1');

    client.tree['root'] = [_audio('f1', 'intro.mp3', md5: 'bbb')];
    await repository.indexDriveFolder(library: library);

    final sound = (await soundsOf(library.id)).single;
    expect(sound.waveform, isNull);
    expect(sound.contentHash, isNull);
    expect(sound.driveMd5, 'bbb');
    expect(await cached.exists(), isFalse);
  });

  test('md5 inchangé : les dérivés de contenu sont conservés', () async {
    final client = _FakeDriveClient({
      'root': [_audio('f1', 'intro.mp3', md5: 'aaa')],
    });
    final repository = await repositoryFor(client);
    await repository.indexDriveFolder(library: library);

    await (database.update(database.sounds)
          ..where((s) => s.driveFileId.equals('f1')))
        .write(db.SoundsCompanion(
          waveform: Value(Uint8List.fromList([0, 1, 0])),
        ));

    await repository.indexDriveFolder(library: library);

    expect((await soundsOf(library.id)).single.waveform, [0, 1, 0]);
  });

  test('fichier disparu de Drive : son élagué et fichier de cache supprimé',
      () async {
    final client = _FakeDriveClient({
      'root': [_audio('f1', 'intro.mp3'), _audio('f2', 'outro.mp3')],
    });
    final repository = await repositoryFor(client);
    await repository.indexDriveFolder(library: library);

    final cached = File('${cacheRoot.path}${Platform.pathSeparator}outro.mp3');
    await cached.writeAsString('audio');

    client.tree['root'] = [_audio('f1', 'intro.mp3')];
    final result = await repository.indexDriveFolder(library: library);

    expect(result.presentDriveFileIds, {'f1'});
    final sounds = await soundsOf(library.id);
    expect(sounds, hasLength(1));
    expect(sounds.single.driveFileId, 'f1');
    expect(await cached.exists(), isFalse);
  });

  test('son legacy sans driveFileId : épargné par l\'élagage et adopte '
      'l\'identité forte quand son chemin est retrouvé', () async {
    // Son issu d'un snapshot, sans identité forte.
    await database.into(database.sounds).insert(
          db.SoundsCompanion.insert(
            title: 'knock',
            filePath: '${cacheRoot.path}/Portes/knock.mp3',
            libraryId: Value(library.id),
            relativePath: const Value('Portes/knock.mp3'),
          ),
        );

    final client = _FakeDriveClient({
      'root': [_folder('d1', 'Portes')],
      'd1': [_audio('f1', 'knock.mp3')],
    });
    final repository = await repositoryFor(client);

    final result = await repository.indexDriveFolder(library: library);

    // Adopté, pas dupliqué.
    expect(result.newFileCount, 0);
    final sounds = await soundsOf(library.id);
    expect(sounds, hasLength(1));
    expect(sounds.single.driveFileId, 'f1');
  });

  test('son legacy dont le fichier est absent de Drive : conservé (jamais '
      'élagué faute d\'identité forte)', () async {
    await database.into(database.sounds).insert(
          db.SoundsCompanion.insert(
            title: 'orphelin',
            filePath: '${cacheRoot.path}/orphelin.mp3',
            libraryId: Value(library.id),
            relativePath: const Value('introuvable/orphelin.mp3'),
          ),
        );

    final client = _FakeDriveClient({
      'root': [_audio('f1', 'intro.mp3')],
    });
    final repository = await repositoryFor(client);
    await repository.indexDriveFolder(library: library);

    final sounds = await soundsOf(library.id);
    expect(sounds, hasLength(2));
    expect(
      sounds.where((s) => s.driveFileId == null).single.title,
      'orphelin',
    );
  });

  group('parcours parallèle', () {
    test('les dossiers d\'un même niveau sont listés en parallèle, sans '
        'dépasser la borne de concurrence', () async {
      // 20 dossiers frères : de quoi saturer la borne (5) si le parcours est
      // bien parallèle, et la dépasser s'il ne l'est pas.
      final tree = <String, List<DriveFile>>{
        'root': [for (var i = 0; i < 20; i++) _folder('d$i', 'Dossier $i')],
      };
      for (var i = 0; i < 20; i++) {
        tree['d$i'] = [_audio('f$i', 'son_$i.mp3')];
      }
      final client = _FakeDriveClient(tree)..latency =
          const Duration(milliseconds: 5);
      final repository = await repositoryFor(client);

      await repository.indexDriveFolder(library: library);

      expect(client.maxConcurrent, greaterThan(1),
          reason: 'le parcours doit être parallèle');
      expect(client.maxConcurrent, lessThanOrEqualTo(5),
          reason: 'la borne de concurrence doit être respectée');
      expect((await soundsOf(library.id)), hasLength(20));
    });

    test('COMPLET OU RIEN : l\'échec du listing d\'un seul dossier fait '
        'échouer le scan et n\'élague RIEN', () async {
      final client = _FakeDriveClient({
        'root': [_folder('d1', 'Portes'), _folder('d2', 'SFX')],
        'd1': [_audio('f1', 'knock.mp3')],
        'd2': [_audio('f2', 'boom.mp3')],
      });
      final repository = await repositoryFor(client);
      await repository.indexDriveFolder(library: library);
      expect(await soundsOf(library.id), hasLength(2));

      // Un dossier devient injoignable. Ses fichiers sont donc ABSENTS du scan :
      // si l'erreur était avalée, l'élagage les prendrait pour des fichiers
      // supprimés sur Drive et détruirait les sons ET leur cache.
      client.failingFolders.add('d2');

      await expectLater(
        repository.indexDriveFolder(library: library),
        throwsA(isA<DriveRequestException>()),
      );

      final sounds = await soundsOf(library.id);
      expect(sounds, hasLength(2),
          reason: 'aucun son ne doit être élagué sur un scan incomplet');
    });
  });

  test('arborescence profonde : un seul listFolder par dossier, chemins '
      'relatifs complets', () async {
    final client = _FakeDriveClient({
      'root': [_folder('d1', 'Actes')],
      'd1': [_folder('d2', 'Acte 1')],
      'd2': [_folder('d3', 'Scene 1')],
      'd3': [_audio('f1', 'pluie.mp3')],
    });
    final repository = await repositoryFor(client);

    await repository.indexDriveFolder(library: library);

    expect(client.listFolderCalls, 4);
    expect(
      (await soundsOf(library.id)).single.relativePath,
      'Actes/Acte 1/Scene 1/pluie.mp3',
    );
  });
}
