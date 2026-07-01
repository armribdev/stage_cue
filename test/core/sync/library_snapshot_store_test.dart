import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/core/database/sounds.dart' show SoundType;
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

  test('mergeLibrarySnapshot recalcule filePath depuis relativePath local', () async {
    const localRoot = '/device/cache';
    final libraryId = await database.into(database.libraries).insert(
          db.LibrariesCompanion.insert(
            name: 'Test Drive',
            localRootPath: localRoot,
          ),
        );

    await database.into(database.sounds).insert(
          db.SoundsCompanion.insert(
            title: 'clap.wav',
            filePath: '/other/device/cache/clap.wav',
            type: const Value(SoundType.soundEffect),
            libraryId: Value(libraryId),
            relativePath: const Value('clap.wav'),
          ),
        );

    final snapshotPath = p.join(tempDir.path, 'library.db');
    await store.exportLibrarySnapshot(libraryId, snapshotPath);

    await (database.delete(database.sounds)
          ..where((s) => s.libraryId.equals(libraryId)))
        .go();

    await store.mergeLibrarySnapshot(libraryId, snapshotPath);

    final sounds = await (database.select(database.sounds)
          ..where((s) => s.libraryId.equals(libraryId)))
        .get();

    expect(sounds, hasLength(1));
    expect(sounds.first.title, 'clap.wav');
    expect(
      sounds.first.filePath,
      p.join(localRoot, 'clap.wav'),
    );
    expect(sounds.first.relativePath, 'clap.wav');
  });

  test('le round-trip snapshot préserve driveFileId (identité forte)', () async {
    const localRoot = '/device/cache';
    final libraryId = await database.into(database.libraries).insert(
          db.LibrariesCompanion.insert(
            name: 'Test Drive',
            localRootPath: localRoot,
          ),
        );

    await database.into(database.sounds).insert(
          db.SoundsCompanion.insert(
            title: 'clap.wav',
            filePath: '/other/device/cache/clap.wav',
            type: const Value(SoundType.soundEffect),
            libraryId: Value(libraryId),
            relativePath: const Value('clap.wav'),
            driveFileId: const Value('DRIVE_ID_42'),
          ),
        );

    final snapshotPath = p.join(tempDir.path, 'library.db');
    await store.exportLibrarySnapshot(libraryId, snapshotPath);

    await (database.delete(database.sounds)
          ..where((s) => s.libraryId.equals(libraryId)))
        .go();

    await store.mergeLibrarySnapshot(libraryId, snapshotPath);

    final sounds = await (database.select(database.sounds)
          ..where((s) => s.libraryId.equals(libraryId)))
        .get();

    expect(sounds, hasLength(1));
    expect(sounds.first.driveFileId, 'DRIVE_ID_42');
  });

  test('mergeLibrarySnapshot normalise relativePath legacy sounds/', () async {
    const localRoot = '/device/cache';
    final libraryId = await database.into(database.libraries).insert(
          db.LibrariesCompanion.insert(
            name: 'Test Drive',
            localRootPath: localRoot,
          ),
        );

    // Simule un snapshot exporté avec un chemin legacy.
    final legacyDb = db.AppDatabase.forTesting(NativeDatabase.memory());
    final legacyLibraryId = await legacyDb.into(legacyDb.libraries).insert(
          db.LibrariesCompanion.insert(
            name: 'Legacy',
            localRootPath: '/old/cache',
          ),
        );
    await legacyDb.into(legacyDb.sounds).insert(
          db.SoundsCompanion.insert(
            title: 'Pistolet 4',
            filePath: '/old/cache/sounds/Pistolet 4.mp3',
            type: const Value(SoundType.soundEffect),
            libraryId: Value(legacyLibraryId),
            relativePath: const Value('sounds/Pistolet 4.mp3'),
          ),
        );
    final snapshotPath = p.join(tempDir.path, 'legacy-library.db');
    await LibrarySnapshotStore(legacyDb)
        .exportLibrarySnapshot(legacyLibraryId, snapshotPath);
    await legacyDb.close();

    await store.mergeLibrarySnapshot(libraryId, snapshotPath);

    final sounds = await (database.select(database.sounds)
          ..where((s) => s.libraryId.equals(libraryId)))
        .get();

    expect(sounds, hasLength(1));
    expect(sounds.first.relativePath, 'Pistolet 4.mp3');
    expect(
      sounds.first.filePath,
      p.join(localRoot, 'Pistolet 4.mp3'),
    );
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
}
