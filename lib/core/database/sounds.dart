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

/// Bibliothèque portable : un dossier (potentiellement synchronisé via Drive)
/// qui regroupe des fichiers audio + leurs métadonnées. Sert de racine pour
/// résoudre les chemins relatifs des sons sur n'importe quel appareil.
class Libraries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  // Racine locale (cache) où les fichiers de la bibliothèque sont matérialisés.
  TextColumn get localRootPath => text()();
  // Identifiant du dossier distant (Google Drive) — null tant que non connecté.
  TextColumn get driveFolderId => text().nullable()();
  /// Chemin relatif dans Drive (sans e-mail propriétaire).
  TextColumn get drivePath => text().nullable()();
  /// E-mail du propriétaire du dossier Drive lié.
  TextColumn get ownerEmail => text().nullable()();
  /// Drive d'équipe parent, si le dossier est dans un drive partagé.
  TextColumn get sharedDriveId => text().nullable()();
  // Dernière révision de snapshot DB connue localement (cf. sync).
  IntColumn get lastSyncedRevision => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Sounds extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()(); // Chemin complet du fichier
  TextColumn get displayName => text().nullable()(); // Nom affiché sur le pad
  TextColumn get filePath => text()(); // Chemin local résolu (cache à l'exécution)
  IntColumn get type => intEnum<SoundType>()();
  IntColumn get color => integer().nullable()(); // Couleur personnalisée (ARGB)
  RealColumn get volume => real().withDefault(const Constant(1.0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // ── Portabilité (bibliothèques synchronisables) ──────────────────────────
  // Bibliothèque d'appartenance ; null = son purement local (legacy).
  IntColumn get libraryId =>
      integer().nullable().references(Libraries, #id, onDelete: KeyAction.setNull)();
  // Chemin relatif à la racine de la bibliothèque ; null pour les sons locaux.
  TextColumn get relativePath => text().nullable()();
  // Empreinte de contenu (FNV-1a) pour réidentifier un fichier déplacé/renommé.
  TextColumn get contentHash => text().nullable()();
}

class SoundBoards extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  /// Bibliothèque Drive propriétaire ; null = scène locale non synchronisée.
  IntColumn get libraryId =>
      integer().nullable().references(Libraries, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class WatchedPaths extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text()(); // Chemin du dossier local surveillé
  BoolColumn get isDirectory => boolean().withDefault(const Constant(true))();
  /// E-mail du propriétaire Drive (dossiers SAF cloud), si résolu.
  TextColumn get accountEmail => text().nullable()();
  /// Identifiant fichier Drive extrait de l'URI SAF, pour résolution API.
  TextColumn get driveFileId => text().nullable()();
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
