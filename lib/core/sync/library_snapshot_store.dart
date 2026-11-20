import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../database/database.dart' as db;
import '../database/sounds.dart' show PadPlayMode, SoundType;
import 'library_sound_paths.dart';
import 'sync_log.dart';

/// Export et fusion de snapshots SQLite limités à une bibliothèque Drive
/// (sons, scènes, pads, tags associés).
class LibrarySnapshotStore {
  final db.AppDatabase _database;

  LibrarySnapshotStore(this._database);

  /// Exporte le snapshot RACINE d'une bibliothèque : ses boards + pads, et ses
  /// multipads enregistrés (avec les traces de leur suppression). Les pads et
  /// les multipads enregistrés
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
      // Multipads enregistrés (décision 0051), même convention que les pads :
      // sons par driveFileId et relativePath. Les modèles locaux
      // (`library_id` null) ne voyagent pas. Les traces de suppression
      // accompagnent les modèles : sans elles, un autre appareil les ramènerait.
      await _database.customStatement('''
        CREATE TABLE snap.saved_multipads AS
        SELECT id, multipad_key, name, color, play_mode, created_at, updated_at
        FROM saved_multipads WHERE library_id = $libraryId
      ''');
      await _database.customStatement('''
        CREATE TABLE snap.saved_multipad_sounds AS
        SELECT m.multipad_id, m.sort_order, s.drive_file_id, s.relative_path
        FROM saved_multipad_sounds m
        INNER JOIN saved_multipads sm ON sm.id = m.multipad_id
        INNER JOIN sounds s ON s.id = m.sound_id
        WHERE sm.library_id = $libraryId
          AND (s.drive_file_id IS NOT NULL OR s.relative_path IS NOT NULL)
      ''');
      await _database.customStatement('''
        CREATE TABLE snap.saved_multipad_tombstones AS
        SELECT multipad_key, deleted_at FROM saved_multipad_tombstones
        WHERE library_id = $libraryId
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
        if (await _snapHasTable('sound_boards')) await _mergeBoards(libraryId);
        // Absent d'un snapshot publié par un appareil antérieur à la v53 : les
        // modèles locaux restent alors intacts (la fusion est une union).
        if (await _snapHasTable('saved_multipads')) {
          await _mergeSavedMultipads(libraryId);
        }
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

      // Recherche GLOBALE, comme l'index d'unicité `board_key` : le scoper à la
      // bibliothèque tirée laissait passer un board de même clé possédé
      // ailleurs (deux liens Drive recouvrant la même racine) ou resté local
      // (`library_id` null). La fusion prenait alors le chemin « inconnu »,
      // tentait un INSERT et faisait échouer l'ajout du dossier Drive entier
      // sur `UNIQUE constraint failed: sound_boards.board_key`.
      final local = snapKey == null
          ? null
          : await (_database.select(
              _database.soundBoards,
            )..where((b) => b.boardKey.equals(snapKey))).getSingleOrNull();

      // Board possédé par une AUTRE bibliothèque : on ne le duplique pas et on
      // ne le confisque pas. Même arbitrage que pour les sons partagés entre
      // liens imbriqués (cf. `syncLibrarySoundsFromDriveIndex`) : la vue de
      // l'autre bibliothèque reste intacte, et surtout rien n'est détruit.
      if (local != null &&
          local.libraryId != null &&
          local.libraryId != libraryId) {
        SyncLog.trace(
          'board ${row.read<String>('name')} possédé par la bibliothèque '
          '${local.libraryId} : fusion ignorée pour $libraryId',
        );
        continue;
      }

      // Rattachement, décidé INDÉPENDAMMENT de la fraîcheur du contenu : un
      // board sans propriétaire dont la clé est publiée par cette bibliothèque
      // lui appartient, qu'il gagne ou perde l'arbitrage `updated_at`. Le
      // laisser orphelin quand c'est le LOCAL qui gagne serait le pire cas :
      // `exportLibrarySnapshot` filtre sur `library_id`, donc sa version plus
      // récente ne serait jamais repoussée — perdue en silence.
      if (local != null && local.libraryId == null) {
        await (_database.update(_database.soundBoards)
              ..where((b) => b.id.equals(local.id)))
            .write(db.SoundBoardsCompanion(libraryId: Value(libraryId)));
      }

      if (local == null) {
        // Board inconnu localement → insertion.
        final newBoardId = await _database
            .into(_database.soundBoards)
            .insert(
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
        await (_database.update(
          _database.soundBoards,
        )..where((b) => b.id.equals(local.id))).write(
          db.SoundBoardsCompanion(
            name: Value(row.read<String>('name')),
            color: Value(row.read<int?>('color')),
            icon: Value(row.read<int?>('icon')),
            updatedAt: Value(snapUpdatedAt),
          ),
        );
        // Ses pads seront réimportés : on efface les anciens (leurs pad_sounds suivent, cf.
        // `_createCascadeTriggers`).
        await (_database.delete(
          _database.pads,
        )..where((p) => p.boardId.equals(local.id))).go();
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

    final padRows = await _database
        .customSelect('SELECT * FROM snap.pads ORDER BY id')
        .get();
    for (final row in padRows) {
      final localBoardId = _boardIdMap[row.read<int>('board_id')];
      if (localBoardId == null) continue;
      final newPadId = await _database
          .into(_database.pads)
          .insert(
            db.PadsCompanion.insert(
              boardId: localBoardId,
              name: Value(row.read<String?>('name')),
              color: Value(row.read<int?>('color')),
              sortOrder: Value(row.read<int>('sort_order')),
              rowIndex: Value(row.read<int>('row_index')),
              playMode: Value(PadPlayMode.values[row.read<int>('play_mode')]),
              createdAt: Value(row.read<DateTime>('created_at')),
            ),
          );
      _padIdMap[row.read<int>('id')] = newPadId;
    }

    if (!await _snapHasTable('pad_sounds')) return;

    // Un snapshot antérieur à v50 porte encore un volume par son (`volume`) :
    // il n'existe plus (décision 0045), la colonne est ignorée.
    final padSoundRows = await _database
        .customSelect('SELECT * FROM snap.pad_sounds')
        .get();
    for (final row in padSoundRows) {
      final localPadId = _padIdMap[row.read<int>('pad_id')];
      if (localPadId == null) continue;
      final driveFileId = row.read<String?>('drive_file_id');
      final relativePath = row.read<String?>('relative_path');

      final sound = await _resolveSnapshotSound(
        libraryId: libraryId,
        driveFileId: driveFileId,
        relativePath: relativePath,
      );
      if (sound == null) continue;

      await _database
          .into(_database.padSounds)
          .insert(
            db.PadSoundsCompanion.insert(
              padId: localPadId,
              soundId: sound.id,
              sortOrder: Value(row.read<int>('sort_order')),
              addedAt: Value(row.read<DateTime>('added_at')),
            ),
          );
    }
  }

  /// Résout un son référencé par un snapshot racine (pad, multipad enregistré)
  /// vers le son local : par identité forte (driveFileId), importé via les
  /// snapshots dossier ; à défaut par chemin portable (relativePath) — ainsi une
  /// référence n'est jamais perdue si l'ID Drive du son manque encore. `null`
  /// si le son n'existe pas (encore) localement.
  Future<db.Sound?> _resolveSnapshotSound({
    required int libraryId,
    required String? driveFileId,
    required String? relativePath,
  }) async {
    db.Sound? sound;
    if (driveFileId != null) {
      // Identité forte GLOBALE : `drive_file_id` est unique en base, toutes
      // bibliothèques confondues. On ne scope PAS à `libraryId` — sinon un
      // board d'une bibliothèque « invitée » ne pourrait pas se recâbler sur un
      // son PARTAGÉ possédé par une autre bibliothèque (VUE PARTAGÉE).
      sound = await (_database.select(
        _database.sounds,
      )..where((s) => s.driveFileId.equals(driveFileId))).getSingleOrNull();
    }
    if (sound == null && relativePath != null) {
      final normalized = LibrarySoundPaths.normalizeRelativePath(relativePath);
      sound =
          await (_database.select(_database.sounds)..where(
                (s) =>
                    s.libraryId.equals(libraryId) &
                    s.relativePath.equals(normalized),
              ))
              .getSingleOrNull();
    }
    return sound;
  }

  // ── Multipads enregistrés (décision 0051) ─────────────────────────────────
  //
  // Publiés avec le snapshot racine, comme les boards : leurs sons sont portés
  // par `driveFileId` puis `relativePath` (jamais l'id local), donc résolus
  // après les snapshots dossier. Fusion par clé portable `multipad_key`,
  // dernier écrivain gagnant, sans purge : un modèle présent seulement en local
  // reste. Seule exception, la suppression, qui voyage en pierre tombale — sans
  // elle l'union ramènerait un modèle supprimé depuis un autre appareil.

  Future<void> _mergeSavedMultipads(int libraryId) async {
    if (await _snapHasTable('saved_multipad_tombstones')) {
      await _applySnapshotTombstones(libraryId);
    }

    final members = <int, List<QueryRow>>{};
    if (await _snapHasTable('saved_multipad_sounds')) {
      final memberRows = await _database
          .customSelect(
            'SELECT * FROM snap.saved_multipad_sounds ORDER BY sort_order',
          )
          .get();
      for (final row in memberRows) {
        (members[row.read<int>('multipad_id')] ??= []).add(row);
      }
    }

    final rows = await _database
        .customSelect('SELECT * FROM snap.saved_multipads ORDER BY id')
        .get();
    for (final row in rows) {
      final key = row.read<String?>('multipad_key');
      if (key == null || key.isEmpty) continue;
      final snapUpdatedAt = row.read<DateTime>('updated_at');

      // Supprimé ici depuis (ou en même temps que) cette version : on ne le
      // ressuscite pas. Modifié APRÈS la suppression, il revient et la trace tombe.
      final tombstone = await (_database.select(
        _database.savedMultipadTombstones,
      )..where((t) => t.multipadKey.equals(key))).getSingleOrNull();
      if (tombstone != null && !tombstone.deletedAt.isBefore(snapUpdatedAt)) {
        continue;
      }

      final local = await (_database.select(
        _database.savedMultipads,
      )..where((m) => m.multipadKey.equals(key))).getSingleOrNull();
      // Possédé par une AUTRE bibliothèque : on ne le duplique ni ne le
      // confisque (même arbitrage que pour les boards).
      if (local != null &&
          local.libraryId != null &&
          local.libraryId != libraryId) {
        SyncLog.trace(
          'multipad ${row.read<String>('name')} possédé par la bibliothèque '
          '${local.libraryId} : fusion ignorée pour $libraryId',
        );
        continue;
      }

      final soundIds = await _resolveMultipadSounds(
        libraryId,
        members[row.read<int>('id')] ?? const [],
      );

      if (local == null) {
        // Aucun son résolu (pas encore indexés) : un modèle sans son ne se pose
        // nulle part. Rien n'est écrit, le prochain pull réessaie.
        if (soundIds.isEmpty) {
          SyncLog.trace(
            'multipad ${row.read<String>('name')} : aucun son résolu, ignoré',
          );
          continue;
        }
        final id = await _database
            .into(_database.savedMultipads)
            .insert(
              db.SavedMultipadsCompanion.insert(
                multipadKey: key,
                name: row.read<String>('name'),
                color: Value(row.read<int?>('color')),
                playMode: Value(PadPlayMode.values[row.read<int>('play_mode')]),
                createdAt: Value(row.read<DateTime>('created_at')),
                updatedAt: Value(snapUpdatedAt),
                libraryId: Value(libraryId),
              ),
            );
        await _replaceMultipadSounds(id, soundIds);
        if (tombstone != null) {
          await (_database.delete(
            _database.savedMultipadTombstones,
          )..where((t) => t.multipadKey.equals(key))).go();
        }
        continue;
      }

      // Rattachement indépendant de la fraîcheur, comme pour les boards : un
      // modèle local sans propriétaire dont la clé est publiée ici lui appartient,
      // sinon sa version plus récente ne serait jamais repoussée.
      if (local.libraryId == null) {
        await (_database.update(_database.savedMultipads)
              ..where((m) => m.id.equals(local.id)))
            .write(db.SavedMultipadsCompanion(libraryId: Value(libraryId)));
      }
      // Le distant gagne s'il est plus récent. Sans aucun son résolu on garde le
      // local plutôt que de vider le modèle ; le prochain pull réessaie.
      if (snapUpdatedAt.isAfter(local.updatedAt) && soundIds.isNotEmpty) {
        await (_database.update(
          _database.savedMultipads,
        )..where((m) => m.id.equals(local.id))).write(
          db.SavedMultipadsCompanion(
            name: Value(row.read<String>('name')),
            color: Value(row.read<int?>('color')),
            playMode: Value(PadPlayMode.values[row.read<int>('play_mode')]),
            updatedAt: Value(snapUpdatedAt),
          ),
        );
        await _replaceMultipadSounds(local.id, soundIds);
      }
    }
  }

  /// Applique les suppressions publiées : la trace est conservée localement (pour
  /// la republier à un troisième appareil) et supprime le modèle local qu'elle
  /// vise, sauf s'il a été modifié après la suppression.
  Future<void> _applySnapshotTombstones(int libraryId) async {
    final rows = await _database
        .customSelect('SELECT * FROM snap.saved_multipad_tombstones')
        .get();
    for (final row in rows) {
      final key = row.read<String>('multipad_key');
      final deletedAt = row.read<DateTime>('deleted_at');

      final known = await (_database.select(
        _database.savedMultipadTombstones,
      )..where((t) => t.multipadKey.equals(key))).getSingleOrNull();
      if (known == null || deletedAt.isAfter(known.deletedAt)) {
        await _database
            .into(_database.savedMultipadTombstones)
            .insert(
              db.SavedMultipadTombstonesCompanion.insert(
                multipadKey: key,
                libraryId: libraryId,
                deletedAt: Value(deletedAt),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }

      final local = await (_database.select(
        _database.savedMultipads,
      )..where((m) => m.multipadKey.equals(key))).getSingleOrNull();
      if (local == null) continue;
      // Possédé par une autre bibliothèque : cette trace ne le concerne pas.
      if (local.libraryId != null && local.libraryId != libraryId) continue;
      if (deletedAt.isBefore(local.updatedAt)) continue;
      await (_database.delete(
        _database.savedMultipads,
      )..where((m) => m.id.equals(local.id))).go();
    }
  }

  /// Ids locaux des sons d'un multipad du snapshot, dans l'ordre, sans doublon ;
  /// ceux qui n'existent pas localement sont ignorés.
  Future<List<int>> _resolveMultipadSounds(
    int libraryId,
    List<QueryRow> memberRows,
  ) async {
    final ids = <int>[];
    for (final row in memberRows) {
      final sound = await _resolveSnapshotSound(
        libraryId: libraryId,
        driveFileId: row.read<String?>('drive_file_id'),
        relativePath: row.read<String?>('relative_path'),
      );
      if (sound != null && !ids.contains(sound.id)) ids.add(sound.id);
    }
    return ids;
  }

  Future<void> _replaceMultipadSounds(
    int multipadId,
    List<int> soundIds,
  ) async {
    await (_database.delete(
      _database.savedMultipadSounds,
    )..where((s) => s.multipadId.equals(multipadId))).go();
    for (var i = 0; i < soundIds.length; i++) {
      await _database
          .into(_database.savedMultipadSounds)
          .insert(
            db.SavedMultipadSoundsCompanion.insert(
              multipadId: multipadId,
              soundId: soundIds[i],
              sortOrder: Value(i),
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
      // Colonnes explicites : `is_favorite` et `last_played_at` sont des
      // annotations locales qui ne voyagent pas (et `markPlayed` s'écrit sans
      // déclencher de push en conséquence). Pas de `SELECT *` ici.
      //
      // `volume` et `loudness_gain` n'existent plus (décision 0045) mais restent
      // publiés pour les appareils en v49 ou avant : leur import lit `volume` sans
      // garde et ferait échouer le pull du dossier. Un appareil en v49 joue
      // `volume × loudness_gain`, donc `1.0` et le gain donnent exactement le
      // niveau d'ici. À retirer quand plus aucun appareil n'est en v49.
      await _database.customStatement('''
        CREATE TABLE snap.sounds AS
        SELECT id, title, display_name, file_path, type, color, gain,
               1.0 AS volume, gain AS loudness_gain, created_at, library_id,
               relative_path, content_hash, drive_file_id
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
        UNION
        SELECT DISTINCT ti.* FROM tags ti
        INNER JOIN sound_auto_tags sa ON sa.tag_id = ti.id
        INNER JOIN sounds s ON s.id = sa.sound_id
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
      // Suggestions de l'IA avec leur score (décision 0031). `hidden` n'existe
      // plus ici, mais un appareil en v45 le lit encore à la fusion : on le publie
      // à 0 (jamais masqué) plutôt que de lui faire échouer le pull.
      await _database.customStatement('''
        CREATE TABLE snap.sound_auto_tags AS
        SELECT sa.sound_id, sa.tag_id, 0 AS hidden, sa.score, sa.updated_at
        FROM sound_auto_tags sa
        INNER JOIN sounds s ON s.id = sa.sound_id
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
        final folder = await (_database.select(
          _database.libraryFolders,
        )..where((f) => f.id.equals(folderId))).getSingleOrNull();
        if (folder == null) return;
        if (!await _snapHasTable('sounds')) return;

        final library = await (_database.select(
          _database.libraries,
        )..where((l) => l.id.equals(folder.libraryId))).getSingleOrNull();

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
        if (await _snapHasTable('sound_auto_tags')) {
          if (await _snapColumnExists('sound_auto_tags', 'score')) {
            await _mergeSoundAutoTags();
          } else {
            // Appareil en v45 : ses tags de l'IA n'ont pas de score et étaient
            // des tags à part entière, pas des suggestions (décision 0031).
            SyncLog.info(
              'Snapshot : tags de l\'IA d\'un appareil plus ancien (sans '
              'score) ignorés.',
            );
          }
        }
        // Après tous les imports de tags : un snapshot d'un appareil en retard
        // peut avoir recréé un tag que le catalogue a retiré depuis (0043).
        await _database.reconcileTagCatalog();
      });
    } finally {
      await _detachSnapshot();
    }
  }

  /// Nom affiché d'une ligne de snapshot, jamais vide : un snapshot publié par
  /// un appareil antérieur à v39 peut porter `display_name` à null/vide, et
  /// l'écraser tel quel ferait revenir un son sans nom affiché.
  String _displayNameOf(QueryRow row) {
    final raw = row.read<String?>('display_name')?.trim();
    return (raw == null || raw.isEmpty) ? row.read<String>('title') : raw;
  }

  Future<void> _importFolderSounds({
    required int folderId,
    required int libraryId,
    required String folderRelativePath,
    required String? localRoot,
  }) async {
    _soundIdMap.clear();

    // Gain (décision 0045) : absent des snapshots publiés par un appareil
    // antérieur à v50, où le niveau d'un son est `volume` × `loudness_gain`
    // (cette dernière absente avant v49) — sans erreur ni log : un appareil en
    // retard est normal.
    final hasGain = await _snapColumnExists('sounds', 'gain');
    final hasLoudnessGain = await _snapColumnExists('sounds', 'loudness_gain');
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
      final gain = hasGain
          ? row.read<double>('gain')
          : row.read<double>('volume') *
                (hasLoudnessGain
                    ? row.read<double?>('loudness_gain') ?? 1.0
                    : 1.0);
      if (driveFileId != null) seenDriveIds.add(driveFileId);

      db.Sound? existing;
      if (driveFileId != null) {
        // Identité forte GLOBALE : `drive_file_id` est unique en base. On le
        // résout sans le scoper au dossier — sinon un fichier déplacé vers CE
        // dossier depuis un autre nœud violerait l'index d'unicité à l'insert.
        existing = await (_database.select(
          _database.sounds,
        )..where((s) => s.driveFileId.equals(driveFileId))).getSingleOrNull();
      }
      if (existing == null && normalized != null) {
        existing =
            await (_database.select(_database.sounds)..where(
                  (s) =>
                      s.folderId.equals(folderId) &
                      s.relativePath.equals(normalized),
                ))
                .getSingleOrNull();
      }

      if (existing != null) {
        await (_database.update(
          _database.sounds,
        )..where((s) => s.id.equals(existing!.id))).write(
          db.SoundsCompanion(
            title: Value(row.read<String>('title')),
            displayName: Value(_displayNameOf(row)),
            filePath: Value(filePath),
            type: Value(rawType != null ? SoundType.values[rawType] : null),
            color: Value(row.read<int?>('color')),
            gain: Value(gain),
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
        final newId = await _database
            .into(_database.sounds)
            .insert(
              db.SoundsCompanion.insert(
                title: row.read<String>('title'),
                filePath: filePath,
                type: Value(rawType != null ? SoundType.values[rawType] : null),
                displayName: _displayNameOf(row),
                color: Value(row.read<int?>('color')),
                gain: Value(gain),
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
    final localSounds = await (_database.select(
      _database.sounds,
    )..where((s) => s.folderId.equals(folderId))).get();
    for (final sound in localSounds) {
      final fid = sound.driveFileId;
      if (fid != null && !seenDriveIds.contains(fid)) {
        await (_database.delete(
          _database.sounds,
        )..where((s) => s.id.equals(sound.id))).go();
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
        // Importé tel que publié : un tag ou une catégorie que le catalogue a
        // retirés depuis sont résorbés par `reconcileTagCatalog`, appelé à la
        // fin de la fusion (0043), pas ici.
        final name = row.read<String>('name');

        final existing = await (_database.select(
          _database.tagCategories,
        )..where((c) => c.name.equals(name))).getSingleOrNull();

        final localCategoryId =
            existing?.id ??
            await _database
                .into(_database.tagCategories)
                .insert(
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
      final aliasRows = await _database
          .customSelect('SELECT * FROM snap.tag_aliases')
          .get();
      for (final row in aliasRows) {
        final localTagId = _tagIdMap[row.read<int>('tag_id')];
        if (localTagId == null) continue;

        final normalizedAlias = row.read<String>('normalized_alias');
        final existing =
            await (_database.select(_database.tagAliases)
                  ..where((a) => a.normalizedAlias.equals(normalizedAlias)))
                .getSingleOrNull();
        if (existing != null) continue;

        await _database
            .into(_database.tagAliases)
            .insert(
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
    final tagRows = await _database
        .customSelect(
          'SELECT * FROM snap.tag_items WHERE category_id = ? ORDER BY id',
          variables: [Variable<int>(snapCategoryId)],
        )
        .get();

    for (final row in tagRows) {
      await _upsertTagItem(row, localCategoryId: localCategoryId);
    }
  }

  Future<void> _upsertTagItem(QueryRow row, {int? localCategoryId}) async {
    final snapTagId = row.read<int>('id');
    final categoryId = localCategoryId ?? row.read<int>('category_id');
    final normalizedName = row.read<String>('normalized_name');

    final existing =
        await (_database.select(_database.tagItems)..where(
              (t) =>
                  t.categoryId.equals(categoryId) &
                  t.normalizedName.equals(normalizedName),
            ))
            .getSingleOrNull();

    final localTagId =
        existing?.id ??
        await _database
            .into(_database.tagItems)
            .insert(
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
    final rows = await _database
        .customSelect('SELECT * FROM snap.sound_tags')
        .get();

    for (final row in rows) {
      final localSoundId = _soundIdMap[row.read<int>('sound_id')];
      final localTagId = _tagIdMap[row.read<int>('tag_id')];
      if (localSoundId == null || localTagId == null) continue;

      await _database
          .into(_database.soundTags)
          .insert(
            db.SoundTagsCompanion.insert(
              soundId: localSoundId,
              tagId: localTagId,
              addedAt: Value(row.read<DateTime>('added_at')),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  /// Fusionne les suggestions de l'IA du snapshot (décisions 0030 et 0031) :
  /// **union**, jamais de suppression, et pour une paire (son, tag) connue des
  /// deux côtés la dernière modification gagne (`updated_at`). Un snapshot sans
  /// cette table laisse les suggestions locales intactes.
  Future<void> _mergeSoundAutoTags() async {
    final rows = await _database
        .customSelect('SELECT * FROM snap.sound_auto_tags')
        .get();
    for (final row in rows) {
      final soundId = _soundIdMap[row.read<int>('sound_id')];
      final tagId = _tagIdMap[row.read<int>('tag_id')];
      if (soundId == null || tagId == null) continue;
      final score = row.read<double>('score');
      final updatedAt = row.read<DateTime>('updated_at');

      final existing =
          await (_database.select(_database.soundAutoTags)..where(
                (t) => t.soundId.equals(soundId) & t.tagId.equals(tagId),
              ))
              .getSingleOrNull();
      if (existing == null) {
        await _database
            .into(_database.soundAutoTags)
            .insert(
              db.SoundAutoTagsCompanion.insert(
                soundId: soundId,
                tagId: tagId,
                score: score,
                updatedAt: Value(updatedAt),
              ),
            );
      } else if (updatedAt.isAfter(existing.updatedAt)) {
        await (_database.update(_database.soundAutoTags)
              ..where((t) => t.soundId.equals(soundId) & t.tagId.equals(tagId)))
            .write(
              db.SoundAutoTagsCompanion(
                score: Value(score),
                updatedAt: Value(updatedAt),
              ),
            );
      }
    }
  }

  Future<bool> _snapHasTable(String table) async {
    final rows = await _database
        .customSelect(
          "SELECT name FROM snap.sqlite_master WHERE type = 'table' AND name = ?",
          variables: [Variable<String>(table)],
        )
        .get();
    return rows.isNotEmpty;
  }

  /// Vrai si la colonne existe dans la table du snapshot attaché. Robustesse
  /// face à un ancien snapshot dépourvu de `board_key`/`updated_at`.
  Future<bool> _snapColumnExists(String table, String column) async {
    final rows = await _database
        .customSelect('PRAGMA snap.table_info($table)')
        .get();
    return rows.any((r) => r.read<String>('name') == column);
  }

  Future<void> _detachSnapshot() async {
    await _database.customStatement('DETACH DATABASE snap');
  }

  String _escapePath(String path) =>
      p.normalize(path).replaceAll('\\', '/').replaceAll("'", "''");
}
