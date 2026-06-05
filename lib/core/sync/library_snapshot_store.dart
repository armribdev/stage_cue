import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../database/database.dart' as db;
import '../database/sounds.dart' show PadPlayMode, SoundType;

/// Export et fusion de snapshots SQLite limités à une bibliothèque Drive
/// (sons, scènes, pads, tags associés).
class LibrarySnapshotStore {
  final db.AppDatabase _database;

  LibrarySnapshotStore(this._database);

  /// Copie les données de [libraryId] vers un fichier SQLite autonome.
  Future<int> exportLibrarySnapshot(int libraryId, String targetPath) async {
    final target = File(targetPath);
    if (await target.exists()) {
      await target.delete();
    }

    final escaped = _escapePath(targetPath);
    await _database.customStatement("ATTACH DATABASE '$escaped' AS snap");
    try {
      await _database.customStatement('''
        CREATE TABLE snap.sounds AS
        SELECT * FROM sounds WHERE library_id = $libraryId
      ''');
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
      await _database.customStatement('''
        CREATE TABLE snap.pad_sounds AS
        SELECT ps.* FROM pad_sounds ps
        INNER JOIN pads p ON p.id = ps.pad_id
        INNER JOIN sound_boards b ON b.id = p.board_id
        WHERE b.library_id = $libraryId
      ''');
      await _database.customStatement('''
        CREATE TABLE snap.tag_items AS
        SELECT DISTINCT ti.* FROM tags ti
        INNER JOIN sound_tags st ON st.tag_id = ti.id
        INNER JOIN sounds s ON s.id = st.sound_id
        WHERE s.library_id = $libraryId
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
        WHERE s.library_id = $libraryId
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

  /// Remplace les données locales de [libraryId] par le contenu du snapshot.
  ///
  /// [driveFolderId] permet d'importer un ancien snapshot global (pré-v15)
  /// en ne prenant que les lignes liées à ce dossier Drive.
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
        await _purgeLibraryData(libraryId);

        if (!await _snapHasTable('sounds')) return;
        final legacy = await _snapHasTable('libraries');
        await _importSounds(
          libraryId,
          legacy: legacy,
          driveFolderId: driveFolderId,
        );
        if (await _snapHasTable('sound_boards')) {
          await _importBoardsAndPads(
            libraryId,
            legacy: legacy,
            driveFolderId: driveFolderId,
          );
        }
        if (await _snapHasTable('tag_items')) {
          await _importTags();
        }
        if (await _snapHasTable('sound_tags')) {
          await _importSoundTags();
        }
      });
    } finally {
      await _detachSnapshot();
    }
  }

  Future<void> _purgeLibraryData(int libraryId) async {
    await (_database.delete(_database.soundBoards)
          ..where((b) => b.libraryId.equals(libraryId)))
        .go();
    await (_database.delete(_database.sounds)
          ..where((s) => s.libraryId.equals(libraryId)))
        .go();
  }

  final Map<int, int> _soundIdMap = {};
  final Map<int, int> _boardIdMap = {};
  final Map<int, int> _padIdMap = {};
  final Map<int, int> _tagIdMap = {};

  Future<void> _importSounds(
    int libraryId, {
    required bool legacy,
    String? driveFolderId,
  }) async {
    _soundIdMap.clear();
    final rows = legacy && driveFolderId != null
        ? await _database.customSelect(
            '''
            SELECT s.* FROM snap.sounds s
            WHERE s.library_id IN (
              SELECT l.id FROM snap.libraries l
              WHERE l.drive_folder_id = ?
            )
            ORDER BY s.id
            ''',
            variables: [Variable<String>(driveFolderId)],
          ).get()
        : await _database
            .customSelect('SELECT * FROM snap.sounds ORDER BY id')
            .get();

    for (final row in rows) {
      final snapId = row.read<int>('id');
      final relativePath = row.read<String?>('relative_path');
      final contentHash = row.read<String?>('content_hash');

      final newId = await _database.into(_database.sounds).insert(
            db.SoundsCompanion.insert(
              title: row.read<String>('title'),
              filePath: row.read<String>('file_path'),
              type: SoundType.values[row.read<int>('type')],
              displayName: Value(row.read<String?>('display_name')),
              color: Value(row.read<int?>('color')),
              volume: Value(row.read<double>('volume')),
              createdAt: Value(row.read<DateTime>('created_at')),
              libraryId: Value(libraryId),
              relativePath: Value(relativePath),
              contentHash: Value(contentHash),
            ),
          );
      _soundIdMap[snapId] = newId;
    }
  }

  Future<void> _importBoardsAndPads(
    int libraryId, {
    required bool legacy,
    String? driveFolderId,
  }) async {
    _boardIdMap.clear();
    _padIdMap.clear();

    if (legacy && !await _snapColumnExists('sound_boards', 'library_id')) {
      return;
    }

    final boardRows = legacy && driveFolderId != null
        ? await _database.customSelect(
            '''
            SELECT b.* FROM snap.sound_boards b
            WHERE b.library_id IN (
              SELECT l.id FROM snap.libraries l
              WHERE l.drive_folder_id = ?
            )
            ORDER BY b.id
            ''',
            variables: [Variable<String>(driveFolderId)],
          ).get()
        : await _database
            .customSelect('SELECT * FROM snap.sound_boards ORDER BY id')
            .get();

    for (final row in boardRows) {
      final snapBoardId = row.read<int>('id');
      final newBoardId = await _database.into(_database.soundBoards).insert(
            db.SoundBoardsCompanion.insert(
              name: row.read<String>('name'),
              libraryId: Value(libraryId),
              createdAt: Value(row.read<DateTime>('created_at')),
            ),
          );
      _boardIdMap[snapBoardId] = newBoardId;
    }

    if (!await _snapHasTable('pads')) return;

    final padRows =
        await _database.customSelect('SELECT * FROM snap.pads ORDER BY id').get();

    for (final row in padRows) {
      final snapPadId = row.read<int>('id');
      final snapBoardId = row.read<int>('board_id');
      final localBoardId = _boardIdMap[snapBoardId];
      if (localBoardId == null) continue;

      final newPadId = await _database.into(_database.pads).insert(
            db.PadsCompanion.insert(
              boardId: localBoardId,
              name: Value(row.read<String?>('name')),
              color: Value(row.read<int?>('color')),
              sortOrder: Value(row.read<int>('sort_order')),
              playMode: Value(PadPlayMode.values[row.read<int>('play_mode')]),
              volume: Value(row.read<double>('volume')),
              createdAt: Value(row.read<DateTime>('created_at')),
            ),
          );
      _padIdMap[snapPadId] = newPadId;
    }

    if (!await _snapHasTable('pad_sounds')) return;

    final padSoundRows =
        await _database.customSelect('SELECT * FROM snap.pad_sounds').get();

    for (final row in padSoundRows) {
      final localPadId = _padIdMap[row.read<int>('pad_id')];
      final localSoundId = _soundIdMap[row.read<int>('sound_id')];
      if (localPadId == null || localSoundId == null) continue;

      await _database.into(_database.padSounds).insert(
            db.PadSoundsCompanion.insert(
              padId: localPadId,
              soundId: localSoundId,
              sortOrder: Value(row.read<int>('sort_order')),
              addedAt: Value(row.read<DateTime>('added_at')),
            ),
          );
    }
  }

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

  Future<bool> _snapColumnExists(String table, String column) async {
    final rows = await _database.customSelect('PRAGMA snap.table_info($table)').get();
    return rows.any((row) => row.read<String>('name') == column);
  }

  Future<bool> _snapHasTable(String table) async {
    final rows = await _database.customSelect(
      "SELECT name FROM snap.sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable<String>(table)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<void> _detachSnapshot() async {
    await _database.customStatement('DETACH DATABASE snap');
  }

  String _escapePath(String path) =>
      p.normalize(path).replaceAll('\\', '/').replaceAll("'", "''");
}
