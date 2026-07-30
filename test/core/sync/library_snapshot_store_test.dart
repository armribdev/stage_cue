import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/core/sync/library_snapshot_store.dart';

void main() {
  late Directory tempDir;
  late db.AppDatabase database;
  late LibrarySnapshotStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('stage_cue_snap_test_');
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    store = LibrarySnapshotStore(database);
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('snapshot racine : boards recâblés sur les sons par driveFileId',
      () async {
    // Device A : bibliothèque + son (driveFileId DF1) + board/pad le référençant.
    final lib = await database.into(database.libraries).insert(
          db.LibrariesCompanion.insert(name: 'A', localRootPath: '/A'),
        );
    final folder = await database.into(database.libraryFolders).insert(
          db.LibraryFoldersCompanion.insert(
            libraryId: lib,
            driveFolderId: 'F',
            relativePath: const Value(''),
          ),
        );
    final soundId = await database.into(database.sounds).insert(
          db.SoundsCompanion.insert(
            title: 'knock',
            filePath: '/A/knock.mp3',
            libraryId: Value(lib),
            relativePath: const Value('knock.mp3'),
            driveFileId: const Value('DF1'),
            folderId: Value(folder),
          ),
        );
    final boardId = await database.into(database.soundBoards).insert(
          db.SoundBoardsCompanion.insert(name: 'Scène', libraryId: Value(lib)),
        );
    final padId = await database.into(database.pads).insert(
          db.PadsCompanion.insert(boardId: boardId, name: const Value('Pad 1')),
        );
    await database.into(database.padSounds).insert(
          db.PadSoundsCompanion.insert(padId: padId, soundId: soundId),
        );

    final snapshotPath = p.join(tempDir.path, 'root.db');
    await store.exportLibrarySnapshot(lib, snapshotPath);

    // Device B : mêmes son/biblio mais ids locaux DÉCALÉS (son bidon d'abord).
    final dbB = db.AppDatabase.forTesting(NativeDatabase.memory());
    final libB = await dbB.into(dbB.libraries).insert(
          db.LibrariesCompanion.insert(name: 'A', localRootPath: '/B'),
        );
    final folderB = await dbB.into(dbB.libraryFolders).insert(
          db.LibraryFoldersCompanion.insert(
            libraryId: libB,
            driveFolderId: 'F',
            relativePath: const Value(''),
          ),
        );
    await dbB.into(dbB.sounds).insert(
          db.SoundsCompanion.insert(title: 'bidon', filePath: '/B/x.mp3'),
        );
    final soundBId = await dbB.into(dbB.sounds).insert(
          db.SoundsCompanion.insert(
            title: 'knock',
            filePath: '/B/knock.mp3',
            libraryId: Value(libB),
            relativePath: const Value('knock.mp3'),
            driveFileId: const Value('DF1'),
            folderId: Value(folderB),
          ),
        );
    expect(soundBId, isNot(soundId), reason: 'ids locaux différents entre appareils');

    await LibrarySnapshotStore(dbB).mergeLibrarySnapshot(libB, snapshotPath);

    final boards = await (dbB.select(dbB.soundBoards)
          ..where((b) => b.libraryId.equals(libB)))
        .get();
    expect(boards, hasLength(1));
    expect(boards.first.name, 'Scène');

    final padSounds = await dbB.select(dbB.padSounds).get();
    expect(padSounds, hasLength(1));
    expect(
      padSounds.first.soundId,
      soundBId,
      reason: 'le pad est recâblé sur le son local via driveFileId',
    );
    await dbB.close();
  });

  test('snapshot racine : pad recâblé par relativePath quand driveFileId manque',
      () async {
    // Device A : son SANS driveFileId (ex. non encore réconcilié avec l'index
    // Drive) mais avec un relativePath portable, référencé par un pad.
    final lib = await database.into(database.libraries).insert(
          db.LibrariesCompanion.insert(name: 'A', localRootPath: '/A'),
        );
    final soundId = await database.into(database.sounds).insert(
          db.SoundsCompanion.insert(
            title: 'knock',
            filePath: '/A/knock.mp3',
            libraryId: Value(lib),
            relativePath: const Value('knock.mp3'),
          ),
        );
    final boardId = await database.into(database.soundBoards).insert(
          db.SoundBoardsCompanion.insert(name: 'Scène', libraryId: Value(lib)),
        );
    final padId = await database.into(database.pads).insert(
          db.PadsCompanion.insert(boardId: boardId, name: const Value('Pad 1')),
        );
    await database.into(database.padSounds).insert(
          db.PadSoundsCompanion.insert(padId: padId, soundId: soundId),
        );

    final snapshotPath = p.join(tempDir.path, 'root.db');
    await store.exportLibrarySnapshot(lib, snapshotPath);

    // Device B : même son (par relativePath), id local décalé, driveFileId null.
    final dbB = db.AppDatabase.forTesting(NativeDatabase.memory());
    final libB = await dbB.into(dbB.libraries).insert(
          db.LibrariesCompanion.insert(name: 'A', localRootPath: '/B'),
        );
    await dbB.into(dbB.sounds).insert(
          db.SoundsCompanion.insert(title: 'bidon', filePath: '/B/x.mp3'),
        );
    final soundBId = await dbB.into(dbB.sounds).insert(
          db.SoundsCompanion.insert(
            title: 'knock',
            filePath: '/B/knock.mp3',
            libraryId: Value(libB),
            relativePath: const Value('knock.mp3'),
          ),
        );

    await LibrarySnapshotStore(dbB).mergeLibrarySnapshot(libB, snapshotPath);

    final padSounds = await dbB.select(dbB.padSounds).get();
    expect(padSounds, hasLength(1), reason: 'le pad n\'est pas perdu');
    expect(
      padSounds.first.soundId,
      soundBId,
      reason: 'recâblé sur le son local via relativePath (repli)',
    );
    await dbB.close();
  });

  group('snapshot par-dossier', () {
    test('round-trip : chemins folder-relative reconstruits dans le nœud cible',
        () async {
      // Device A : racine liée à xx/, nœud dossier yy (relativePath 'yy').
      final libA = await database.into(database.libraries).insert(
            db.LibrariesCompanion.insert(name: 'A', localRootPath: '/A/cache'),
          );
      final folderA = await database.into(database.libraryFolders).insert(
            db.LibraryFoldersCompanion.insert(
              libraryId: libA,
              driveFolderId: 'FOLDER_YY',
              relativePath: const Value('yy'),
            ),
          );
      await database.into(database.sounds).insert(
            db.SoundsCompanion.insert(
              title: 'knock',
              filePath: '/A/cache/yy/knock.mp3',
              libraryId: Value(libA),
              relativePath: const Value('yy/knock.mp3'),
              driveFileId: const Value('F1'),
              folderId: Value(folderA),
            ),
          );

      final snapshotPath = p.join(tempDir.path, 'folder.db');
      await store.exportFolderSnapshot(folderA, snapshotPath);

      // Device B : a lié yy/ directement → nœud avec relativePath '' et autre cache.
      final dbB = db.AppDatabase.forTesting(NativeDatabase.memory());
      final libB = await dbB.into(dbB.libraries).insert(
            db.LibrariesCompanion.insert(name: 'B', localRootPath: '/B/cache'),
          );
      final folderB = await dbB.into(dbB.libraryFolders).insert(
            db.LibraryFoldersCompanion.insert(
              libraryId: libB,
              driveFolderId: 'FOLDER_YY',
              relativePath: const Value(''),
            ),
          );
      await LibrarySnapshotStore(dbB)
          .mergeFolderSnapshot(folderB, snapshotPath);

      final sounds = await (dbB.select(dbB.sounds)
            ..where((s) => s.folderId.equals(folderB)))
          .get();
      expect(sounds, hasLength(1));
      expect(sounds.first.relativePath, 'knock.mp3');
      expect(sounds.first.filePath, p.join('/B/cache', 'knock.mp3'));
      expect(sounds.first.driveFileId, 'F1');
      await dbB.close();
    });

    test('upsert préserve l\'id du son (liens pad intacts)', () async {
      final lib = await database.into(database.libraries).insert(
            db.LibrariesCompanion.insert(name: 'A', localRootPath: '/cache'),
          );
      final folder = await database.into(database.libraryFolders).insert(
            db.LibraryFoldersCompanion.insert(
              libraryId: lib,
              driveFolderId: 'F',
              relativePath: const Value(''),
            ),
          );
      final soundId = await database.into(database.sounds).insert(
            db.SoundsCompanion.insert(
              title: 'knock',
              filePath: '/cache/knock.mp3',
              libraryId: Value(lib),
              relativePath: const Value('knock.mp3'),
              driveFileId: const Value('F1'),
              folderId: Value(folder),
            ),
          );

      final boardId = await database.into(database.soundBoards).insert(
            db.SoundBoardsCompanion.insert(name: 'Board', libraryId: Value(lib)),
          );
      final padId = await database.into(database.pads).insert(
            db.PadsCompanion.insert(boardId: boardId),
          );
      await database.into(database.padSounds).insert(
            db.PadSoundsCompanion.insert(padId: padId, soundId: soundId),
          );

      final snapshotPath = p.join(tempDir.path, 'folder.db');
      await store.exportFolderSnapshot(folder, snapshotPath);
      await store.mergeFolderSnapshot(folder, snapshotPath);

      final sounds = await (database.select(database.sounds)
            ..where((s) => s.folderId.equals(folder)))
          .get();
      expect(sounds, hasLength(1));
      expect(sounds.first.id, soundId, reason: 'upsert conserve la ligne');

      final padSounds = await database.select(database.padSounds).get();
      expect(padSounds, hasLength(1));
      expect(padSounds.first.soundId, soundId);
    });

    test('supprime les sons absents du snapshot (retirés côté distant)',
        () async {
      final lib = await database.into(database.libraries).insert(
            db.LibrariesCompanion.insert(name: 'A', localRootPath: '/cache'),
          );
      final folder = await database.into(database.libraryFolders).insert(
            db.LibraryFoldersCompanion.insert(
              libraryId: lib,
              driveFolderId: 'F',
              relativePath: const Value(''),
            ),
          );
      await database.into(database.sounds).insert(
            db.SoundsCompanion.insert(
              title: 'a',
              filePath: '/cache/a.mp3',
              libraryId: Value(lib),
              relativePath: const Value('a.mp3'),
              driveFileId: const Value('F1'),
              folderId: Value(folder),
            ),
          );

      final snapshotPath = p.join(tempDir.path, 'folder.db');
      await store.exportFolderSnapshot(folder, snapshotPath);

      // Ajout local APRÈS l'export : absent du snapshot distant.
      await database.into(database.sounds).insert(
            db.SoundsCompanion.insert(
              title: 'b',
              filePath: '/cache/b.mp3',
              libraryId: Value(lib),
              relativePath: const Value('b.mp3'),
              driveFileId: const Value('F2'),
              folderId: Value(folder),
            ),
          );

      await store.mergeFolderSnapshot(folder, snapshotPath);

      final sounds = await (database.select(database.sounds)
            ..where((s) => s.folderId.equals(folder)))
          .get();
      expect(sounds, hasLength(1));
      expect(sounds.first.driveFileId, 'F1');
    });
  });

  group('fusion intelligente des boards', () {
    // Crée un son de bibliothèque référençable par un pad (identité DF1).
    Future<int> seedSound(db.AppDatabase d, int lib) {
      return d.into(d.sounds).insert(
            db.SoundsCompanion.insert(
              title: 'knock',
              filePath: '/knock.mp3',
              libraryId: Value(lib),
              relativePath: const Value('knock.mp3'),
              driveFileId: const Value('DF1'),
            ),
          );
    }

    Future<int> seedBoard(
      db.AppDatabase d,
      int lib, {
      required String name,
      required String key,
      required DateTime updatedAt,
      required int soundId,
      String? padName,
    }) async {
      final boardId = await d.into(d.soundBoards).insert(
            db.SoundBoardsCompanion.insert(
              name: name,
              libraryId: Value(lib),
              boardKey: Value(key),
              updatedAt: Value(updatedAt),
            ),
          );
      final padId = await d.into(d.pads).insert(
            db.PadsCompanion.insert(
              boardId: boardId,
              name: Value(padName ?? name),
            ),
          );
      await d.into(d.padSounds).insert(
            db.PadSoundsCompanion.insert(padId: padId, soundId: soundId),
          );
      return boardId;
    }

    test('préserve une scène éditée en parallèle (deux régisseurs)', () async {
      // Device A : bibliothèque avec la scène « Forêt ».
      final libA = await database.into(database.libraries).insert(
            db.LibrariesCompanion.insert(name: 'A', localRootPath: '/A'),
          );
      final soundA = await seedSound(database, libA);
      await seedBoard(database, libA,
          name: 'Forêt', key: 'KF', updatedAt: DateTime(2026, 1, 1),
          soundId: soundA);

      final snapshotPath = p.join(tempDir.path, 'root.db');
      await store.exportLibrarySnapshot(libA, snapshotPath);

      // Device B : MÊME bibliothèque mais l'opérateur y a créé « Ville »
      // (absente du snapshot de A).
      final dbB = db.AppDatabase.forTesting(NativeDatabase.memory());
      final libB = await dbB.into(dbB.libraries).insert(
            db.LibrariesCompanion.insert(name: 'A', localRootPath: '/B'),
          );
      final soundB = await seedSound(dbB, libB);
      await seedBoard(dbB, libB,
          name: 'Ville', key: 'KV', updatedAt: DateTime(2026, 1, 2),
          soundId: soundB);

      await LibrarySnapshotStore(dbB).mergeLibrarySnapshot(libB, snapshotPath);

      final boards = await (dbB.select(dbB.soundBoards)
            ..where((b) => b.libraryId.equals(libB)))
          .get();
      final names = boards.map((b) => b.name).toSet();
      expect(names, {'Forêt', 'Ville'},
          reason: 'la scène locale « Ville » n\'est pas écrasée par la fusion');
      await dbB.close();
    });

    test('même scène : la version distante plus récente gagne', () async {
      final libA = await database.into(database.libraries).insert(
            db.LibrariesCompanion.insert(name: 'A', localRootPath: '/A'),
          );
      final soundA = await seedSound(database, libA);
      await seedBoard(database, libA,
          name: 'Scène (A)', key: 'KS', updatedAt: DateTime(2026, 1, 3),
          soundId: soundA, padName: 'PadA');

      final snapshotPath = p.join(tempDir.path, 'root.db');
      await store.exportLibrarySnapshot(libA, snapshotPath);

      final dbB = db.AppDatabase.forTesting(NativeDatabase.memory());
      final libB = await dbB.into(dbB.libraries).insert(
            db.LibrariesCompanion.insert(name: 'A', localRootPath: '/B'),
          );
      final soundB = await seedSound(dbB, libB);
      await seedBoard(dbB, libB,
          name: 'Scène (B)', key: 'KS', updatedAt: DateTime(2026, 1, 1),
          soundId: soundB, padName: 'PadB');

      await LibrarySnapshotStore(dbB).mergeLibrarySnapshot(libB, snapshotPath);

      final boards = await (dbB.select(dbB.soundBoards)
            ..where((b) => b.libraryId.equals(libB)))
          .get();
      expect(boards, hasLength(1), reason: 'pas de doublon : même board_key');
      expect(boards.first.name, 'Scène (A)');
      final pads = await (dbB.select(dbB.pads)
            ..where((pd) => pd.boardId.equals(boards.first.id)))
          .get();
      expect(pads.single.name, 'PadA', reason: 'contenu remplacé par le distant');
      await dbB.close();
    });

    test('même scène : le local plus récent n\'est pas écrasé', () async {
      final libA = await database.into(database.libraries).insert(
            db.LibrariesCompanion.insert(name: 'A', localRootPath: '/A'),
          );
      final soundA = await seedSound(database, libA);
      await seedBoard(database, libA,
          name: 'Scène (A)', key: 'KS', updatedAt: DateTime(2026, 1, 1),
          soundId: soundA, padName: 'PadA');

      final snapshotPath = p.join(tempDir.path, 'root.db');
      await store.exportLibrarySnapshot(libA, snapshotPath);

      final dbB = db.AppDatabase.forTesting(NativeDatabase.memory());
      final libB = await dbB.into(dbB.libraries).insert(
            db.LibrariesCompanion.insert(name: 'A', localRootPath: '/B'),
          );
      final soundB = await seedSound(dbB, libB);
      await seedBoard(dbB, libB,
          name: 'Scène (B)', key: 'KS', updatedAt: DateTime(2026, 1, 5),
          soundId: soundB, padName: 'PadB');

      await LibrarySnapshotStore(dbB).mergeLibrarySnapshot(libB, snapshotPath);

      final boards = await (dbB.select(dbB.soundBoards)
            ..where((b) => b.libraryId.equals(libB)))
          .get();
      expect(boards, hasLength(1));
      expect(boards.first.name, 'Scène (B)', reason: 'local plus récent conservé');
      final pads = await (dbB.select(dbB.pads)
            ..where((pd) => pd.boardId.equals(boards.first.id)))
          .get();
      expect(pads.single.name, 'PadB');
      await dbB.close();
    });
  });

  group('vue partagée', () {
    test('un board recâble un son partagé possédé par une AUTRE bibliothèque',
        () async {
      // Device A : deux bibliothèques. Le son « rain » (driveFileId DFX) est
      // possédé par libA (home), mais un board de libB le référence — cas d'un
      // dossier recouvert vu par les deux.
      final libA = await database.into(database.libraries).insert(
            db.LibrariesCompanion.insert(name: 'A', localRootPath: '/A'),
          );
      final libB = await database.into(database.libraries).insert(
            db.LibrariesCompanion.insert(name: 'B', localRootPath: '/B'),
          );
      final sharedSound = await database.into(database.sounds).insert(
            db.SoundsCompanion.insert(
              title: 'rain',
              filePath: '/A/rain.mp3',
              libraryId: Value(libA),
              relativePath: const Value('rain.mp3'),
              driveFileId: const Value('DFX'),
            ),
          );
      final boardId = await database.into(database.soundBoards).insert(
            db.SoundBoardsCompanion.insert(
              name: 'Ville',
              libraryId: Value(libB),
              boardKey: const Value('KV'),
            ),
          );
      final padId = await database.into(database.pads).insert(
            db.PadsCompanion.insert(boardId: boardId),
          );
      await database.into(database.padSounds).insert(
            db.PadSoundsCompanion.insert(padId: padId, soundId: sharedSound),
          );

      final snapshotPath = p.join(tempDir.path, 'root.db');
      await store.exportLibrarySnapshot(libB, snapshotPath);

      // Device 2 : le son partagé appartient encore à A (ids décalés), libB tire
      // son board racine. Le recâblage doit résoudre par driveFileId GLOBAL.
      final dbB = db.AppDatabase.forTesting(NativeDatabase.memory());
      final a2 = await dbB.into(dbB.libraries).insert(
            db.LibrariesCompanion.insert(name: 'A', localRootPath: '/A2'),
          );
      final b2 = await dbB.into(dbB.libraries).insert(
            db.LibrariesCompanion.insert(name: 'B', localRootPath: '/B2'),
          );
      await dbB.into(dbB.sounds).insert(
            db.SoundsCompanion.insert(title: 'bidon', filePath: '/x.mp3'),
          );
      final shared2 = await dbB.into(dbB.sounds).insert(
            db.SoundsCompanion.insert(
              title: 'rain',
              filePath: '/A2/rain.mp3',
              libraryId: Value(a2),
              relativePath: const Value('rain.mp3'),
              driveFileId: const Value('DFX'),
            ),
          );

      await LibrarySnapshotStore(dbB).mergeLibrarySnapshot(b2, snapshotPath);

      final padSounds = await dbB.select(dbB.padSounds).get();
      expect(padSounds, hasLength(1), reason: 'le pad n\'est pas perdu');
      expect(
        padSounds.first.soundId,
        shared2,
        reason: 'board de B recâblé sur le son partagé possédé par A '
            '(driveFileId global, pas de scope libraryId)',
      );
      await dbB.close();
    });
  });

  group('board_key : identité GLOBALE', () {
    /// Exporte un snapshot racine contenant un board de clé [boardKey].
    Future<String> exportBoardSnapshot(String boardKey, String name) async {
      final lib = await database.into(database.libraries).insert(
            db.LibrariesCompanion.insert(name: 'src', localRootPath: '/src'),
          );
      await database.into(database.soundBoards).insert(
            db.SoundBoardsCompanion.insert(
              name: name,
              libraryId: Value(lib),
              boardKey: Value(boardKey),
              updatedAt: Value(DateTime(2026, 3)),
            ),
          );
      final path = p.join(tempDir.path, 'root_$boardKey.db');
      await store.exportLibrarySnapshot(lib, path);
      return path;
    }

    test('un board de MÊME clé dans une AUTRE bibliothèque ne fait pas planter '
        'la fusion', () async {
      const key = '3c27f4c7-d331-4b51-930d-db87c437fec0';
      final snapshotPath = await exportBoardSnapshot(key, 'Armand');

      // Appareil cible : le board existe déjà sous une PREMIÈRE bibliothèque
      // (deux liens Drive qui recouvrent la même racine, cf. décision 0003).
      final dbB = db.AppDatabase.forTesting(NativeDatabase.memory());
      final libA = await dbB.into(dbB.libraries).insert(
            db.LibrariesCompanion.insert(name: 'A', localRootPath: '/A'),
          );
      await dbB.into(dbB.soundBoards).insert(
            db.SoundBoardsCompanion.insert(
              name: 'Armand',
              libraryId: Value(libA),
              boardKey: const Value(key),
              updatedAt: Value(DateTime(2026)),
            ),
          );
      // Puis on lie une SECONDE bibliothèque et on y fusionne le même snapshot.
      final libB = await dbB.into(dbB.libraries).insert(
            db.LibrariesCompanion.insert(name: 'B', localRootPath: '/B'),
          );

      // Sans correctif : UNIQUE constraint failed sur sound_boards.board_key,
      // l'ajout du dossier Drive échoue entièrement.
      await LibrarySnapshotStore(dbB).mergeLibrarySnapshot(libB, snapshotPath);

      final boards = await dbB.select(dbB.soundBoards).get();
      expect(boards, hasLength(1),
          reason: 'la clé étant globale, le board ne doit pas être dupliqué');
      expect(boards.single.libraryId, libA,
          reason: 'un board possédé ailleurs n\'est pas confisqué');
      await dbB.close();
    });

    test('un board LOCAL (sans bibliothèque) de même clé est adopté, pas '
        'dupliqué', () async {
      const key = '9f14b0a2-0000-4000-8000-000000000001';
      final snapshotPath = await exportBoardSnapshot(key, 'Scène distante');

      final dbB = db.AppDatabase.forTesting(NativeDatabase.memory());
      // `library_id = null` = scène locale non synchronisée (cf. SoundBoards).
      await dbB.into(dbB.soundBoards).insert(
            db.SoundBoardsCompanion.insert(
              name: 'Scène locale',
              boardKey: const Value(key),
              updatedAt: Value(DateTime(2026)),
            ),
          );
      final libB = await dbB.into(dbB.libraries).insert(
            db.LibrariesCompanion.insert(name: 'B', localRootPath: '/B'),
          );

      await LibrarySnapshotStore(dbB).mergeLibrarySnapshot(libB, snapshotPath);

      final boards = await dbB.select(dbB.soundBoards).get();
      expect(boards, hasLength(1));
      expect(boards.single.libraryId, libB,
          reason: 'un board sans propriétaire rejoint la bibliothèque tirée');
      expect(boards.single.name, 'Scène distante',
          reason: 'le distant est plus récent : il gagne');
      await dbB.close();
    });

    test('un board local PLUS RÉCENT est rattaché quand même, sinon sa version '
        'ne serait jamais repoussée', () async {
      const key = '9f14b0a2-0000-4000-8000-000000000002';
      final snapshotPath = await exportBoardSnapshot(key, 'Ancienne version');

      final dbB = db.AppDatabase.forTesting(NativeDatabase.memory());
      await dbB.into(dbB.soundBoards).insert(
            db.SoundBoardsCompanion.insert(
              name: 'Version locale récente',
              boardKey: const Value(key),
              // Postérieur au snapshot (exporté à 2026-03) : le local gagne.
              updatedAt: Value(DateTime(2026, 6)),
            ),
          );
      final libB = await dbB.into(dbB.libraries).insert(
            db.LibrariesCompanion.insert(name: 'B', localRootPath: '/B'),
          );

      await LibrarySnapshotStore(dbB).mergeLibrarySnapshot(libB, snapshotPath);

      final board = (await dbB.select(dbB.soundBoards).get()).single;
      expect(board.name, 'Version locale récente',
          reason: 'le contenu local, plus récent, est conservé');
      // Le rattachement est INDÉPENDANT de l'arbitrage de contenu :
      // `exportLibrarySnapshot` filtre sur `library_id`, donc un board resté
      // orphelin ne serait jamais republié — sa version gagnante serait perdue.
      expect(board.libraryId, libB);
      await dbB.close();
    });
  });
}
