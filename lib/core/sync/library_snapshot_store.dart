import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../database/database.dart' as db;
import '../database/sounds.dart' show PadPlayMode, SoundType;
import 'library_sound_paths.dart';

/// Export et fusion de snapshots SQLite limités à une bibliothèque Drive
/// (sons, scènes, pads, tags associés).
class LibrarySnapshotStore {
  final db.AppDatabase _database;

  LibrarySnapshotStore(this._database);

  /// Exporte le snapshot RACINE d'une bibliothèque : ses boards + pads. Les pads
  /// référencent leurs sons par `driveFileId` (identité forte, portable) avec
  /// repli sur `relativePath` (portable lui aussi) quand l'ID Drive manque — les
  /// sons eux-mêmes vivent dans les snapshots PAR DOSSIER, pas ici.
  Future<int> exportLibrarySnapshot(int libraryId, String targetPath) async {
    final target = File(targetPath);
    if (await target.exists()) {
      await target.delete();
    }

    final escaped = _escapePath(targetPath);
    await _database.customStatement("ATTACH DATABASE '$escaped' AS snap");
    try {
      await _database.customStatement('''
        CREATE TABLE snap.sound_boards AS
        SELECT * FROM sound_boards WHERE library_id = $libraryId
      ''');
      await _database.customStatement('''
        CREATE TABLE snap.pads AS
        SELECT p.* FROM pads p
        INNER JOIN sound_boards b ON b.id = p.board_id
        WHERE b.library_id = $libraryId
      ''');
      // pad_sounds portent le driveFileId ET le relativePath du son (pas son id
      // local) : la résolution au merge se fait par identité forte (driveFileId)
      // puis par chemin portable (relativePath) en repli, une fois les snapshots
      // dossier fusionnés. On ne garde QUE les pads dont le son a au moins l'une
      // des deux clés portables ; un son purement local (les deux NULL) ne peut
      // pas voyager (le picker interdit d'en placer dans un board Drive).
      await _database.customStatement('''
        CREATE TABLE snap.pad_sounds AS
        SELECT ps.pad_id, ps.sort_order, ps.added_at,
               s.drive_file_id, s.relative_path
        FROM pad_sounds ps
        INNER JOIN pads p ON p.id = ps.pad_id
        INNER JOIN sound_boards b ON b.id = p.board_id
        INNER JOIN sounds s ON s.id = ps.sound_id
        WHERE b.library_id = $libraryId
          AND (s.drive_file_id IS NOT NULL OR s.relative_path IS NOT NULL)
      ''');
    } finally {
      await _detachSnapshot();
    }

    return target.length();
  }

  /// Fusionne le snapshot RACINE de façon INTELLIGENTE (fusion board-par-board,
  /// pas d'écrasement global) et recâble les pads sur les sons locaux via leur
  /// `driveFileId`. Les sons ne sont PAS touchés ici (gérés par
  /// [mergeFolderSnapshot]) — appeler les merges de dossiers AVANT celui-ci pour
  /// que les sons référencés existent.
  Future<void> mergeLibrarySnapshot(
    int libraryId,
    String sourcePath, {
    String? driveFolderId,
  }) async {
    if (!await File(sourcePath).exists()) return;

    final escaped = _escapePath(sourcePath);
    await _database.customStatement("ATTACH DATABASE '$escaped' AS snap");
    try {
      // ATTACH/DETACH doivent rester hors de la transaction Drift : un DETACH
      // avant COMMIT provoque « database snap is locked » sous SQLite.
      await _database.transaction(() async {
        if (!await _snapHasTable('sound_boards')) return;
        await _mergeBoards(libraryId);
      });
    } finally {
      await _detachSnapshot();
    }
  }

