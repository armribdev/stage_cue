import 'package:drift/drift.dart';

enum SoundType {
  soundEffect,
  music,
  ambiance,
}

enum PadPlayMode {
  random,
  sequential,
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
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  
  @override
  Set<Column> get primaryKey => {boardId, soundId};
}

class Pads extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get boardId =>
      integer().references(SoundBoards, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().nullable()();
  IntColumn get color => integer().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get playMode =>
      intEnum<PadPlayMode>().withDefault(const Constant(0))();
  RealColumn get volume => real().withDefault(const Constant(1.0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class PadSounds extends Table {
  IntColumn get padId =>
      integer().references(Pads, #id, onDelete: KeyAction.cascade)();
  IntColumn get soundId =>
      integer().references(Sounds, #id, onDelete: KeyAction.cascade)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {padId, soundId};
}

class TagCategories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get color => integer()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get description => text().nullable()();
}

class TagItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId =>
      integer().references(TagCategories, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get normalizedName => text()();
  TextColumn get description => text().nullable()();

  @override
  String get tableName => 'tags';

  @override
  List<Set<Column>> get uniqueKeys => [
        {categoryId, normalizedName},
      ];
}

class SoundTags extends Table {
  IntColumn get soundId => integer().references(Sounds, #id, onDelete: KeyAction.cascade)();
  IntColumn get tagId => integer().references(TagItems, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {soundId, tagId};
}

class TagAliases extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get tagId =>
      integer().references(TagItems, #id, onDelete: KeyAction.cascade)();
  TextColumn get alias => text()();
  TextColumn get normalizedAlias => text()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {normalizedAlias},
      ];
}
