part of 'database.dart';

/// Migrations du schéma : le corps de `onUpgrade` (étapes incrémentales, une
/// par version) et les aides qu'elles seules utilisent. La stratégie
/// (`schemaVersion`, `onCreate`, `beforeOpen`) reste dans [AppDatabase].
extension _AppDatabaseMigrations on AppDatabase {
  Future<void> _upgrade(Migrator m, int from, int to) async {
    if (from < 2) {
      await m.createTable(watchedPaths);

      await m.deleteTable(sounds.actualTableName);
      await m.createTable(sounds);
    }
    if (from < 4) {
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
        await _createLegacyBoardSounds();
        await customStatement('''
              INSERT INTO board_sounds (board_id, sound_id, added_at)
              SELECT $defaultBoardId, sound_id, added_at
              FROM board_sounds_old
            ''');
        await customStatement('DROP TABLE board_sounds_old');
      } else {
        await _createLegacyBoardSounds();
      }
    }
    if (from < 5) {
      await m.addColumn(sounds, sounds.color);
      await m.addColumn(sounds, sounds.volume);
    }
    if (from < 6) {
      // Colonne NOT NULL depuis v40 : SQLite refuse un ADD COLUMN NOT NULL
      // sans défaut, donc SQL brut avec défaut '' (les vides sont réparés
      // par v39/v40). Gardé : un upgrade depuis < 2 recrée déjà `sounds`.
      if (!await _columnExists('sounds', 'display_name')) {
        await customStatement(
          "ALTER TABLE sounds ADD COLUMN display_name TEXT NOT NULL DEFAULT ''",
        );
      }
    }
    if (from < 7) {
      await m.createTable(tagCategories);
      await m.createTable(tagItems);
      await m.createTable(soundTags);
      await m.createTable(tagAliases);
      await _seedDefaultTagsIfEmpty();
    }
    if (from < 8) {
      await customStatement(
        'ALTER TABLE board_sounds '
        'ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0',
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
            // `display_name` est NOT NULL depuis v40 : la copie vers la
            // nouvelle table ne doit pas échouer sur un nom null/vide.
            sounds.displayName: const CustomExpression<String>(
              "COALESCE(NULLIF(TRIM(display_name), ''), title)",
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
    if (from < 30) {
      // Point d'entrée par son : la lecture démarre à cet offset au lieu
      // du sample 0. Défaut 0 → comportement inchangé pour l'existant.
      await m.addColumn(sounds, sounds.startOffsetMs);
    }
    if (from < 31) {
      // Marque de révision Drive (`md5Checksum`) par son : détecte une
      // édition « en place » (contenu écrasé à ID de fichier constant) pour
      // invalider cache local + waveform + contentHash. Backfill au prochain
      // scan Drive (null → aucune invalidation tant que la marque est absente).
      await m.addColumn(sounds, sounds.driveMd5);
    }
    if (from < 32) {
      await _ensureMusicCategoryTags();
    }
    if (from < 33) {
      // État d'échec VERSIONNÉ de l'extraction waveform : mémorise la
      // génération d'extraction lors d'un échec « format » pour ne pas
      // re-sonder en boucle un fichier que le backend refuse, tout en le
      // re-tentant après une montée de capacité (cf. kWaveformProbeGeneration).
      // Backfill implicite : colonne null → les sons sans waveform seront
      // (re)tentés à la prochaine occasion, ce qui « guérit » d'un coup les
      // fichiers auparavant en échec après un upgrade de flutter_soloud.
      await m.addColumn(sounds, sounds.waveformProbeGeneration);
    }
    if (from < 34) {
      // Le volume passe du pad au couple (pad, son) : chaque son d'un pad a
      // désormais son propre volume (override), au lieu d'un volume unique
      // pour tout le pad. Backfill : chaque pad_sound hérite du volume actuel
      // de son pad pour préserver le rendu audio existant ; null = suivre le
      // volume par défaut du son. On garde-fou les deux étapes car un upgrade
      // depuis < 10 crée déjà les tables au schéma courant (colonne présente,
      // volume du pad absent).
      if (!await _columnExists('pad_sounds', 'volume')) {
        await m.addColumn(
          padSounds,
          padSounds.volume as GeneratedColumn<Object>,
        );
      }
      if (await _columnExists('pads', 'volume')) {
        await customStatement(
          'UPDATE pad_sounds SET volume = '
          '(SELECT p.volume FROM pads p WHERE p.id = pad_sounds.pad_id)',
        );
        // Supprime la colonne volume de pads (recréation de table SQLite).
        await m.alterTable(TableMigration(pads));
      }
    }
    if (from < 35) {
      // Rattrapage d'une collision de versions au merge : deux branches ont
      // toutes deux utilisé le slot `from < 29` (l'une pour la waveform,
      // l'autre pour le volume par pad_sound, depuis renuméroté en v34). Les
      // bases migrées par la branche « volume » ont atteint user_version 29
      // SANS la colonne `waveform` et sautent donc à jamais le `from < 29`.
      // On ré-applique ici l'ajout, gardé par un test d'existence pour rester
      // sans effet sur les bases déjà correctes (branche waveform ou fraîches).
      if (!await _columnExists('sounds', 'waveform')) {
        await m.addColumn(sounds, sounds.waveform);
      }
      if (!await _columnExists('sounds', 'waveform_probe_generation')) {
        await m.addColumn(sounds, sounds.waveformProbeGeneration);
      }
    }
    if (from < 36) {
      // Cache de sonde du pull par-dossier : jeton du manifest au dernier
      // pull concluant. Backfill implicite à null → le premier pull après
      // migration retélécharge chaque manifest une fois, puis les sauts
      // s'installent. Gardé par un test d'existence : un upgrade depuis < 10
      // recrée déjà les tables au schéma courant.
      if (!await _columnExists('library_folders', 'manifest_probe_token')) {
        await m.addColumn(libraryFolders, libraryFolders.manifestProbeToken);
      }
    }
    if (from < 37) {
      // Suivi du parcours incrémental des changements Drive. Backfill
      // implicite à null pour les deux : la première passe après migration
      // est donc un scan complet, qui pose le jeton de départ.
      if (!await _columnExists('libraries', 'drive_change_token')) {
        await m.addColumn(libraries, libraries.driveChangeToken);
      }
      if (!await _columnExists('libraries', 'last_full_scan_at')) {
        await m.addColumn(libraries, libraries.lastFullScanAt);
      }
    }
    if (from < 38) {
      // Marque « son traité » (enregistré depuis la bibliothèque). Défaut
      // false : tous les sons existants démarrent « à traiter ». Gardé par
      // un test d'existence : un upgrade depuis < 10 recrée déjà les tables
      // au schéma courant.
      if (!await _columnExists('sounds', 'is_processed')) {
        await m.addColumn(sounds, sounds.isProcessed);
      }
    }
    if (from < 39) {
      // Le nom affiché d'un son n'est plus jamais null/vide : il vaut le
      // titre du fichier tant que l'utilisateur ne l'a pas personnalisé.
      // Les noms déjà personnalisés sont conservés. Écriture SQL brute :
      // pas d'événement `tableUpdates`, donc aucun push Drive déclenché.
      await customStatement(
        "UPDATE sounds SET display_name = title "
        "WHERE display_name IS NULL OR TRIM(display_name) = ''",
      );
    }
    if (from < 40) {
      // `display_name` passe NOT NULL : SQLite ne sait pas modifier une
      // contrainte, donc recréation de la table (précédent : v23). Le
      // transformer répare au passage tout résidu null/vide — après v39 il
      // ne devrait plus y en avoir, mais une contrainte NOT NULL ne
      // pardonne pas. Aucun `PRAGMA foreign_keys` n'est posé dans l'app
      // (SQLite : désactivé), donc le DROP de l'ancienne table ne cascade
      // ni pad_sounds ni sound_tags. Si les clés étrangères étaient un jour
      // activées, revalider cette étape.
      await m.alterTable(
        TableMigration(
          sounds,
          columnTransformer: {
            sounds.displayName: const CustomExpression<String>(
              "COALESCE(NULLIF(TRIM(display_name), ''), title)",
            ),
          },
        ),
      );
      // Index créé à la main (pas déclaré sur la table) : emporté par la
      // recréation, il faut le reposer.
      await _createGlobalIdentityIndexes();
    }
    if (from < 42) {
      // Vocabulaire musique : la v41 posait des instruments (Piano, Cordes…),
      // peu utiles à la recherche ; on les retire (sauf s'ils sont déjà posés
      // sur un son) au profit de la voix, du tempo et de l'ambiance
      // (EMOTION_STYLE). Données seules, aucun changement de schéma.
      await _ensureExtraTags();
      await _removeUnusedInstrumentTags();
    }
    if (from < 43) {
      // Marque d'analyse automatique des tags (décision 0029). Null = jamais
      // analysé, donc tous les sons existants sont candidats. Gardé par un
      // test d'existence : un upgrade depuis < 40 passe par `alterTable`, qui
      // recrée `sounds` au schéma courant — colonne déjà présente.
      if (!await _columnExists('sounds', 'auto_tagged_at')) {
        await m.addColumn(sounds, sounds.autoTaggedAt);
      }
    }
    if (from < 44) {
      // Empreinte audio de l'analyse automatique (décision 0029). Même
      // garde que ci-dessus. Null pour tous : aucun son n'a été analysé.
      if (!await _columnExists('sounds', 'auto_embedding')) {
        await m.addColumn(sounds, sounds.autoEmbedding);
      }
    }
    if (from < 45) {
      // Tags de l'IA en couche séparée, masquables (décision 0030).
      await customStatement('''
            CREATE TABLE IF NOT EXISTS sound_auto_tags (
              sound_id INTEGER NOT NULL
                REFERENCES sounds (id) ON DELETE CASCADE,
              tag_id INTEGER NOT NULL
                REFERENCES tags (id) ON DELETE CASCADE,
              hidden INTEGER NOT NULL DEFAULT 0 CHECK (hidden IN (0, 1)),
              updated_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
              PRIMARY KEY (sound_id, tag_id)
            )
          ''');
    }
    if (from < 46) {
      // Les tags de l'IA deviennent des suggestions avec un score (décision
      // 0031) : plus de masquage, une confiance par ligne. La table de la v45
      // n'avait ni l'un ni l'autre et n'a jamais été publiée : on la recrée,
      // et on rouvre la décision des sons dont l'empreinte est déjà en base
      // (recalcul sans ré-analyse du fichier). Les sons écartés (format…)
      // n'ont pas d'empreinte : leur marque reste.
      await customStatement('DROP TABLE IF EXISTS sound_auto_tags');
      await m.createTable(soundAutoTags);
      await customStatement(
        'UPDATE sounds SET auto_tagged_at = NULL '
        'WHERE auto_embedding IS NOT NULL',
      );
    }
    if (from < 47) {
      // `board_sounds` n'est plus déclarée : les installations neuves la
      // créaient vide alors que la v10 la supprime des bases migrées.
      await customStatement('DROP TABLE IF EXISTS board_sounds');
      // Les suppressions ne cascadaient pas (clés étrangères désactivées) :
      // on retire les orphelins accumulés. Les déclencheurs de
      // `_createCascadeTriggers` empêchent qu'il s'en recrée.
      await _purgeOrphans();
    }
  }

  /// Vrai si la colonne [column] existe déjà sur la table [table] (PRAGMA).
  /// Rend les migrations idempotentes face aux upgrades multi-versions où une
  /// table a pu être (re)créée au schéma courant par une étape antérieure.
  Future<bool> _columnExists(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.any((r) => r.read<String>('name') == column);
  }

  /// Table `board_sounds` telle que la v4 la déclarait (sans `sort_order`, ajouté
  /// en v8). Elle n'existe que le temps des migrations antérieures à v10, qui la
  /// convertissent en pads puis la suppriment.
  Future<void> _createLegacyBoardSounds() async {
    await customStatement('''
      CREATE TABLE board_sounds (
        board_id INTEGER NOT NULL,
        sound_id INTEGER NOT NULL,
        added_at INTEGER NOT NULL
          DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
        PRIMARY KEY (board_id, sound_id)
      )
    ''');
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
        ),
      );
      // Le volume vit désormais sur le couple (pad, son) et non sur le pad.
      await into(padSounds).insert(
        PadSoundsCompanion.insert(
          padId: padId,
          soundId: row.read<int>('sound_id'),
          volume: Value(row.read<double?>('volume')),
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
        LibrariesCompanion(name: Value(name), drivePath: Value(drivePath)),
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
}