  /// Fusion INTELLIGENTE des boards, SANS purge globale :
  /// - chaque board est identifié par sa clé portable `board_key` ;
  /// - un board présent des deux côtés → « dernier écrivain gagne » via
  ///   `updated_at` : on n'écrase le local que si le distant est plus récent ;
  /// - un board présent SEULEMENT en local (autre scène éditée en parallèle) est
  ///   CONSERVÉ — c'est tout l'intérêt : deux régisseurs sur deux scènes ne
  ///   s'écrasent plus ;
  /// - un board présent seulement dans le snapshot est inséré.
  ///
  /// Les pads d'un board (ré)importé sont remplacés puis recâblés sur les sons
  /// locaux. Un board conservé (local plus récent) garde ses pads intacts.
  Future<void> _mergeBoards(int libraryId) async {
    _boardIdMap.clear();
    _padIdMap.clear();

    final hasKey = await _snapColumnExists('sound_boards', 'board_key');
    final hasUpdatedAt = await _snapColumnExists('sound_boards', 'updated_at');

    final boardRows = await _database
        .customSelect('SELECT * FROM snap.sound_boards ORDER BY id')
        .get();
    for (final row in boardRows) {
      final snapBoardId = row.read<int>('id');
      final createdAt = row.read<DateTime>('created_at');
      final snapKey = hasKey ? row.read<String?>('board_key') : null;
      final snapUpdatedAt = hasUpdatedAt
          ? (row.read<DateTime?>('updated_at') ?? createdAt)
          : createdAt;
      final effectiveKey = snapKey ?? const Uuid().v4();

      final local = snapKey == null
          ? null
          : await (_database.select(_database.soundBoards)
                ..where((b) =>
                    b.libraryId.equals(libraryId) & b.boardKey.equals(snapKey)))
              .getSingleOrNull();

      if (local == null) {
        // Board inconnu localement → insertion.
        final newBoardId = await _database.into(_database.soundBoards).insert(
              db.SoundBoardsCompanion.insert(
                name: row.read<String>('name'),
                color: Value(row.read<int?>('color')),
                icon: Value(row.read<int?>('icon')),
                libraryId: Value(libraryId),
                createdAt: Value(createdAt),
                boardKey: Value(effectiveKey),
                updatedAt: Value(snapUpdatedAt),
              ),
            );
        _boardIdMap[snapBoardId] = newBoardId;
      } else if (snapUpdatedAt.isAfter(local.updatedAt)) {
        // Le distant est plus récent → on remplace le contenu de CE board.
        await (_database.update(_database.soundBoards)
              ..where((b) => b.id.equals(local.id)))
            .write(db.SoundBoardsCompanion(
          name: Value(row.read<String>('name')),
          color: Value(row.read<int?>('color')),
          icon: Value(row.read<int?>('icon')),
          updatedAt: Value(snapUpdatedAt),
        ));
        // Ses pads seront réimportés : on efface les anciens (cascade pad_sounds).
        await (_database.delete(_database.pads)
              ..where((p) => p.boardId.equals(local.id)))
            .go();
        _boardIdMap[snapBoardId] = local.id;
      }
      // else : le local est plus récent (édité en parallèle) → conservé tel quel.
      // Board absent de _boardIdMap → ses pads du snapshot sont ignorés.
    }

    await _importBoardPads(libraryId);
  }

