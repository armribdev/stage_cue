import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import '../sync/library_sound_paths.dart';
import 'sounds.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Libraries,
    LibraryFolders,
    FolderMemberships,
    Sounds,
    SoundBoards,
    WatchedPaths,
    BoardSounds,
    Pads,
    PadSounds,
    TagCategories,
    TagItems,
    SoundTags,
    TagAliases,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 29;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
        await _createGlobalIdentityIndexes();
        await _createBoardKeyIndex();
        await _seedDefaultTagsIfEmpty();
      },
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
            await customStatement(
              'ALTER TABLE board_sounds RENAME TO board_sounds_old',
            );
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
        if (from < 6) {
          await m.addColumn(
            sounds,
            sounds.displayName as GeneratedColumn<Object>,
          );
        }
        if (from < 7) {
          await m.createTable(tagCategories);
          await m.createTable(tagItems);
          await m.createTable(soundTags);
          await m.createTable(tagAliases);
          await _seedDefaultTagsIfEmpty();
        }
        if (from < 8) {
          await m.addColumn(
            boardSounds,
            boardSounds.sortOrder as GeneratedColumn<Object>,
          );
          // Attribuer sort_order aux lignes existantes (ordre par added_at)
          await customStatement('''
            UPDATE board_sounds SET sort_order = (
              SELECT COUNT(*) FROM board_sounds bs2
              WHERE bs2.board_id = board_sounds.board_id
              AND bs2.added_at < board_sounds.added_at
            )
          ''');
        }
        if (from < 9) {
          await _ensureBoardSoundSettingsTableExists();
        }
        if (from < 10) {
          await _migrateToPads(m);
        }
        if (from < 11) {
          // Socle des bibliothèques portables : table + colonnes de portabilité
          // sur sounds. Les sons existants restent locaux (library_id NULL,
          // relative_path NULL → filePath demeure la source de vérité).
          await m.createTable(libraries);
          await m.addColumn(sounds, sounds.libraryId);
          await m.addColumn(sounds, sounds.relativePath);
          await m.addColumn(sounds, sounds.contentHash);
        }
        if (from < 12) {
          await m.addColumn(watchedPaths, watchedPaths.accountEmail);
          await m.addColumn(watchedPaths, watchedPaths.driveFileId);
        }
        if (from < 13) {
          await m.addColumn(libraries, libraries.drivePath);
          await m.addColumn(libraries, libraries.ownerEmail);
          await _migrateLibraryDisplayFields();
        }
        if (from < 14) {
          await m.addColumn(libraries, libraries.sharedDriveId);
        }
        if (from < 15) {
          await m.addColumn(soundBoards, soundBoards.libraryId);
        }
        if (from < 16) {
          await m.addColumn(
            soundBoards,
            soundBoards.color as GeneratedColumn<Object>,
          );
          await m.addColumn(
            soundBoards,
            soundBoards.icon as GeneratedColumn<Object>,
          );
        }
        if (from < 17) {
          await customStatement(
            'ALTER TABLE libraries ADD COLUMN auto_download INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (from < 18) {
          await _resyncLibrarySoundPaths();
        }
        if (from < 19) {
          // Accès rapide live (P3) : favoris + horodatage de dernière lecture.
          await m.addColumn(sounds, sounds.isFavorite);
          await m.addColumn(sounds, sounds.lastPlayedAt);
        }
        if (from < 20) {
          await customStatement(
            'ALTER TABLE sounds ADD COLUMN type_manually_set INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (from < 21) {
          await customStatement(
            'ALTER TABLE sounds ADD COLUMN type_detected INTEGER NOT NULL DEFAULT 1',
          );
          // Sons Drive indexés sans fichier local : type provisoire, à reclasser.
          await customStatement('''
            UPDATE sounds SET type_detected = 0
            WHERE library_id IS NOT NULL
              AND content_hash IS NULL
              AND type_manually_set = 0
          ''');
        }
        if (from < 22) {
          await m.addColumn(pads, pads.rowIndex as GeneratedColumn<Object>);
        }
        if (from < 23) {
          // Simplifie le modèle de type : une seule colonne nullable remplace
          // type (NOT NULL) + typeDetected + typeManuallySet.
          // Règle : null = type inconnu (son Drive jamais téléchargé ou probe
          // raté) ; valeur non-null = type connu (probe réussi ou choix user).
          await m.alterTable(
            TableMigration(
              sounds,
              columnTransformer: {
                sounds.type: const CustomExpression<int>(
                  'CASE WHEN type_detected = 0 AND type_manually_set = 0'
                  ' THEN NULL ELSE type END',
                ),
              },
            ),
          );
        }
        if (from < 24) {
          // Identité forte des sons Drive : l'ID de fichier Drive (stable au
          // renommage/déplacement) devient la clé de déduplication et de
          // réconciliation, en remplacement de l'heuristique par chemin/nom.
          // Backfill par un scan Drive ultérieur (indexDriveFolder) — null OK.
          await m.addColumn(sounds, sounds.driveFileId);
        }
        if (from < 25) {
          // Modèle « BDD par dossier » : chaque dossier Drive devient un nœud
          // propriétaire de ses fichiers directs. Backfill NON destructif —
          // chaque bibliothèque existante devient un nœud racine possédant
          // (comme aujourd'hui) tous ses sons ; le découpage par sous-dossier
          // se fait au prochain réindexage.
          await m.createTable(libraryFolders);
          await m.addColumn(sounds, sounds.folderId);
          await _backfillLibraryFolders();
        }
        if (from < 26) {
          // Identité GLOBALE (indépendante de la bibliothèque) : un fichier
          // Drive = une ligne (`drive_file_id`), un dossier Drive = un nœud
          // (`drive_folder_id`). Empêche la duplication quand des dossiers
          // imbriqués sont liés comme bibliothèques distinctes (l'ancienne
          // dédup était scopée `library_id`).
          //
          // App non publiée : on purge les données Drive (sons + nœuds),
          // ré-indexées au prochain scan, pour repartir d'une base sans doublon
          // AVANT de poser les index d'unicité (une base contenant déjà des
          // doublons ferait échouer la création de l'index). Les sons locaux
          // (`drive_file_id` NULL) sont conservés.
          await customStatement(
            'DELETE FROM sounds WHERE drive_file_id IS NOT NULL',
          );
          await customStatement('UPDATE sounds SET folder_id = NULL');
          await customStatement('DELETE FROM library_folders');
          await _createGlobalIdentityIndexes();
        }
        if (from < 27) {
          // Fusion intelligente des boards : identité portable (`board_key`) +
          // horodatage (`updated_at`) pour une fusion « dernier écrivain gagne »
          // PAR BOARD au lieu d'un écrasement global de toutes les scènes.
          await m.addColumn(
            soundBoards,
            soundBoards.boardKey as GeneratedColumn<Object>,
          );
          await m.addColumn(
            soundBoards,
            soundBoards.updatedAt as GeneratedColumn<Object>,
          );
          await _createBoardKeyIndex();
        }
        if (from < 28) {
          // Vue partagée : un dossier Drive recouvert par plusieurs bibliothèques
          // (parent lié comme A, sous-dossier lié comme B) devient visible par
          // TOUTES via une table de jonction, sans dupliquer fichiers ni nœuds.
          // Backfill : chaque nœud existant est rattaché à sa bibliothèque
          // propriétaire (comportement identique à avant, plus les recouvrements
          // futurs). Réalimenté par l'indexation à chaque appareil de toute façon.
          await m.createTable(folderMemberships);
          await customStatement(
            'INSERT OR IGNORE INTO folder_memberships (library_id, folder_id) '
            'SELECT library_id, id FROM library_folders',
          );
        }
        if (from < 29) {
          // Waveform pré-calculée pour la régie musique (enveloppe RMS par
          // barre). Colonne nullable — les sons existants restent à null et
          // sont calculés paresseusement au premier chargement en régie.
          await m.addColumn(sounds, sounds.waveform);
        }
      },
      beforeOpen: (details) async {
        // Filet de sécurité pour les bases antérieures à v9 qui n'auraient pas
        // encore migré — sans effet sur les bases v10+ (table inexistante).
        if (details.versionBefore != null && details.versionBefore! < 9) {
          await _ensureBoardSoundSettingsTableExists();
        }
      },
    );
  }

  /// Index d'unicité GLOBALE de l'identité forte Drive : un fichier Drive
  /// (`drive_file_id`) et un dossier Drive (`drive_folder_id`) n'existent qu'une
  /// fois en base, toutes bibliothèques confondues. SQLite traite les NULL comme
  /// distincts → les sons locaux (sans `drive_file_id`) ne sont pas contraints.
  Future<void> _createGlobalIdentityIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_sounds_drive_file_id '
      'ON sounds (drive_file_id)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_library_folders_drive_folder_id '
      'ON library_folders (drive_folder_id)',
    );
  }

  /// Index d'unicité de l'identité portable des boards (`board_key`). SQLite
  /// traite les NULL comme distincts → les boards pas encore réconciliés (clé
  /// NULL) ne sont pas contraints.
  Future<void> _createBoardKeyIndex() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_sound_boards_board_key '
      'ON sound_boards (board_key)',
    );
  }

  Future<void> _ensureBoardSoundSettingsTableExists() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS board_sound_settings (
        board_id INTEGER NOT NULL,
        sound_id INTEGER NOT NULL,
        display_name TEXT NULL,
        color INTEGER NULL,
        volume REAL NULL,
        PRIMARY KEY (board_id, sound_id),
        FOREIGN KEY (board_id) REFERENCES sound_boards(id) ON DELETE CASCADE,
        FOREIGN KEY (sound_id) REFERENCES sounds(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _migrateToPads(Migrator m) async {
    // Garantir que board_sound_settings existe (migrations antérieures)
    await _ensureBoardSoundSettingsTableExists();

    await m.createTable(pads);
    await m.createTable(padSounds);

    // Migrer board_sounds + board_sound_settings → pads + pad_sounds
    final rows = await customSelect('''
      SELECT bs.board_id, bs.sound_id, bs.sort_order,
             bss.display_name, bss.color, bss.volume
      FROM board_sounds bs
      LEFT JOIN board_sound_settings bss
        ON bss.board_id = bs.board_id AND bss.sound_id = bs.sound_id
      ORDER BY bs.board_id, bs.sort_order
    ''').get();

    for (final row in rows) {
      final padId = await into(pads).insert(
        PadsCompanion.insert(
          boardId: row.read<int>('board_id'),
          name: Value(row.read<String?>('display_name')),
          color: Value(row.read<int?>('color')),
          sortOrder: Value(row.read<int>('sort_order')),
          volume: Value(row.read<double?>('volume') ?? 1.0),
        ),
      );
      await into(padSounds).insert(
        PadSoundsCompanion.insert(
          padId: padId,
          soundId: row.read<int>('sound_id'),
        ),
      );
    }

    await customStatement('DROP TABLE IF EXISTS board_sound_settings');
    await customStatement('DROP TABLE IF EXISTS board_sounds');
  }

  Future<void> _migrateLibraryDisplayFields() async {
    final rows = await customSelect('SELECT id, name FROM libraries').get();
    for (final row in rows) {
      final id = row.read<int>('id');
      final storedName = row.read<String>('name').trim();
      if (storedName.isEmpty) {
        continue;
      }

      String name = storedName;
      String? drivePath;

      const root = 'Mon Drive';
      if (storedName.startsWith('$root / ')) {
        drivePath = storedName.substring(root.length + 3);
        final segments = drivePath.split(' / ');
        name = segments.isNotEmpty ? segments.last : storedName;
      } else if (storedName.contains(' / ')) {
        drivePath = storedName;
        name = storedName.split(' / ').last;
      }

      await (update(libraries)..where((l) => l.id.equals(id))).write(
        LibrariesCompanion(
          name: Value(name),
          drivePath: Value(drivePath),
        ),
      );
    }
  }

  /// Recalcule `relative_path` (sans préfixe legacy) et `file_path` pour tous
  /// les sons de bibliothèque — source de vérité : `(library_id, relative_path)`.
  Future<void> _resyncLibrarySoundPaths() async {
    final rows = await customSelect('''
      SELECT s.id, s.relative_path, l.local_root_path
      FROM sounds s
      INNER JOIN libraries l ON l.id = s.library_id
      WHERE s.relative_path IS NOT NULL
    ''').get();

    for (final row in rows) {
      final soundId = row.read<int>('id');
      final rawRelative = row.read<String>('relative_path');
      final localRoot = row.read<String>('local_root_path');
      final relativePath = LibrarySoundPaths.normalizeRelativePath(rawRelative);
      final filePath = LibrarySoundPaths.localPathFor(localRoot, relativePath);

      await (update(sounds)..where((s) => s.id.equals(soundId))).write(
        SoundsCompanion(
          relativePath: Value(relativePath),
          filePath: Value(filePath),
        ),
      );
    }
  }

  /// Crée un nœud dossier racine par bibliothèque Drive existante et rattache
  /// tous ses sons — migration non destructive vers le modèle par-dossier.
  Future<void> _backfillLibraryFolders() async {
    final libs = await customSelect(
      'SELECT id, drive_folder_id FROM libraries',
    ).get();
    for (final row in libs) {
      final libraryId = row.read<int>('id');
      final driveFolderId = row.read<String?>('drive_folder_id');
      if (driveFolderId == null) continue; // bibliothèque non connectée à Drive
      final folderId = await into(libraryFolders).insert(
        LibraryFoldersCompanion.insert(
          libraryId: libraryId,
          driveFolderId: driveFolderId,
        ),
      );
      await customStatement(
        'UPDATE sounds SET folder_id = ? WHERE library_id = ?',
        [folderId, libraryId],
      );
    }
  }

  Future<void> _seedDefaultTagsIfEmpty() async {
    final existingResult = await customSelect(
      'SELECT COUNT(*) AS c FROM tag_categories',
    ).getSingle();
    if (existingResult.read<int>('c') > 0) {
      return;
    }

    await transaction(() async {
      Future<void> insertCategory({
        required String name,
        required int color,
        required int sortOrder,
        required String description,
      }) async {
        await customStatement(
          'INSERT INTO tag_categories (name, color, sort_order, description) VALUES (?, ?, ?, ?)',
          [name, color, sortOrder, description],
        );
      }

      await insertCategory(
        name: 'ACTION',
        color: 0xFFFF5722,
        sortOrder: 1,
        description: 'Verbes et gestes associés aux actions des comédiens.',
      );
      await insertCategory(
        name: 'OBJET',
        color: 0xFF2196F3,
        sortOrder: 2,
        description: 'Accessoires utilisés ou évoqués dans la scène.',
      );
      await insertCategory(
        name: 'MATIERE',
        color: 0xFF4CAF50,
        sortOrder: 3,
        description: 'Texture sonore quand l’objet précis manque.',
      );
      await insertCategory(
        name: 'AMBIANCE',
        color: 0xFF7E57C2,
        sortOrder: 4,
        description: 'Décors sonores.',
      );
      await insertCategory(
        name: 'EMOTION_STYLE',
        color: 0xFFE91E63,
        sortOrder: 5,
        description: 'Couleur émotionnelle ou style de scène.',
      );

      Future<int> getCategoryId(String name) async {
        final row = await customSelect(
          'SELECT id FROM tag_categories WHERE name = ? LIMIT 1',
          variables: [Variable<String>(name)],
        ).getSingle();
        return row.read<int>('id');
      }

      final tagByName = <String, int>{};
      Future<void> insertTag(String name, String categoryName) async {
        final categoryId = await getCategoryId(categoryName);
        await customStatement(
          'INSERT INTO tags (category_id, name, normalized_name) VALUES (?, ?, ?)',
          [categoryId, name, _normalize(name)],
        );
        final row = await customSelect(
          'SELECT id FROM tags WHERE name = ? LIMIT 1',
          variables: [Variable<String>(name)],
        ).getSingle();
        tagByName[name] = row.read<int>('id');
      }

      // ACTION
      await insertTag('Casser', 'ACTION');
      await insertTag('Claquer', 'ACTION');
      await insertTag('Ouvrir', 'ACTION');
      await insertTag('Fermer', 'ACTION');
      await insertTag('Impact', 'ACTION');
      await insertTag('Glisser', 'ACTION');
      await insertTag('Frapper', 'ACTION');
      await insertTag('Exploser', 'ACTION');
      await insertTag('Actionner', 'ACTION');
      await insertTag('Marcher', 'ACTION');
      await insertTag('Courir', 'ACTION');
      await insertTag('Rire', 'ACTION');
      await insertTag('Pleurer', 'ACTION');
      await insertTag('Crier', 'ACTION');
      await insertTag('Chuchoter', 'ACTION');
      await insertTag('Siffler', 'ACTION');
      await insertTag('Applaudir', 'ACTION');
      // OBJET
      await insertTag('Porte', 'OBJET');
      await insertTag('Téléphone', 'OBJET');
      await insertTag('Voiture', 'OBJET');
      await insertTag('Arme', 'OBJET');
      await insertTag('Verre', 'OBJET');
      await insertTag('Clés', 'OBJET');
      await insertTag('Outil', 'OBJET');
      await insertTag('Cuisine', 'OBJET');
      await insertTag('Chaise', 'OBJET');
      await insertTag('Table', 'OBJET');
      await insertTag('Fenêtre', 'OBJET');
      await insertTag('Livre', 'OBJET');
      await insertTag('Lit', 'OBJET');
      // MATIERE
      await insertTag('Bois', 'MATIERE');
      await insertTag('Métal', 'MATIERE');
      await insertTag('Verre', 'MATIERE');
      await insertTag('Eau', 'MATIERE');
      await insertTag('Papier', 'MATIERE');
      await insertTag('Gravier', 'MATIERE');
      await insertTag('Électronique', 'MATIERE');
      await insertTag('Plastique', 'MATIERE');
      await insertTag('Tissu', 'MATIERE');
      await insertTag('Pierre', 'MATIERE');
      await insertTag('Caoutchouc', 'MATIERE');
      // AMBIANCE
      await insertTag('Nature', 'AMBIANCE');
      await insertTag('Urbain', 'AMBIANCE');
      await insertTag('Public', 'AMBIANCE');
      await insertTag('Horreur', 'AMBIANCE');
      await insertTag('Transport', 'AMBIANCE');
      await insertTag('Médiéval', 'AMBIANCE');
      await insertTag('Fantastique', 'AMBIANCE');
      await insertTag('Antiquité', 'AMBIANCE');
      await insertTag('Renaissance', 'AMBIANCE');
      await insertTag('Époque victorienne', 'AMBIANCE');
      await insertTag('Années 20', 'AMBIANCE');
      await insertTag('Années 50', 'AMBIANCE');
      await insertTag('Années 80', 'AMBIANCE');
      await insertTag('Futuriste', 'AMBIANCE');
      await insertTag('Intérieur', 'AMBIANCE');
      await insertTag('Extérieur', 'AMBIANCE');
      await insertTag('Foule', 'AMBIANCE');
      await insertTag('Silence', 'AMBIANCE');
      await insertTag('Pluie', 'AMBIANCE');
      await insertTag('Orage', 'AMBIANCE');
      await insertTag('Mer', 'AMBIANCE');
      await insertTag('Forêt', 'AMBIANCE');
      await insertTag('Nuit', 'AMBIANCE');
      await insertTag('Jour', 'AMBIANCE');
      // EMOTION_STYLE
      await insertTag('Comédie', 'EMOTION_STYLE');
      await insertTag('Tension', 'EMOTION_STYLE');
      await insertTag('Magie', 'EMOTION_STYLE');
      await insertTag('Urgence', 'EMOTION_STYLE');
      await insertTag('Romantique', 'EMOTION_STYLE');
      await insertTag('Triste', 'EMOTION_STYLE');
      await insertTag('Épique', 'EMOTION_STYLE');
      await insertTag('Drame', 'EMOTION_STYLE');
      await insertTag('Mystérieux', 'EMOTION_STYLE');
      await insertTag('Oppressant', 'EMOTION_STYLE');
      await insertTag('Sombre', 'EMOTION_STYLE');
      await insertTag('Léger', 'EMOTION_STYLE');
      await insertTag('Poétique', 'EMOTION_STYLE');

      Future<void> insertAlias(String alias, String tagName) async {
        final tagId = tagByName[tagName]!;
        await customStatement(
          'INSERT INTO tag_aliases (tag_id, alias, normalized_alias) VALUES (?, ?, ?)',
          [tagId, alias, _normalize(alias)],
        );
      }

      await insertAlias('tomber', 'Impact');
      await insertAlias('chute', 'Impact');
      await insertAlias('heurter', 'Impact');
      await insertAlias('impact', 'Impact');
      await insertAlias('briser', 'Casser');
      await insertAlias('coup de feu', 'Exploser');
      await insertAlias('tir', 'Exploser');
      await insertAlias('détonation', 'Exploser');
      await insertAlias('explosion', 'Exploser');
      await insertAlias('déraper', 'Glisser');
      await insertAlias('glissement', 'Glisser');
      await insertAlias('toquer', 'Frapper');
      await insertAlias('gifle', 'Claquer');
      await insertAlias('porte qui claque', 'Claquer');
      await insertAlias('bris de verre', 'Casser');
      await insertAlias('verre cassé', 'Casser');
      await insertAlias('liquide', 'Eau');
      await insertAlias('plastique', 'Plastique');
      await insertAlias('synthétique', 'Plastique');
      await insertAlias('terre', 'Gravier');
      await insertAlias('cailloux', 'Gravier');
      await insertAlias('caoutchouc', 'Caoutchouc');
      await insertAlias('mystère', 'Mystérieux');
      await insertAlias('fantasy', 'Fantastique');
      await insertAlias('ville', 'Urbain');
      await insertAlias('rue', 'Urbain');
      await insertAlias('extérieur', 'Extérieur');
      await insertAlias('intérieur', 'Intérieur');
      await insertAlias('applaudissements', 'Applaudir');
      await insertAlias('rire', 'Rire');
      await insertAlias('rires', 'Rire');
      await insertAlias('pleurs', 'Pleurer');
      await insertAlias('crier', 'Crier');
      await insertAlias('hurler', 'Crier');
      await insertAlias('chuchotement', 'Chuchoter');
      await insertAlias('sifflement', 'Siffler');
      await insertAlias('pas', 'Marcher');
      await insertAlias('course', 'Courir');
      await insertAlias('auto', 'Voiture');
      await insertAlias('bagnole', 'Voiture');
      await insertAlias('portable', 'Téléphone');
      await insertAlias('téléphone portable', 'Téléphone');
      await insertAlias('clef', 'Clés');
      await insertAlias('clé', 'Clés');
      await insertAlias('forêt', 'Forêt');
      await insertAlias('pluie', 'Pluie');
      await insertAlias('orage', 'Orage');
      await insertAlias('mer', 'Mer');
      await insertAlias('nuit', 'Nuit');
      await insertAlias('jour', 'Jour');
      await insertAlias('sf', 'Futuriste');
      await insertAlias('science fiction', 'Futuriste');
      await insertAlias('science-fiction', 'Futuriste');
      await insertAlias('cartoon', 'Comédie');
      await insertAlias('burlesque', 'Comédie');
      await insertAlias('suspense', 'Tension');
      await insertAlias('féerie', 'Magie');
      await insertAlias('mélancolique', 'Triste');
      await insertAlias('héroïque', 'Épique');
      await insertAlias('dramatique', 'Drame');
      await insertAlias('tragique', 'Drame');
      await insertAlias('enjoué', 'Léger');
    });
  }

  String _normalize(String value) {
    final lower = value.trim().toLowerCase();
    const replacements = {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'á': 'a',
      'ç': 'c',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'ì': 'i',
      'í': 'i',
      'ô': 'o',
      'ö': 'o',
      'ò': 'o',
      'ó': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ú': 'u',
      'ÿ': 'y',
      'œ': 'oe',
      'æ': 'ae',
    };
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(replacements[char] ?? char);
    }
    return buffer.toString();
  }
}

/// Nom du fichier de base principal.
const String kDbFileName = 'db.sqlite';

/// Résout le fichier de la base principale.
///
/// La base vit dans le dossier de support de l'app (masqué de l'utilisateur,
/// hors du dossier Documents partagé/visible). Unique source de vérité pour
/// l'emplacement de la DB — ne pas reconstruire ce chemin ailleurs.
Future<File> resolveDatabaseFile() async {
  final dbFolder = await getApplicationSupportDirectory();
  return File(p.join(dbFolder.path, kDbFileName));
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    // Initialiser les bibliothèques natives SQLite sur Android/iOS
    if (Platform.isAndroid || Platform.isIOS) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }

    final file = await resolveDatabaseFile();
    return NativeDatabase.createInBackground(file);
  });
}
