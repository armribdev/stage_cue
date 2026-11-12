import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/features/sampler/data/datasources/local_pad_datasource.dart';

void main() {
  late db.AppDatabase database;
  late LocalPadDataSource dataSource;

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    dataSource = LocalPadDataSource(database);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'deletePad purge les pad_sounds du pad et laisse ceux des autres',
    () async {
      final boardId = await database
          .into(database.soundBoards)
          .insert(db.SoundBoardsCompanion.insert(name: 'Scène'));
      final soundId = await database
          .into(database.sounds)
          .insert(
            db.SoundsCompanion.insert(
              title: 'a',
              displayName: 'a',
              filePath: '/x/a.mp3',
            ),
          );
      final removed = await dataSource.createPad(boardId, soundId);
      final kept = await dataSource.createPad(boardId, soundId);

      await dataSource.deletePad(removed);

      final rows = await database.select(database.padSounds).get();
      expect(rows.map((r) => r.padId), [kept]);
      final pads = await database.select(database.pads).get();
      expect(pads.map((p) => p.id), [kept]);
    },
  );

  group('un pad sans son ne peut pas exister', () {
    test('createPadWithSettings refuse une liste de sons vide', () async {
      final boardId = await database
          .into(database.soundBoards)
          .insert(db.SoundBoardsCompanion.insert(name: 'Scène'));

      await expectLater(
        dataSource.createPadWithSettings(boardId: boardId, soundIds: const []),
        throwsArgumentError,
      );
      expect(await database.select(database.pads).get(), isEmpty);
    });

    test('getBoardPads ignore un pad resté vide en base', () async {
      final boardId = await database
          .into(database.soundBoards)
          .insert(db.SoundBoardsCompanion.insert(name: 'Scène'));
      final soundId = await database
          .into(database.sounds)
          .insert(
            db.SoundsCompanion.insert(
              title: 'a',
              displayName: 'a',
              filePath: '/x/a.mp3',
            ),
          );
      final kept = await dataSource.createPad(boardId, soundId);
      await database
          .into(database.pads)
          .insert(db.PadsCompanion.insert(boardId: boardId));

      final pads = await dataSource.getBoardPads(boardId);

      expect(pads.map((p) => p.id), [kept]);
    });
  });
}
