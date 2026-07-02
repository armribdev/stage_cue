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
  /// Si true, les nouveaux fichiers indexés sont téléchargés automatiquement.
  BoolColumn get autoDownload => boolean().withDefault(const Constant(false))();
}

/// Nœud « dossier » d'une bibliothèque Drive : chaque dossier contenant de
/// l'audio possède ses fichiers DIRECTS et, à terme, sa propre BDD snapshot
/// co-localisée (`.stagecue/library.db` dans CE dossier). Identité = le couple
/// (bibliothèque racine, [driveFolderId]) : lier un parent puis un enfant pointe
/// vers le même nœud au lieu de dupliquer les fichiers partagés.
class LibraryFolders extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get libraryId =>
      integer().references(Libraries, #id, onDelete: KeyAction.cascade)();

  /// Identifiant du dossier Drive (immuable) — ancre de l'emplacement de la BDD.
  TextColumn get driveFolderId => text()();

  /// Chemin du dossier relatif à la racine de la bibliothèque ('' = racine).
  TextColumn get relativePath => text().withDefault(const Constant(''))();

  /// Révision de snapshot connue pour CE dossier (bookkeeping par-dossier).
  IntColumn get lastSyncedRevision => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {libraryId, driveFolderId},
      ];
}

/// Jonction bibliothèque ↔ nœud dossier (VUE PARTAGÉE). Un nœud [LibraryFolders]
/// a un unique propriétaire (`libraryId` = home, qui synchronise son `.stagecue`
/// et sert de base aux chemins). Mais plusieurs bibliothèques peuvent VOIR le
/// même dossier quand leurs liens se recouvrent (parent lié comme A, sous-dossier
/// lié comme B) : chaque bibliothèque dont l'indexation atteint un dossier y est
/// rattachée ici, sans dupliquer ni les fichiers ni le nœud. La visibilité des
/// sons dans le picker et le recâblage des boards passent par cette table.
class FolderMemberships extends Table {
  IntColumn get libraryId =>
      integer().references(Libraries, #id, onDelete: KeyAction.cascade)();
  IntColumn get folderId =>
      integer().references(LibraryFolders, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {libraryId, folderId};
}

class Sounds extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()(); // Nom de fichier sans extension
  TextColumn get displayName => text().nullable()(); // Nom affiché sur le pad
  TextColumn get filePath => text()(); // Chemin local (legacy ou cache dérivé)
  IntColumn get type => intEnum<SoundType>().nullable()();
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
  // Identifiant Drive stable du fichier : immuable au renommage/déplacement,
  // c'est la source de vérité de l'identité d'un son de bibliothèque Drive.
  // null pour un son local ou pas encore réconcilié avec l'index Drive.
  TextColumn get driveFileId => text().nullable()();
  // Dossier propriétaire (ses fichiers directs) : unité d'appartenance et de
  // snapshot par-dossier. null = son local ou antérieur au modèle par-dossier.
  IntColumn get folderId => integer()
      .nullable()
      .references(LibraryFolders, #id, onDelete: KeyAction.setNull)();
  // ── Accès rapide live (refonte UX P3) ────────────────────────────────────
  /// Marqué favori par l'opérateur : accès 1-tap aux sons du spectacle.
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  /// Dernière lecture (pré-écoute ou déclenchement) — tri par récence.
  DateTimeColumn get lastPlayedAt => dateTime().nullable()();
}

class SoundBoards extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get color => integer().nullable()(); // Couleur ARGB personnalisée
  IntColumn get icon => integer().nullable()(); // IconData.codePoint ; null = carré
  /// Bibliothèque Drive propriétaire ; null = scène locale non synchronisée.
  IntColumn get libraryId =>
      integer().nullable().references(Libraries, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Identité stable et PORTABLE du board (UUID). Permet de reconnaître le même
  /// board d'un appareil à l'autre lors de la fusion, indépendamment de l'`id`
  /// local (qui diffère entre appareils). null pour les boards antérieurs à v27
  /// pas encore réconciliés ; un backfill leur en attribue un.
  TextColumn get boardKey => text().nullable()();

  /// Dernière modification locale du board OU de ses pads. Arbitre la fusion
  /// « dernier écrivain gagne » PAR BOARD : deux régisseurs qui éditent deux
  /// scènes différentes ne s'écrasent plus (fusion), et sur une même scène la
  /// version la plus récente l'emporte.
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
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
  IntColumn get rowIndex => integer().withDefault(const Constant(0))();
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
