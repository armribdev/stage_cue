import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'sounds.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Sounds, WatchedPaths, BoardSounds])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

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
        if (from < 3) {
          // Créer la table BoardSounds pour gérer les sons dans la board
          await m.createTable(boardSounds);
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
    return NativeDatabase(file);
  });
}