  /// (Ré)importe les pads des boards insérés/écrasés (présents dans
  /// [_boardIdMap]) et recâble chaque pad_sound sur le son local.
  Future<void> _importBoardPads(int libraryId) async {
    if (!await _snapHasTable('pads')) return;

    final padRows =
        await _database.customSelect('SELECT * FROM snap.pads ORDER BY id').get();
    for (final row in padRows) {
      final localBoardId = _boardIdMap[row.read<int>('board_id')];
      if (localBoardId == null) continue;
      final newPadId = await _database.into(_database.pads).insert(
            db.PadsCompanion.insert(
              boardId: localBoardId,
              name: Value(row.read<String?>('name')),
              color: Value(row.read<int?>('color')),
              sortOrder: Value(row.read<int>('sort_order')),
              rowIndex: Value(row.read<int>('row_index')),
              playMode: Value(PadPlayMode.values[row.read<int>('play_mode')]),
              volume: Value(row.read<double>('volume')),
              createdAt: Value(row.read<DateTime>('created_at')),
            ),
          );
      _padIdMap[row.read<int>('id')] = newPadId;
    }

    if (!await _snapHasTable('pad_sounds')) return;

    final padSoundRows =
        await _database.customSelect('SELECT * FROM snap.pad_sounds').get();
    for (final row in padSoundRows) {
      final localPadId = _padIdMap[row.read<int>('pad_id')];
      if (localPadId == null) continue;
      final driveFileId = row.read<String?>('drive_file_id');
      final relativePath = row.read<String?>('relative_path');

      // Résout le son par identité forte (driveFileId), importé via les
      // snapshots dossier ; à défaut par chemin portable (relativePath) — ainsi
      // un pad n'est jamais perdu si l'ID Drive du son manque encore.
      db.Sound? sound;
      if (driveFileId != null) {
        sound = await (_database.select(_database.sounds)
              ..where(
                (s) =>
                    s.libraryId.equals(libraryId) &
                    s.driveFileId.equals(driveFileId),
              ))
            .getSingleOrNull();
      }
      if (sound == null && relativePath != null) {
        final normalized =
            LibrarySoundPaths.normalizeRelativePath(relativePath);
        sound = await (_database.select(_database.sounds)
              ..where(
                (s) =>
                    s.libraryId.equals(libraryId) &
                    s.relativePath.equals(normalized),
              ))
            .getSingleOrNull();
      }
      if (sound == null) continue;

      await _database.into(_database.padSounds).insert(
            db.PadSoundsCompanion.insert(
              padId: localPadId,
              soundId: sound.id,
              sortOrder: Value(row.read<int>('sort_order')),
              addedAt: Value(row.read<DateTime>('added_at')),
            ),
          );
    }
  }

  // ── Snapshot PAR DOSSIER (modèle BDD-par-dossier) ─────────────────────────
  //
  // Un nœud dossier possède ses fichiers DIRECTS. Le snapshot est donc écrit en
  // chemins « folder-relative » (= basename), portables : n'importe quel appareil
  // le fusionne dans SON nœud (qui a son propre relativePath racine) sans
  // dépendre de l'arborescence de l'appareil source. Les boards/pads ne sont pas
  // ici (ils vivent au niveau bibliothèque/racine).

  /// Exporte les sons (et leurs tags) du dossier [folderId] en chemins
  /// folder-relative vers un fichier SQLite autonome.
  Future<int> exportFolderSnapshot(int folderId, String targetPath) async {
    final target = File(targetPath);
    if (await target.exists()) {
      await target.delete();
    }

    final escaped = _escapePath(targetPath);
    await _database.customStatement("ATTACH DATABASE '$escaped' AS snap");
    try {
      await _database.customStatement('''
        CREATE TABLE snap.sounds AS
        SELECT id, title, display_name, file_path, type, color, volume,
               created_at, library_id, relative_path, content_hash,
               drive_file_id
        FROM sounds WHERE folder_id = $folderId
      ''');

      // Re-base relative_path en folder-relative (basename) : le nœud possède
      // des fichiers directs. SQLite n'a pas de fonction basename → fait en Dart.
      final rows = await _database
          .customSelect('SELECT id, relative_path FROM snap.sounds')
          .get();
      for (final row in rows) {
        final raw = row.read<String?>('relative_path');
        if (raw == null || raw.isEmpty) continue;
        final name = p.posix.basename(raw);
        if (name == raw) continue;
        await _database.customStatement(
          'UPDATE snap.sounds SET relative_path = ? WHERE id = ?',
          [name, row.read<int>('id')],
        );
      }

      await _database.customStatement('''
        CREATE TABLE snap.tag_items AS
        SELECT DISTINCT ti.* FROM tags ti
        INNER JOIN sound_tags st ON st.tag_id = ti.id
        INNER JOIN sounds s ON s.id = st.sound_id
        WHERE s.folder_id = $folderId
      ''');
      await _database.customStatement('''
        CREATE TABLE snap.tag_categories AS
        SELECT DISTINCT tc.* FROM tag_categories tc
        INNER JOIN snap.tag_items ti ON ti.category_id = tc.id
      ''');
      await _database.customStatement('''
        CREATE TABLE snap.sound_tags AS
        SELECT st.* FROM sound_tags st
        INNER JOIN sounds s ON s.id = st.sound_id
        WHERE s.folder_id = $folderId
      ''');
      await _database.customStatement('''
        CREATE TABLE snap.tag_aliases AS
        SELECT DISTINCT ta.* FROM tag_aliases ta
        INNER JOIN snap.tag_items ti ON ti.id = ta.tag_id
      ''');
    } finally {
      await _detachSnapshot();
    }

    return target.length();
  }

