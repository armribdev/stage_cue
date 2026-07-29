// Verrouille les réglages de journalisation posés par `beforeOpen`.
//
// Ce sont deux lignes invisibles dont la perte ne casse aucun test fonctionnel :
// la base retomberait silencieusement en `delete` + `synchronous = full`, et
// l'indexation Drive redeviendrait des milliers de transactions à double fsync.
// D'où un test dédié.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/database/database.dart' as db;

void main() {
  late Directory dir;
  late db.AppDatabase database;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('stagecue_journal_test');
    // Base sur FICHIER : le mode WAL n'a pas de sens sur une base mémoire
    // (SQLite y reste en `memory` sans erreur), donc un test en mémoire ne
    // prouverait rien.
    database = db.AppDatabase.forTesting(
      NativeDatabase(File('${dir.path}/test.sqlite')),
    );
  });

  tearDown(() async {
    await database.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<String> pragma(String name) async {
    final row = await database.customSelect('PRAGMA $name').getSingle();
    return row.data.values.first.toString();
  }

  test('la base sur fichier est ouverte en WAL', () async {
    expect(await pragma('journal_mode'), 'wal');
  });

  test('synchronous vaut NORMAL (1) et non FULL (2)', () async {
    expect(await pragma('synchronous'), '1');
  });
}
