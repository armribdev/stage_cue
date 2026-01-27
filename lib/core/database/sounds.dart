import 'package:drift/drift.dart';

enum SoundType {
  soundEffect,
  music,
  ambiance,
}

class Sounds extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()(); // Chemin complet du fichier
  TextColumn get filePath => text()(); // Chemin complet du fichier
  IntColumn get type => intEnum<SoundType>()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class WatchedPaths extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text()(); // Chemin du dossier ou fichier surveillé
  BoolColumn get isDirectory => boolean().withDefault(const Constant(true))();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
}

class BoardSounds extends Table {
  IntColumn get soundId => integer().references(Sounds, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
  
  @override
  Set<Column> get primaryKey => {soundId};
}