  /// Fusionne le snapshot d'un dossier dans le nœud [folderId] local.
  ///
  /// Stratégie **upsert par driveFileId** (pas purge-replace) : les sons
  /// survivants gardent leur ligne — donc leurs liens pad→son et leurs
  /// annotations locales (favori, récence) restent intacts. Les sons absents du
  /// snapshot (retirés côté distant) sont supprimés.
  Future<void> mergeFolderSnapshot(int folderId, String sourcePath) async {
    if (!await File(sourcePath).exists()) return;

    final escaped = _escapePath(sourcePath);
    await _database.customStatement("ATTACH DATABASE '$escaped' AS snap");
    try {
      await _database.transaction(() async {
        final folder = await (_database.select(_database.libraryFolders)
              ..where((f) => f.id.equals(folderId)))
            .getSingleOrNull();
        if (folder == null) return;
        if (!await _snapHasTable('sounds')) return;

        final library = await (_database.select(_database.libraries)
              ..where((l) => l.id.equals(folder.libraryId)))
            .getSingleOrNull();

        await _importFolderSounds(
          folderId: folderId,
          libraryId: folder.libraryId,
          folderRelativePath: folder.relativePath,
          localRoot: library?.localRootPath,
        );

        if (await _snapHasTable('tag_items')) {
          await _importTags();
        }
        if (await _snapHasTable('sound_tags')) {
          // Remplace les tags du dossier (le distant fait foi) avant réimport.
          await _database.customStatement(
            'DELETE FROM sound_tags WHERE sound_id IN '
            '(SELECT id FROM sounds WHERE folder_id = ?)',
            [folderId],
          );
          await _importSoundTags();
        }
      });
    } finally {
      await _detachSnapshot();
    }
  }

