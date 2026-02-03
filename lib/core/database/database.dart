import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'sounds.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Sounds, SoundBoards, WatchedPaths, BoardSounds])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          // 1. Créer la nouvelle table WatchedPaths
          await m.createTable(watchedPaths); 

          // 2. Pour la table Sounds
          await m.deleteTable(sounds.actualTableName);
          await m.createTable(sounds);
        }
        if (from < 4) {
          // Créer la table des soundboards
          await m.createTable(soundBoards);
          final defaultBoardId = await into(soundBoards).insert(
            SoundBoardsCompanion.insert(
              name: 'Board 1',
              createdAt: Value(DateTime.now()),
            ),
          );

          if (from >= 3) {
            // Migration vers la nouvelle structure de board_sounds
            await customStatement('ALTER TABLE board_sounds RENAME TO board_sounds_old');
            await m.createTable(boardSounds);
            await customStatement('''
              INSERT INTO board_sounds (board_id, sound_id, added_at)
              SELECT $defaultBoardId, sound_id, added_at
              FROM board_sounds_old
            ''');
            await customStatement('DROP TABLE board_sounds_old');
          } else {
            await m.createTable(boardSounds);
          }
        }
        if (from < 5) {
          await m.addColumn(sounds, sounds.color);
          await m.addColumn(sounds, sounds.volume);
        }
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    // Initialiser les bibliothèques natives SQLite sur Android/iOS
    if (Platform.isAndroid || Platform.isIOS) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }
    
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'db.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
