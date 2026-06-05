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

  test('mergeLibrarySnapshot importe un export sans erreur DETACH', () async {
    final libraryId = await database.into(database.libraries).insert(
          db.LibrariesCompanion.insert(
            name: 'Test Drive',
            localRootPath: p.join(tempDir.path, 'cache'),
          ),
        );

    await database.into(database.sounds).insert(
          db.SoundsCompanion.insert(
            title: 'clap.wav',
            filePath: '/cache/clap.wav',
            type: SoundType.soundEffect,
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
  });
}