  Future<void> _importFolderSounds({
    required int folderId,
    required int libraryId,
    required String folderRelativePath,
    required String? localRoot,
  }) async {
    _soundIdMap.clear();

    final snapRows = await _database
        .customSelect('SELECT * FROM snap.sounds ORDER BY id')
        .get();
    final seenDriveIds = <String>{};

    for (final row in snapRows) {
      final snapId = row.read<int>('id');
      final folderRelative = row.read<String?>('relative_path');
      final rootRelative = (folderRelative == null || folderRelative.isEmpty)
          ? folderRelative
          : (folderRelativePath.isEmpty
              ? folderRelative
              : '$folderRelativePath/$folderRelative');
      final normalized = rootRelative != null
          ? LibrarySoundPaths.normalizeRelativePath(rootRelative)
          : null;
      final filePath = normalized != null && localRoot != null
          ? LibrarySoundPaths.localPathFor(localRoot, normalized)
          : row.read<String>('file_path');
      final driveFileId = row.read<String?>('drive_file_id');
      final contentHash = row.read<String?>('content_hash');
      final rawType = row.read<int?>('type');
      if (driveFileId != null) seenDriveIds.add(driveFileId);

      db.Sound? existing;
      if (driveFileId != null) {
        // Identité forte GLOBALE : `drive_file_id` est unique en base. On le
        // résout sans le scoper au dossier — sinon un fichier déplacé vers CE
        // dossier depuis un autre nœud violerait l'index d'unicité à l'insert.
        existing = await (_database.select(_database.sounds)
              ..where((s) => s.driveFileId.equals(driveFileId)))
            .getSingleOrNull();
      }
      if (existing == null && normalized != null) {
        existing = await (_database.select(_database.sounds)
              ..where(
                (s) =>
                    s.folderId.equals(folderId) &
                    s.relativePath.equals(normalized),
              ))
            .getSingleOrNull();
      }

      if (existing != null) {
        await (_database.update(_database.sounds)
              ..where((s) => s.id.equals(existing!.id)))
            .write(
          db.SoundsCompanion(
            title: Value(row.read<String>('title')),
            displayName: Value(row.read<String?>('display_name')),
            filePath: Value(filePath),
            type: Value(rawType != null ? SoundType.values[rawType] : null),
            color: Value(row.read<int?>('color')),
            volume: Value(row.read<double>('volume')),
            relativePath: Value(normalized),
            contentHash: Value(contentHash),
            driveFileId: Value(driveFileId),
            // Réassigne au nœud courant si le fichier vient d'un autre dossier
            // (résolution par identité forte globale).
            folderId: Value(folderId),
            libraryId: Value(libraryId),
          ),
        );
        _soundIdMap[snapId] = existing.id;
      } else {
        final newId = await _database.into(_database.sounds).insert(
              db.SoundsCompanion.insert(
                title: row.read<String>('title'),
                filePath: filePath,
                type: Value(rawType != null ? SoundType.values[rawType] : null),
                displayName: Value(row.read<String?>('display_name')),
                color: Value(row.read<int?>('color')),
                volume: Value(row.read<double>('volume')),
                createdAt: Value(row.read<DateTime>('created_at')),
                libraryId: Value(libraryId),
                relativePath: Value(normalized),
                contentHash: Value(contentHash),
                driveFileId: Value(driveFileId),
                folderId: Value(folderId),
              ),
            );
        _soundIdMap[snapId] = newId;
      }
    }

    // Supprime les sons du dossier retirés côté distant (identité forte connue
    // mais absente du snapshot). On épargne les sons sans driveFileId (legacy /
    // pas encore réconciliés) pour ne pas perdre de données par erreur.
    final localSounds = await (_database.select(_database.sounds)
          ..where((s) => s.folderId.equals(folderId)))
        .get();
    for (final sound in localSounds) {
      final fid = sound.driveFileId;
      if (fid != null && !seenDriveIds.contains(fid)) {
        await (_database.delete(_database.sounds)
              ..where((s) => s.id.equals(sound.id)))
            .go();
      }
    }
  }

  final Map<int, int> _soundIdMap = {};
  final Map<int, int> _boardIdMap = {};
  final Map<int, int> _padIdMap = {};
  final Map<int, int> _tagIdMap = {};

