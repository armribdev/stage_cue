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
import 'package:stage_cue/features/sampler/data/models/indexing_progress.dart';
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

  /// Jeton rendu par `getStartPageToken`.
  String startPageToken = 'token-1';

  /// Pages de changements servies par `listChanges`, indexées par jeton.
  final Map<String, DriveChangePage> changePages = {};

  /// Jetons pour lesquels `listChanges` doit signaler une expiration.
  final Set<String> expiredTokens = {};

  int listChangesCalls = 0;

  /// Ids de fichiers dont le téléchargement doit échouer.
  final Set<String> failingDownloads = {};

  /// Ids de fichiers dont le téléchargement lève une expiration de session.
  final Set<String> authExpiredDownloads = {};

  Duration downloadLatency = Duration.zero;
  int downloadCalls = 0;
  int maxConcurrentDownloads = 0;
  int _downloadsInFlight = 0;

  _FakeDriveClient(this.tree);

  @override
  Future<void> downloadToFile({
    required String fileId,
    required String destinationPath,
  }) async {
    downloadCalls++;
    _downloadsInFlight++;
    if (_downloadsInFlight > maxConcurrentDownloads) {
      maxConcurrentDownloads = _downloadsInFlight;
    }
    try {
      if (downloadLatency > Duration.zero) {
        await Future<void>.delayed(downloadLatency);
      }
      if (authExpiredDownloads.contains(fileId)) {
        throw const DriveAuthException();
      }
      if (failingDownloads.contains(fileId)) {
        throw const DriveRequestException.offline();
      }
      final file = File(destinationPath);
      await file.parent.create(recursive: true);
      // Volontairement minuscule : sous le seuil de validité audio, donc le
      // backfill de métadonnées renonce avant tout appel à SoLoud (non
      // initialisé en test).
      await file.writeAsBytes(List.filled(16, 1));
    } finally {
      _downloadsInFlight--;
    }
  }

  @override
  Future<String> getStartPageToken({String? sharedDriveId}) async =>
      startPageToken;

  @override
  Future<DriveChangePage> listChanges({
    required String pageToken,
    String? sharedDriveId,
  }) async {
    listChangesCalls++;
    if (expiredTokens.contains(pageToken)) {
      throw const DriveChangeTokenExpiredException();
    }
    return changePages[pageToken] ??
        const DriveChangePage(changes: [], newStartPageToken: 'token-next');
  }

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
  /// Mutable : permet de simuler le remplacement du client en cours de passe
  /// (renouvellement de token) ou la perte définitive de session (`null`).
  DriveClient? client;
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

  /// Authentificateur du dernier repository construit : permet aux tests de
  /// remplacer ou de retirer la session en cours de passe.
  late _FakeAuthenticator authenticator;

  /// Construit le repository autour d'un client fake déjà « connecté ».
  Future<LibraryRepository> repositoryFor(_FakeDriveClient client) async {
    authenticator = _FakeAuthenticator(client);
    final repository = LibraryRepository(
      libraryDataSource,
      authenticator,
      LibrarySyncService(DriftSnapshotStore(database)),
      // Sonde disque simulée : la sonde réelle passe par le canal de plateforme,
      // indisponible en test unitaire — sans ça, chaque `ensureCached` échoue à
      // l'étape d'éviction et tous les téléchargements sont comptés en erreur.
      AudioCacheManager(
        availableDiskBytes: (_) async => 100 * 1024 * 1024 * 1024,
      ),
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

  group('synchronisation incrémentale (changes.list)', () {
    /// Bibliothèque armée pour le chemin incrémental : jeton posé et scan
    /// complet récent.
    Library armed({String token = 'token-1', Duration since = Duration.zero}) =>
        Library(
          id: library.id,
          name: library.name,
          localRootPath: library.localRootPath,
          driveFolderId: library.driveFolderId,
          createdAt: library.createdAt,
          driveChangeToken: token,
          lastFullScanAt: DateTime.now().subtract(since),
        );

    DriveChange audioChange(
      String id,
      String name, {
      required String parentId,
      String? md5,
    }) =>
        DriveChange(
          fileId: id,
          removed: false,
          file: DriveFile(
            id: id,
            name: name,
            mimeType: 'audio/mpeg',
            md5Checksum: md5,
          ),
          parentId: parentId,
        );

    test('sans jeton de reprise : scan complet demandé', () async {
      final client = _FakeDriveClient({'root': []});
      final repository = await repositoryFor(client);

      final outcome = await repository.applyDriveChanges(library: library);

      expect(outcome, isA<DriveSyncNeedsFullScan>());
      expect(client.listChangesCalls, 0);
    });

    test('dernier scan complet trop ancien : rescan périodique demandé',
        () async {
      final client = _FakeDriveClient({'root': []});
      final repository = await repositoryFor(client);

      final outcome = await repository.applyDriveChanges(
        library: armed(since: const Duration(days: 8)),
      );

      expect(outcome, isA<DriveSyncNeedsFullScan>());
      expect((outcome as DriveSyncNeedsFullScan).reason, 'rescan périodique');
      expect(client.listChangesCalls, 0,
          reason: 'le rescan périodique doit court-circuiter le delta');
    });

    test('jeton expiré : scan complet demandé', () async {
      final client = _FakeDriveClient({'root': []})
        ..expiredTokens.add('token-1');
      final repository = await repositoryFor(client);

      final outcome = await repository.applyDriveChanges(library: armed());

      expect(outcome, isA<DriveSyncNeedsFullScan>());
      expect((outcome as DriveSyncNeedsFullScan).reason, 'jeton expiré');
    });

    test('changement de DOSSIER : scan complet demandé (le delta ne porte pas '
        'la descendance)', () async {
      final client = _FakeDriveClient({'root': []});
      client.changePages['token-1'] = DriveChangePage(
        changes: [
          DriveChange(
            fileId: 'd9',
            removed: false,
            file: _folder('d9', 'Renommé'),
            parentId: 'root',
            isFolder: true,
          ),
        ],
        newStartPageToken: 'token-2',
      );
      final repository = await repositoryFor(client);

      final outcome = await repository.applyDriveChanges(library: armed());

      expect(outcome, isA<DriveSyncNeedsFullScan>());
      expect(
        (outcome as DriveSyncNeedsFullScan).reason,
        'changement de structure',
      );
    });

    test('ajout d\'un fichier dans un dossier connu : son créé, jeton avancé',
        () async {
      final client = _FakeDriveClient({
        'root': [_folder('d1', 'Portes')],
        // Le dossier doit déjà porter un son : un nœud dossier n'existe
        // localement que pour les dossiers qui contiennent des fichiers.
        'd1': [_audio('f0', 'existant.mp3')],
      });
      final repository = await repositoryFor(client);
      // Scan initial : crée le nœud dossier `d1` et pose le jeton.
      await repository.indexDriveFolder(library: library);

      client.changePages['token-1'] = DriveChangePage(
        changes: [audioChange('f1', 'knock.mp3', parentId: 'd1', md5: 'aaa')],
        newStartPageToken: 'token-2',
      );

      final outcome = await repository.applyDriveChanges(library: armed());

      expect(outcome, isA<DriveSyncApplied>());
      expect((outcome as DriveSyncApplied).upserted, 1);

      final sounds = await soundsOf(library.id);
      expect(sounds, hasLength(2));
      final added = sounds.firstWhere((s) => s.driveFileId == 'f1');
      expect(added.relativePath, 'Portes/knock.mp3');

      final stored = await (database.select(database.libraries)
            ..where((l) => l.id.equals(library.id)))
          .getSingle();
      expect(stored.driveChangeToken, 'token-2');
    });

    test('suppression signalée : son retiré et cache évincé', () async {
      final client = _FakeDriveClient({
        'root': [_audio('f1', 'intro.mp3'), _audio('f2', 'outro.mp3')],
      });
      final repository = await repositoryFor(client);
      await repository.indexDriveFolder(library: library);

      final cached =
          File('${cacheRoot.path}${Platform.pathSeparator}outro.mp3');
      await cached.writeAsString('audio');

      client.changePages['token-1'] = const DriveChangePage(
        changes: [DriveChange(fileId: 'f2', removed: true)],
        newStartPageToken: 'token-2',
      );

      final outcome = await repository.applyDriveChanges(library: armed());

      expect((outcome as DriveSyncApplied).removed, 1);
      final sounds = await soundsOf(library.id);
      expect(sounds, hasLength(1));
      expect(sounds.single.driveFileId, 'f1');
      expect(await cached.exists(), isFalse);
    });

    test('AUCUN élagage par différence : un delta vide ne supprime RIEN',
        () async {
      final client = _FakeDriveClient({
        'root': [
          _audio('f1', 'a.mp3'),
          _audio('f2', 'b.mp3'),
          _audio('f3', 'c.mp3'),
        ],
      });
      final repository = await repositoryFor(client);
      await repository.indexDriveFolder(library: library);
      expect(await soundsOf(library.id), hasLength(3));

      // Delta vide : Drive dit « rien n'a changé ». Un élagage par différence
      // d'ensembles conclurait ici que les trois fichiers ont disparu.
      client.changePages['token-1'] = const DriveChangePage(
        changes: [],
        newStartPageToken: 'token-2',
      );

      final outcome = await repository.applyDriveChanges(library: armed());

      expect(outcome, isA<DriveSyncApplied>());
      expect(await soundsOf(library.id), hasLength(3),
          reason: 'le chemin incrémental ne doit JAMAIS élaguer par différence');
    });

    test('un fichier audio dans un dossier inconnu : scan complet demandé, '
        'jamais un saut silencieux', () async {
      final client = _FakeDriveClient({
        'root': [_audio('f1', 'intro.mp3')],
      });
      final repository = await repositoryFor(client);
      await repository.indexDriveFolder(library: library);

      client.changePages['token-1'] = DriveChangePage(
        changes: [
          audioChange('f1', 'intro.mp3', parentId: 'dossier-inconnu'),
        ],
        newStartPageToken: 'token-2',
      );

      final outcome = await repository.applyDriveChanges(library: armed());

      expect(outcome, isA<DriveSyncNeedsFullScan>());
      // Le son reste intact : on n'a rien appliqué.
      expect((await soundsOf(library.id)).single.relativePath, 'intro.mp3');
    });

    test('changement portant sur une AUTRE bibliothèque : ignoré', () async {
      final client = _FakeDriveClient({
        'root': [_audio('f1', 'intro.mp3')],
      });
      final repository = await repositoryFor(client);
      await repository.indexDriveFolder(library: library);

      client.changePages['token-1'] = const DriveChangePage(
        changes: [
          // Fichier inconnu de cette bibliothèque, retiré ailleurs.
          DriveChange(fileId: 'etranger', removed: true),
        ],
        newStartPageToken: 'token-2',
      );

      final outcome = await repository.applyDriveChanges(library: armed());

      expect((outcome as DriveSyncApplied).removed, 0);
      expect(await soundsOf(library.id), hasLength(1));
    });

    test('pagination : toutes les pages sont collectées avant application',
        () async {
      final client = _FakeDriveClient({
        'root': [_folder('d1', 'Portes')],
        'd1': [_audio('f0', 'existant.mp3')],
      });
      final repository = await repositoryFor(client);
      await repository.indexDriveFolder(library: library);

      client.changePages['token-1'] = DriveChangePage(
        changes: [audioChange('f1', 'a.mp3', parentId: 'd1')],
        nextPageToken: 'page-2',
      );
      client.changePages['page-2'] = DriveChangePage(
        changes: [audioChange('f2', 'b.mp3', parentId: 'd1')],
        newStartPageToken: 'token-2',
      );

      final outcome = await repository.applyDriveChanges(library: armed());

      expect((outcome as DriveSyncApplied).upserted, 2);
      expect(await soundsOf(library.id), hasLength(3));
      expect(client.listChangesCalls, 2);
    });

    test('un scan complet arme le parcours incrémental (jeton pris AVANT le '
        'parcours) et réarme l\'horloge du rescan', () async {
      final client = _FakeDriveClient({'root': [_audio('f1', 'intro.mp3')]})
        ..startPageToken = 'token-frais';
      final repository = await repositoryFor(client);

      await repository.indexDriveFolder(library: library);

      final stored = await (database.select(database.libraries)
            ..where((l) => l.id.equals(library.id)))
          .getSingle();
      expect(stored.driveChangeToken, 'token-frais');
      expect(stored.lastFullScanAt, isNotNull);
    });
  });

  group('téléchargement de masse', () {
    /// Indexe [count] sons (métadonnées seules — aucun fichier local).
    Future<LibraryRepository> indexedLibrary(
      _FakeDriveClient client,
      int count,
    ) async {
      client.tree['root'] = [
        for (var i = 0; i < count; i++) _audio('f$i', 'son_$i.mp3'),
      ];
      final repository = await repositoryFor(client);
      await repository.indexDriveFolder(library: library);
      return repository;
    }

    test('les téléchargements sont parallèles, dans la limite de la borne',
        () async {
      final client = _FakeDriveClient({})
        ..downloadLatency = const Duration(milliseconds: 5);
      final repository = await indexedLibrary(client, 20);

      final downloaded =
          await repository.downloadAllLibraryAudio(library: library);

      expect(downloaded, 20);
      expect(client.maxConcurrentDownloads, greaterThan(1),
          reason: 'la passe doit être parallèle');
      expect(client.maxConcurrentDownloads, lessThanOrEqualTo(4),
          reason: 'la borne de concurrence doit être respectée');
    });

    test('un fichier en échec n\'emporte pas la passe', () async {
      final client = _FakeDriveClient({})..failingDownloads.add('f2');
      final repository = await indexedLibrary(client, 5);

      IndexingProgress? last;
      final downloaded = await repository.downloadAllLibraryAudio(
        library: library,
        onProgress: (p) => last = p,
      );

      // Contrairement à l'indexation, où un trou fait SUPPRIMER des sons, un
      // téléchargement raté ne fait que laisser un son non matérialisé : la
      // passe doit continuer.
      expect(downloaded, 4);
      expect(last?.isComplete, isTrue);
      expect(last?.error, contains('1 fichier(s) ignoré(s)'));
    });

    test('session expirée : la passe s\'arrête, les tâches restantes renoncent',
        () async {
      final client = _FakeDriveClient({})
        ..downloadLatency = const Duration(milliseconds: 5)
        ..authExpiredDownloads.add('f0');
      final repository = await indexedLibrary(client, 30);

      IndexingProgress? last;
      await repository.downloadAllLibraryAudio(
        library: library,
        onProgress: (p) => last = p,
      );

      expect(last?.error, contains('Session Google expirée'));
      // Les tâches déjà en file se vident sans rien télécharger : on ne doit
      // pas voir les 30 fichiers tentés un par un.
      expect(client.downloadCalls, lessThan(30),
          reason: 'les tâches restantes doivent renoncer, pas échouer une à une');
    });

    test('annulation : plus aucun téléchargement ne démarre', () async {
      final client = _FakeDriveClient({})
        ..downloadLatency = const Duration(milliseconds: 5);
      final repository = await indexedLibrary(client, 40);

      final pass = repository.downloadAllLibraryAudio(library: library);
      repository.cancelLibraryDownload(library.id);
      await pass;

      expect(client.downloadCalls, lessThan(40),
          reason: 'l\'annulation doit tarir la file');
    });

    test('client remplacé en cours de passe : la passe suit le NOUVEAU client',
        () async {
      final first = _FakeDriveClient({})
        ..downloadLatency = const Duration(milliseconds: 5);
      final repository = await indexedLibrary(first, 20);

      final second = _FakeDriveClient({})
        ..downloadLatency = const Duration(milliseconds: 5);

      final pass = repository.downloadAllLibraryAudio(library: library);
      // Ce que fait `reconnectSilently` sous les pieds d'une passe en cours :
      // il pose un client frais et DISPOSE le précédent. Quand la passe
      // capturait son client une fois pour toutes, tous les fichiers restants
      // échouaient sur « Client is already closed » — traduit en « Pas de
      // connexion », soit des centaines de lignes annonçant une panne réseau
      // qui n'existait pas.
      authenticator.client = second;
      await repository.reconnectSilently();
      await pass;

      expect(second.downloadCalls, greaterThan(0),
          reason: 'le client doit être relu à chaque fichier, jamais capturé');
      expect(
        first.downloadCalls + second.downloadCalls,
        20,
        reason: 'aucun fichier ne doit être perdu au changement de client',
      );
    });

    test('session définitivement perdue : arrêt net, pas une rafale d\'échecs',
        () async {
      final client = _FakeDriveClient({})
        ..downloadLatency = const Duration(milliseconds: 5);
      final repository = await indexedLibrary(client, 40);

      IndexingProgress? last;
      final pass = repository.downloadAllLibraryAudio(
        library: library,
        onProgress: (p) => last = p,
      );
      // Plus aucune session à rétablir : continuer ferait échouer chacun des
      // fichiers restants, un par un.
      authenticator.client = null;
      await repository.releaseDriveSession();
      await pass;

      expect(client.downloadCalls, lessThan(40),
          reason: 'la passe doit s\'arrêter, pas échouer fichier par fichier');
      expect(last?.error, contains('Connexion Drive interrompue'),
          reason: 'à distinguer d\'une session expirée côté Google');
    });

    test('fichiers déjà en cache : aucun téléchargement', () async {
      final client = _FakeDriveClient({});
      final repository = await indexedLibrary(client, 3);
      await repository.downloadAllLibraryAudio(library: library);
      final afterFirst = client.downloadCalls;

      final downloaded =
          await repository.downloadAllLibraryAudio(library: library);

      expect(downloaded, 0);
      expect(client.downloadCalls, afterFirst);
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
