// Multipads enregistrés (décision 0051) : un modèle garde ses sons dans
// l'ordre, se modifie et se supprime sans toucher aux pads posés, et suit la
// suppression d'un son de la bibliothèque.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/features/sampler/data/datasources/local_sound_datasource.dart';
import 'package:stage_cue/features/sampler/domain/entities/pad.dart';

void main() {
  late db.AppDatabase database;
  late LocalSavedMultipadDataSource source;

  setUp(() async {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    source = LocalSavedMultipadDataSource(database);
    await database.customStatement(
      "INSERT INTO sounds (title, file_path, display_name) VALUES "
      "('a', '/a.wav', 'Porte A'), ('b', '/b.wav', 'Porte B'), "
      "('c', '/c.wav', 'Porte C')",
    );
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

  test('un modèle garde nom, couleur, mode et sons dans l\'ordre', () async {
    final id = await source.create(
      name: 'Porte qui grince',
      soundIds: [3, 1, 2],
      colorValue: 0xFF112233,
      playMode: PadPlayMode.sequential,
    );

    final all = await source.getAll();
    expect(all, hasLength(1));
    final saved = all.single;
    expect(saved.id, id);
    expect(saved.name, 'Porte qui grince');
    expect(saved.colorValue, 0xFF112233);
    expect(saved.playMode, PadPlayMode.sequential);
    expect(saved.sounds.map((s) => s.id), [3, 1, 2]);
    expect(saved.sounds.first.displayName, 'Porte C');
  });

  test('chaque modèle reçoit une identité portable distincte', () async {
    await source.create(name: 'A', soundIds: [1]);
    await source.create(name: 'B', soundIds: [2]);

    final rows = await database
        .customSelect('SELECT multipad_key FROM saved_multipads')
        .get();
    final keys = rows.map((r) => r.read<String>('multipad_key')).toSet();
    expect(keys, hasLength(2));
    expect(keys, everyElement(isNotEmpty));
  });

  test(
    'libraryIdOfBoard : bibliothèque du plateau, null si local ou inconnu',
    () async {
      await database.customStatement(
        "INSERT INTO libraries (name, local_root_path) VALUES ('L', '/l')",
      );
      await database.customStatement(
        "INSERT INTO sound_boards (name, library_id) VALUES ('Drive', 1), "
        "('Local', NULL)",
      );

      expect(await source.libraryIdOfBoard(1), 1);
      expect(await source.libraryIdOfBoard(2), isNull);
      expect(await source.libraryIdOfBoard(99), isNull);
    },
  );

  test('un modèle sans son est refusé', () async {
    expect(
      () => source.create(name: 'Vide', soundIds: const []),
      throwsArgumentError,
    );
    final id = await source.create(name: 'Ok', soundIds: [1]);
    expect(
      () => source.update(id, soundIds: const []),
      throwsArgumentError,
      reason: 'vider un modèle par la mise à jour est refusé aussi',
    );
    expect((await source.getAll()).single.sounds, hasLength(1));
  });

  test('un son en double n\'est gardé qu\'une fois', () async {
    await source.create(name: 'Doublon', soundIds: [1, 2, 1]);

    expect((await source.getAll()).single.sounds.map((s) => s.id), [1, 2]);
  });

  test('update change les champs fournis, retire la couleur, remplace les '
      'sons et date la modification', () async {
    final id = await source.create(
      name: 'Avant',
      soundIds: [1, 2],
      colorValue: 0xFF000001,
    );
    await database.customStatement(
      'UPDATE saved_multipads SET updated_at = 0 WHERE id = $id',
    );

    await source.update(id, name: 'Après', soundIds: [2, 3]);
    var saved = (await source.getAll()).single;
    expect(saved.name, 'Après');
    expect(saved.colorValue, 0xFF000001, reason: 'couleur non touchée');
    expect(saved.sounds.map((s) => s.id), [2, 3]);
    final stamp = await database
        .customSelect('SELECT updated_at FROM saved_multipads WHERE id = $id')
        .getSingle();
    expect(stamp.read<int>('updated_at'), greaterThan(0));

    await source.update(id, clearColor: true, playMode: PadPlayMode.sequential);
    saved = (await source.getAll()).single;
    expect(saved.colorValue, isNull);
    expect(saved.playMode, PadPlayMode.sequential);
    expect(saved.name, 'Après');
  });

  test('getAll trie par nom sans tenir compte de la casse', () async {
    await source.create(name: 'zèbre', soundIds: [1]);
    await source.create(name: 'Alarme', soundIds: [1]);
    await source.create(name: 'moteur', soundIds: [1]);

    expect((await source.getAll()).map((m) => m.name), [
      'Alarme',
      'moteur',
      'zèbre',
    ]);
  });

  test('supprimer un modèle retire ses sons, jamais les sons eux-mêmes ni les '
      'pads posés', () async {
    final id = await source.create(name: 'Porte', soundIds: [1, 2]);
    await database.customStatement(
      "INSERT INTO sound_boards (name) VALUES ('S1')",
    );
    await database.customStatement('INSERT INTO pads (board_id) VALUES (1)');
    await database.customStatement(
      'INSERT INTO pad_sounds (pad_id, sound_id) VALUES (1, 1), (1, 2)',
    );

    await source.delete(id);

    expect(await source.getAll(), isEmpty);
    expect(await count('saved_multipad_sounds'), 0);
    expect(await count('sounds'), 3);
    expect(await count('pad_sounds'), 2, reason: 'le pad posé est une copie');
  });

  test('supprimer un son le retire des modèles, qui restent', () async {
    await source.create(name: 'Porte', soundIds: [1, 2]);

    await database.customStatement('DELETE FROM sounds WHERE id = 1');

    expect((await source.getAll()).single.sounds.map((s) => s.id), [2]);

    await database.customStatement('DELETE FROM sounds WHERE id = 2');

    final saved = (await source.getAll()).single;
    expect(saved.sounds, isEmpty, reason: 'le modèle vide reste listé');
    expect(saved.name, 'Porte');
  });
}
