import 'package:drift/drift.dart';

enum SoundType {
  soundEffect,
  music,
  ambiance,
}

class Sounds extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()(); // Chemin complet du fichier
  TextColumn get displayName => text().nullable()(); // Nom affiché sur le pad
  TextColumn get filePath => text()(); // Chemin complet du fichier
  IntColumn get type => intEnum<SoundType>()();
  IntColumn get color => integer().nullable()(); // Couleur personnalisée (ARGB)
  RealColumn get volume => real().withDefault(const Constant(1.0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class SoundBoards extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class WatchedPaths extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text()(); // Chemin du dossier ou fichier surveillé
  BoolColumn get isDirectory => boolean().withDefault(const Constant(true))();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
}

class BoardSounds extends Table {
  IntColumn get boardId =>
      integer().references(SoundBoards, #id, onDelete: KeyAction.cascade)();
  IntColumn get soundId => integer().references(Sounds, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
  
  @override
  Set<Column> get primaryKey => {boardId, soundId};
}

