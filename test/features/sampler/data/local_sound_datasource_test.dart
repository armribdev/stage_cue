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

  Future<int> insertLibrary({String name = 'Lib', String root = '/cache'}) =>
      database.into(database.libraries).insert(
            db.LibrariesCompanion.insert(name: name, localRootPath: root),
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

  group('identité globale (dossiers imbriqués liés séparément)', () {
    test(
        'le même fichier Drive lié via deux bibliothèques ne crée pas de doublon',
        () async {
      final parentLib = await insertLibrary(name: 'Parent', root: '/parent');
      final childLib = await insertLibrary(name: 'Child', root: '/child');

      // La bibliothèque Parent indexe le fichier (vu sous Child/knock.mp3).
      final createdInParent = await dataSource.syncLibrarySoundFromDriveIndex(
        libraryId: parentLib,
        relativePath: 'Child/knock.mp3',
        localPath: '/parent/Child/knock.mp3',
        driveFileId: 'F1',
      );
      expect(createdInParent, isTrue);

      // La bibliothèque Child (racine = le sous-dossier) indexe le MÊME fichier
      // Drive, vu à sa racine (knock.mp3). Aucun doublon ne doit être créé.
      final createdInChild = await dataSource.syncLibrarySoundFromDriveIndex(
        libraryId: childLib,
        relativePath: 'knock.mp3',
        localPath: '/child/knock.mp3',
        driveFileId: 'F1',
      );
      expect(createdInChild, isFalse);

      final all = await database.select(database.sounds).get();
      expect(all, hasLength(1), reason: 'un fichier physique = une ligne');
      // Le son reste dans le cadre de chemins de son propriétaire (Parent) —
      // il n'est pas réécrit vers la racine de Child.
      expect(all.first.libraryId, parentLib);
      expect(all.first.relativePath, 'Child/knock.mp3');
      expect(all.first.filePath, '/parent/Child/knock.mp3');
    });

    test('driveFileId est unique en base (index global)', () async {
      final libraryId = await insertLibrary();
      await dataSource.syncLibrarySoundFromDriveIndex(
        libraryId: libraryId,
        relativePath: 'a.mp3',
        localPath: '/cache/a.mp3',
        driveFileId: 'DUP',
      );

      // Tentative d'insertion directe d'un second son au même driveFileId.
      expect(
        () => database.into(database.sounds).insert(
              db.SoundsCompanion.insert(
                title: 'dup',
                filePath: '/cache/b.mp3',
                libraryId: Value(libraryId),
                relativePath: const Value('b.mp3'),
                driveFileId: const Value('DUP'),
              ),
            ),
        throwsA(anything),
      );
    });

    test('vue partagée : la bibliothèque invitée voit les sons du dossier partagé',
        () async {
      final libraryDataSource = LocalLibraryDataSource(database);
      final parentLib = await insertLibrary(name: 'Parent', root: '/parent');
      final childLib = await insertLibrary(name: 'Child', root: '/child');

      // Sous-dossier partagé : un nœud global unique, possédé par Parent (home).
      final sharedFolder = await libraryDataSource.ensureFolder(
        libraryId: parentLib,
        driveFolderId: 'FOLDER_SUB',
        relativePath: 'sub',
      );
      await dataSource.syncLibrarySoundFromDriveIndex(
        libraryId: parentLib,
        relativePath: 'sub/knock.mp3',
        localPath: '/parent/sub/knock.mp3',
        driveFileId: 'F1',
        folderId: sharedFolder,
      );

      // L'indexation de chaque bibliothèque atteignant ce dossier l'y rattache.
      await libraryDataSource.ensureMembership(
        libraryId: parentLib,
        folderId: sharedFolder,
      );
      await libraryDataSource.ensureMembership(
        libraryId: childLib,
        folderId: sharedFolder,
      );

      final ownedByParent = await soundsOf(parentLib);
      final visibleToChild =
          await dataSource.getSoundIdsVisibleToLibrary(childLib);
      expect(
        visibleToChild,
        {ownedByParent.single.id},
        reason: 'la biblio invitée voit le son partagé (sans doublon)',
      );
      expect(
        await database.select(database.sounds).get(),
        hasLength(1),
        reason: 'un fichier physique = une ligne, même partagé',
      );
    });

    test('ensureFolder partage un nœud globalement entre bibliothèques',
        () async {
      final libraryDataSource = LocalLibraryDataSource(database);
      final parentLib = await insertLibrary(name: 'Parent', root: '/parent');
      final childLib = await insertLibrary(name: 'Child', root: '/child');

      final fromParent = await libraryDataSource.ensureFolder(
        libraryId: parentLib,
        driveFolderId: 'FOLDER_YY',
        relativePath: 'yy',
      );
      final fromChild = await libraryDataSource.ensureFolder(
        libraryId: childLib,
        driveFolderId: 'FOLDER_YY',
        relativePath: '',
      );
      expect(fromChild, fromParent, reason: 'un seul nœud par dossier Drive');

      final nodes = await database.select(database.libraryFolders).get();
      expect(nodes, hasLength(1));
      // Le relativePath du propriétaire (Parent) n'est pas écrasé par Child.
      expect(nodes.first.libraryId, parentLib);
      expect(nodes.first.relativePath, 'yy');
    });
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

  group('élagage des sons supprimés directement sur Drive', () {
    test('supprime le son dont le fichier a disparu du scan', () async {
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

      // F2 a été supprimé directement sur Drive : le scan ne remonte plus que F1.
      final pruned = await dataSource.pruneLibrarySoundsAbsentFromDrive(
        libraryId: libraryId,
        keptDriveFileIds: {'F1'},
      );

      expect(pruned, ['b.mp3'],
          reason: 'retourne le relativePath du son élagué');
      final sounds = await soundsOf(libraryId);
      expect(sounds, hasLength(1));
      expect(sounds.first.driveFileId, 'F1');
    });

    test('épargne les sons legacy sans driveFileId', () async {
      final libraryId = await insertLibrary();
      await database.into(database.sounds).insert(
            db.SoundsCompanion.insert(
              title: 'legacy',
              filePath: '/cache/legacy.mp3',
              libraryId: Value(libraryId),
              relativePath: const Value('legacy.mp3'),
            ),
          );

      // Aucun survivant à identité forte, mais le legacy ne doit pas être élagué.
      final pruned = await dataSource.pruneLibrarySoundsAbsentFromDrive(
        libraryId: libraryId,
        keptDriveFileIds: const {},
      );

      expect(pruned, isEmpty);
      expect(await soundsOf(libraryId), hasLength(1));
    });

    test('scan vide supprime tous les sons à identité de la bibliothèque',
        () async {
      final libraryId = await insertLibrary();
      await dataSource.syncLibrarySoundFromDriveIndex(
        libraryId: libraryId,
        relativePath: 'a.mp3',
        localPath: '/cache/a.mp3',
        driveFileId: 'F1',
      );

      final pruned = await dataSource.pruneLibrarySoundsAbsentFromDrive(
        libraryId: libraryId,
        keptDriveFileIds: const {},
      );

      expect(pruned, ['a.mp3']);
      expect(await soundsOf(libraryId), isEmpty);
    });

    test('n\'élague pas les sons d\'une autre bibliothèque', () async {
      final libA = await insertLibrary(name: 'A', root: '/a');
      final libB = await insertLibrary(name: 'B', root: '/b');
      await dataSource.syncLibrarySoundFromDriveIndex(
        libraryId: libA,
        relativePath: 'a.mp3',
        localPath: '/a/a.mp3',
        driveFileId: 'FA',
      );
      await dataSource.syncLibrarySoundFromDriveIndex(
        libraryId: libB,
        relativePath: 'b.mp3',
        localPath: '/b/b.mp3',
        driveFileId: 'FB',
      );

      // Scan de A qui ne remonte plus rien : B ne doit pas être touchée.
      final pruned = await dataSource.pruneLibrarySoundsAbsentFromDrive(
        libraryId: libA,
        keptDriveFileIds: const {},
      );

      expect(pruned, ['a.mp3']);
      expect(await soundsOf(libA), isEmpty);
      expect(await soundsOf(libB), hasLength(1));
    });
  });
}