  Future<void> _importTags() async {
    _tagIdMap.clear();

    if (await _snapHasTable('tag_categories')) {
      final categoryRows = await _database
          .customSelect('SELECT * FROM snap.tag_categories ORDER BY id')
          .get();

      for (final row in categoryRows) {
        final snapCategoryId = row.read<int>('id');
        final name = row.read<String>('name');

        final existing = await (_database.select(_database.tagCategories)
              ..where((c) => c.name.equals(name)))
            .getSingleOrNull();

        final localCategoryId = existing?.id ??
            await _database.into(_database.tagCategories).insert(
                  db.TagCategoriesCompanion.insert(
                    name: name,
                    color: row.read<int>('color'),
                    sortOrder: Value(row.read<int>('sort_order')),
                    description: Value(row.read<String?>('description')),
                  ),
                );

        await _importTagItemsForCategory(snapCategoryId, localCategoryId);
      }
    } else {
      final tagRows = await _database
          .customSelect('SELECT * FROM snap.tag_items ORDER BY id')
          .get();
      for (final row in tagRows) {
        await _upsertTagItem(row);
      }
    }

    if (await _snapHasTable('tag_aliases')) {
      final aliasRows =
          await _database.customSelect('SELECT * FROM snap.tag_aliases').get();
      for (final row in aliasRows) {
        final localTagId = _tagIdMap[row.read<int>('tag_id')];
        if (localTagId == null) continue;

        final normalizedAlias = row.read<String>('normalized_alias');
        final existing = await (_database.select(_database.tagAliases)
              ..where((a) => a.normalizedAlias.equals(normalizedAlias)))
            .getSingleOrNull();
        if (existing != null) continue;

        await _database.into(_database.tagAliases).insert(
              db.TagAliasesCompanion.insert(
                tagId: localTagId,
                alias: row.read<String>('alias'),
                normalizedAlias: normalizedAlias,
              ),
            );
      }
    }
  }

  Future<void> _importTagItemsForCategory(
    int snapCategoryId,
    int localCategoryId,
  ) async {
    final tagRows = await _database.customSelect(
      'SELECT * FROM snap.tag_items WHERE category_id = ? ORDER BY id',
      variables: [Variable<int>(snapCategoryId)],
    ).get();

    for (final row in tagRows) {
      await _upsertTagItem(row, localCategoryId: localCategoryId);
    }
  }

  Future<void> _upsertTagItem(
    QueryRow row, {
    int? localCategoryId,
  }) async {
    final snapTagId = row.read<int>('id');
    final categoryId = localCategoryId ?? row.read<int>('category_id');
    final normalizedName = row.read<String>('normalized_name');

    final existing = await (_database.select(_database.tagItems)
          ..where(
            (t) =>
                t.categoryId.equals(categoryId) &
                t.normalizedName.equals(normalizedName),
          ))
        .getSingleOrNull();

    final localTagId = existing?.id ??
        await _database.into(_database.tagItems).insert(
              db.TagItemsCompanion.insert(
                categoryId: categoryId,
                name: row.read<String>('name'),
                normalizedName: normalizedName,
                description: Value(row.read<String?>('description')),
              ),
            );

    _tagIdMap[snapTagId] = localTagId;
  }

  Future<void> _importSoundTags() async {
    final rows =
        await _database.customSelect('SELECT * FROM snap.sound_tags').get();

    for (final row in rows) {
      final localSoundId = _soundIdMap[row.read<int>('sound_id')];
      final localTagId = _tagIdMap[row.read<int>('tag_id')];
      if (localSoundId == null || localTagId == null) continue;

      await _database.into(_database.soundTags).insert(
            db.SoundTagsCompanion.insert(
              soundId: localSoundId,
              tagId: localTagId,
              addedAt: Value(row.read<DateTime>('added_at')),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  Future<bool> _snapHasTable(String table) async {
    final rows = await _database.customSelect(
      "SELECT name FROM snap.sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable<String>(table)],
    ).get();
    return rows.isNotEmpty;
  }

  /// Vrai si la colonne existe dans la table du snapshot attaché. Robustesse
  /// face à un ancien snapshot dépourvu de `board_key`/`updated_at`.
  Future<bool> _snapColumnExists(String table, String column) async {
    final rows =
        await _database.customSelect('PRAGMA snap.table_info($table)').get();
    return rows.any((r) => r.read<String>('name') == column);
  }

  Future<void> _detachSnapshot() async {
    await _database.customStatement('DETACH DATABASE snap');
  }

  String _escapePath(String path) =>
      p.normalize(path).replaceAll('\\', '/').replaceAll("'", "''");
}
