import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/features/sampler/data/datasources/local_library_datasource.dart';
import 'package:stage_cue/features/sampler/data/datasources/local_sound_datasource.dart';

/// Vérifie la déduplication par identité forte Drive (`driveFileId`) lors de
/// l'indexation d'un dossier Drive — le correctif central contre les doublons.
void main() {
  late db.AppDatabase database;
  late LocalSoundDataSource dataSource;

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    dataSource = LocalSoundDataSource(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<int> insertLibrary() => database.into(database.libraries).insert(
        db.LibrariesCompanion.insert(name: 'Lib', localRootPath: '/cache'),
      );

  Future<List<db.Sound>> soundsOf(int libraryId) =>
      (database.select(database.sounds)
            ..where((s) => s.libraryId.equals(libraryId)))
          .get();

  test('un fichier renommé/déplacé sur Drive (même ID) ne crée pas de doublon',
      () async {
    final libraryId = await insertLibrary();

    final created1 = await dataSource.syncLibrarySoundFromDriveIndex(
      libraryId: libraryId,
      relativePath: 'Portes/knock.mp3',
      localPath: '/cache/Portes/knock.mp3',
      driveFileId: 'F1',
    );
    expect(created1, isTrue);

    // Déplacement + renommage côté Drive, même ID de fichier.
    final created2 = await dataSource.syncLibrarySoundFromDriveIndex(
      libraryId: libraryId,
      relativePath: 'SFX/knock-2.mp3',
      localPath: '/cache/SFX/knock-2.mp3',
      driveFileId: 'F1',
    );
    expect(created2, isFalse);

    final sounds = await soundsOf(libraryId);
    expect(sounds, hasLength(1));
    expect(sounds.first.relativePath, 'SFX/knock-2.mp3');
    expect(sounds.first.filePath, '/cache/SFX/knock-2.mp3');
    expect(sounds.first.driveFileId, 'F1');
  });

  test('un son legacy (sans driveFileId) adopte l\'identité forte au rescan',
      () async {
    final libraryId = await insertLibrary();

    // Son indexé avant l'introduction de l'identité forte.
    await database.into(database.sounds).insert(
          db.SoundsCompanion.insert(
            title: 'knock',
            filePath: '/cache/knock.mp3',
            libraryId: Value(libraryId),
            relativePath: const Value('knock.mp3'),
          ),
        );

    final created = await dataSource.syncLibrarySoundFromDriveIndex(
      libraryId: libraryId,
      relativePath: 'knock.mp3',
      localPath: '/cache/knock.mp3',
      driveFileId: 'F1',
    );
    expect(created, isFalse);

    final sounds = await soundsOf(libraryId);
    expect(sounds, hasLength(1));
    expect(sounds.first.driveFileId, 'F1');
  });

  test('deux fichiers Drive distincts donnent deux sons', () async {
    final libraryId = await insertLibrary();

    await dataSource.syncLibrarySoundFromDriveIndex(
      libraryId: libraryId,
      relativePath: 'a.mp3',
      localPath: '/cache/a.mp3',
      driveFileId: 'F1',
    );
    await dataSource.syncLibrarySoundFromDriveIndex(
      libraryId: libraryId,
      relativePath: 'b.mp3',
      localPath: '/cache/b.mp3',
      driveFileId: 'F2',
    );

    expect(await soundsOf(libraryId), hasLength(2));
  });

  group('modèle par-dossier (LibraryFolders)', () {
    test('ensureFolder partage un nœud par (libraryId, driveFolderId)',
        () async {
      final libraryDataSource = LocalLibraryDataSource(database);
      final libraryId = await insertLibrary();

      final first = await libraryDataSource.ensureFolder(
        libraryId: libraryId,
        driveFolderId: 'FOLDER_YY',
        relativePath: 'yy',
      );
      // Deuxième lien (ex : bibliothèque imbriquée) sur le même dossier Drive.
      final second = await libraryDataSource.ensureFolder(
        libraryId: libraryId,
        driveFolderId: 'FOLDER_YY',
        relativePath: 'yy',
      );
      expect(second, first, reason: 'un seul nœud pour le même dossier Drive');

      final nodes = await database.select(database.libraryFolders).get();
      expect(nodes, hasLength(1));
    });

    test('ensureFolder met à jour relativePath si le dossier est déplacé',
        () async {
      final libraryDataSource = LocalLibraryDataSource(database);
      final libraryId = await insertLibrary();

      final id = await libraryDataSource.ensureFolder(
        libraryId: libraryId,
        driveFolderId: 'FOLDER_YY',
        relativePath: 'yy',
      );
      await libraryDataSource.ensureFolder(
        libraryId: libraryId,
        driveFolderId: 'FOLDER_YY',
        relativePath: 'sfx/yy',
      );

      final node = await (database.select(database.libraryFolders)
            ..where((f) => f.id.equals(id)))
          .getSingle();
      expect(node.relativePath, 'sfx/yy');
    });

    test('un fichier déplacé vers un autre dossier réassigne son folderId',
        () async {
      final libraryDataSource = LocalLibraryDataSource(database);
      final libraryId = await insertLibrary();

      final folderA = await libraryDataSource.ensureFolder(
        libraryId: libraryId,
        driveFolderId: 'FOLDER_A',
        relativePath: 'a',
      );
      await dataSource.syncLibrarySoundFromDriveIndex(
        libraryId: libraryId,
        relativePath: 'a/knock.mp3',
        localPath: '/cache/a/knock.mp3',
        driveFileId: 'F1',
        folderId: folderA,
      );

      final folderB = await libraryDataSource.ensureFolder(
        libraryId: libraryId,
        driveFolderId: 'FOLDER_B',
        relativePath: 'b',
      );
      final created = await dataSource.syncLibrarySoundFromDriveIndex(
        libraryId: libraryId,
        relativePath: 'b/knock.mp3',
        localPath: '/cache/b/knock.mp3',
        driveFileId: 'F1',
        folderId: folderB,
      );

      expect(created, isFalse, reason: 'même fichier Drive, pas de doublon');
      final sounds = await soundsOf(libraryId);
      expect(sounds, hasLength(1));
      expect(sounds.first.folderId, folderB);
      expect(sounds.first.relativePath, 'b/knock.mp3');
    });
  });
}
