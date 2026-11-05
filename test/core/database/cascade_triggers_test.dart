// Les `onDelete: cascade` déclarés ne s'exécutent pas (clés étrangères
// désactivées) : des déclencheurs SQLite les émulent. Ces tests suivent chaque
// relation émulée ; retirer une bibliothèque détache ses scènes sans les
// supprimer.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/database/database.dart' as db;

void main() {
  late db.AppDatabase database;

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<int> count(String table, [String where = '1 = 1']) async {
    final row = await database
        .customSelect('SELECT COUNT(*) AS c FROM $table WHERE $where')
        .getSingle();
    return row.read<int>('c');
  }

  Future<void> seed() async {
    await database.customStatement(
      "INSERT INTO sounds (title, file_path, display_name) "
      "VALUES ('a', '/a.wav', 'a'), ('b', '/b.wav', 'b')",
    );
    await database.customStatement(
      "INSERT INTO sound_boards (name) VALUES ('S1'), ('S2')",
    );
    await database.customStatement(
      'INSERT INTO pads (board_id) VALUES (1), (1), (2)',
    );
    await database.customStatement(
      'INSERT INTO pad_sounds (pad_id, sound_id) '
      'VALUES (1, 1), (2, 2), (3, 1), (3, 2)',
    );
    await database.customStatement(
      'INSERT INTO sound_tags (sound_id, tag_id) VALUES (1, 1), (2, 1)',
    );
    await database.customStatement(
      'INSERT INTO sound_auto_tags (sound_id, tag_id, score, updated_at) '
      'VALUES (1, 1, 0.5, 0), (2, 1, 0.5, 0)',
    );
  }

  test('supprimer une scène supprime ses pads et leurs pad_sounds', () async {
    await seed();

    await database.customStatement('DELETE FROM sound_boards WHERE id = 1');

    expect(await count('pads'), 1);
    expect(await count('pad_sounds'), 2, reason: 'ceux du pad 3 restent');
    expect(await count('pad_sounds', 'pad_id IN (1, 2)'), 0);
  });

  test('supprimer un son retire ses pad_sounds, tags et suggestions', () async {
    await seed();

    await database.customStatement('DELETE FROM sounds WHERE id = 1');

    expect(await count('pad_sounds', 'sound_id = 1'), 0);
    expect(await count('sound_tags', 'sound_id = 1'), 0);
    expect(await count('sound_auto_tags', 'sound_id = 1'), 0);
    expect(await count('pad_sounds'), 2);
    expect(await count('sound_tags'), 1);
    expect(await count('pads'), 3, reason: 'les pads eux-mêmes restent');
  });

  test('supprimer un tag retire ses liens et ses alias', () async {
    await seed();
    await database.customStatement(
      "INSERT INTO tag_aliases (tag_id, alias, normalized_alias) "
      "VALUES (1, 'zzz-test', 'zzz-test')",
    );
    expect(await count('tag_aliases', "normalized_alias = 'zzz-test'"), 1);

    await database.customStatement('DELETE FROM tags WHERE id = 1');

    expect(await count('sound_tags'), 0);
    expect(await count('sound_auto_tags'), 0);
    expect(await count('tag_aliases', 'tag_id = 1'), 0);
    expect(await count('sounds'), 2);
  });

  test(
    'retirer une bibliothèque rend ses scènes locales, sans les perdre',
    () async {
      await database.customStatement(
        "INSERT INTO libraries (name, local_root_path) "
        "VALUES ('L1', '/l1'), ('L2', '/l2')",
      );
      await database.customStatement(
        "INSERT INTO sound_boards (name, library_id) VALUES ('S1', 1), ('S2', 2)",
      );
      await database.customStatement('INSERT INTO pads (board_id) VALUES (1)');

      await database.customStatement('DELETE FROM libraries WHERE id = 1');

      expect(await count('sound_boards'), 2);
      expect(await count('sound_boards', 'library_id IS NULL'), 1);
      expect(await count('sound_boards', 'library_id = 2'), 1);
      expect(await count('pads'), 1, reason: 'la mise en page est conservée');
    },
  );

  test('retirer une bibliothèque purge ses dossiers et appartenances, '
      'épargne ceux des autres', () async {
    await database.customStatement(
      "INSERT INTO libraries (name, local_root_path) "
      "VALUES ('L1', '/l1'), ('L2', '/l2')",
    );
    // Dossier 1 possédé par L1, vu par L2 ; dossier 2 possédé par L2.
    await database.customStatement(
      "INSERT INTO library_folders (library_id, drive_folder_id) "
      "VALUES (1, 'f1'), (2, 'f2')",
    );
    await database.customStatement(
      'INSERT INTO folder_memberships (library_id, folder_id) '
      'VALUES (1, 1), (2, 1), (2, 2)',
    );

    await database.customStatement('DELETE FROM libraries WHERE id = 1');

    expect(await count('library_folders'), 1);
    expect(await count('library_folders', 'library_id = 2'), 1);
    final memberships = await database
        .customSelect('SELECT library_id, folder_id FROM folder_memberships')
        .get();
    expect(
      memberships.map(
        (r) => (r.read<int>('library_id'), r.read<int>('folder_id')),
      ),
      [(2, 2)],
    );
  });

  test('les déclencheurs manquants sont recréés à l\'ouverture', () async {
    final dir = await Directory.systemTemp.createTemp('stagecue_triggers');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/test.sqlite');

    var fileDb = db.AppDatabase.forTesting(NativeDatabase(file));
    await fileDb.customStatement('DROP TRIGGER trg_pads_delete_pad_sounds');
    await fileDb.close();

    fileDb = db.AppDatabase.forTesting(NativeDatabase(file));
    final rows = await fileDb
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'trigger' "
          "AND name = 'trg_pads_delete_pad_sounds'",
        )
        .get();
    expect(rows, hasLength(1));
    await fileDb.close();
  });
}
