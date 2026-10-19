import 'package:drift/drift.dart';
import '../../../../core/database/database.dart' as db;
import '../../../../core/database/sounds.dart' as db_sounds;
import '../../domain/entities/sound.dart' as domain;
import '../../domain/entities/pad.dart' as domain_pad;

/// Source de données locale pour les pads
class LocalPadDataSource {
  final db.AppDatabase _database;

  LocalPadDataSource(this._database);

  /// Marque le board comme modifié (horodatage de fusion intelligente). Toute
  /// mutation de pad = édition de la scène → arbitre le « dernier écrivain
  /// gagne » PAR BOARD à la synchro.
  Future<void> _touchBoard(int boardId) async {
    await (_database.update(_database.soundBoards)
          ..where((b) => b.id.equals(boardId)))
        .write(db.SoundBoardsCompanion(updatedAt: Value(DateTime.now())));
  }

  /// Variante quand on ne connaît que le pad : résout son board puis l'horodate.
  Future<void> _touchBoardOfPad(int padId) async {
    final pad = await (_database.select(_database.pads)
          ..where((p) => p.id.equals(padId)))
        .getSingleOrNull();
    if (pad != null) await _touchBoard(pad.boardId);
  }

  domain.Sound _rowToSound(QueryRow row) {
    final typeValue = row.read<int?>('type');
    return domain.Sound(
      id: row.read<int>('id'),
      title: row.read<String>('title'),
      displayName: row.read<String>('display_name'),
      filePath: row.read<String>('file_path'),
      type: switch (typeValue) {
        0 => domain.SoundType.soundEffect,
        1 => domain.SoundType.music,
        2 => domain.SoundType.ambiance,
        _ => null,
      },
      colorValue: row.read<int?>('color'),
      volume: row.read<double>('volume'),
      createdAt: row.read<DateTime>('created_at'),
      libraryId: row.read<int?>('library_id'),
      relativePath: row.read<String?>('relative_path'),
      contentHash: row.read<String?>('content_hash'),
      waveform: row.read<Uint8List?>('waveform'),
    );
  }

  /// Récupère tous les pads d'une board avec leurs sons.
  Future<List<domain_pad.Pad>> getBoardPads(int boardId) async {
    final padRows = await _database.customSelect(
      '''
      SELECT id, board_id, name, color, sort_order, row_index, play_mode, created_at
      FROM pads
      WHERE board_id = ?
      ORDER BY row_index, sort_order, created_at
      ''',
      variables: [Variable<int>(boardId)],
    ).get();

    final pads = <domain_pad.Pad>[];
    for (final padRow in padRows) {
      final soundRows = await _database.customSelect(
        '''
        SELECT s.id, s.title, s.display_name, s.file_path, s.type,
               s.color, s.volume, s.created_at,
               s.library_id, s.relative_path, s.content_hash, s.waveform,
               ps.volume AS pad_sound_volume
        FROM pad_sounds ps
        INNER JOIN sounds s ON s.id = ps.sound_id
        WHERE ps.pad_id = ?
        ORDER BY ps.sort_order, ps.added_at
        ''',
        variables: [Variable<int>(padRow.read<int>('id'))],
      ).get();

      pads.add(domain_pad.Pad(
        id: padRow.read<int>('id'),
        boardId: padRow.read<int>('board_id'),
        name: padRow.read<String?>('name'),
        colorValue: padRow.read<int?>('color'),
        sortOrder: padRow.read<int>('sort_order'),
        rowIndex: padRow.read<int>('row_index'),
        playMode: padRow.read<int>('play_mode') == 0
            ? domain_pad.PadPlayMode.random
            : domain_pad.PadPlayMode.sequential,
        createdAt: padRow.read<DateTime>('created_at'),
        sounds: soundRows.map(_rowToSound).toList(),
        soundVolumes:
            soundRows.map((r) => r.read<double?>('pad_sound_volume')).toList(),
      ));
    }
    return pads;
  }

  /// Crée un pad avec un son initial, retourne l'id du pad créé.
  Future<int> createPad(int boardId, int soundId, {int rowIndex = 0}) async {
    final countRow = await _database.customSelect(
      'SELECT COUNT(*) AS c FROM pads WHERE board_id = ?',
      variables: [Variable<int>(boardId)],
    ).getSingle();
    final nextOrder = countRow.read<int>('c');

    final padId = await _database.into(_database.pads).insert(
      db.PadsCompanion.insert(
        boardId: boardId,
        sortOrder: Value(nextOrder),
        rowIndex: Value(rowIndex),
      ),
    );
    await _database.into(_database.padSounds).insert(
      db.PadSoundsCompanion.insert(padId: padId, soundId: soundId),
    );
    await _touchBoard(boardId);
    return padId;
  }

  /// Crée un pad avec des réglages complets et plusieurs sons.
  Future<int> createPadWithSettings({
    required int boardId,
    required List<int> soundIds,
    String? name,
    int? colorValue,
    List<double?>? soundVolumes,
    domain_pad.PadPlayMode playMode = domain_pad.PadPlayMode.random,
    int? sortOrder,
    int rowIndex = 0,
  }) async {
    final nextOrder = sortOrder ??
        (await _database.customSelect(
          'SELECT COUNT(*) AS c FROM pads WHERE board_id = ?',
          variables: [Variable<int>(boardId)],
        ).getSingle())
            .read<int>('c');

    final padId = await _database.into(_database.pads).insert(
      db.PadsCompanion.insert(
        boardId: boardId,
        name: Value(name),
        color: Value(colorValue),
        sortOrder: Value(nextOrder),
        rowIndex: Value(rowIndex),
        playMode: Value(
          playMode == domain_pad.PadPlayMode.random
              ? db_sounds.PadPlayMode.random
              : db_sounds.PadPlayMode.sequential,
        ),
      ),
    );
    for (var i = 0; i < soundIds.length; i++) {
      final override =
          (soundVolumes != null && i < soundVolumes.length)
              ? soundVolumes[i]
              : null;
      await _database.into(_database.padSounds).insert(
        db.PadSoundsCompanion.insert(
          padId: padId,
          soundId: soundIds[i],
          sortOrder: Value(i),
          volume: Value(override),
        ),
      );
    }
    await _touchBoard(boardId);
    return padId;
  }

  /// Supprime un pad (cascade sur pad_sounds).
  Future<void> deletePad(int padId) async {
    await _touchBoardOfPad(padId); // avant suppression : le pad existe encore
    await (_database.delete(_database.pads)
          ..where((p) => p.id.equals(padId)))
        .go();
  }

  /// Ajoute un son à un pad existant.
  Future<void> addSoundToPad(int padId, int soundId) async {
    final existing = await _database.customSelect(
      'SELECT COUNT(*) AS c FROM pad_sounds WHERE pad_id = ? AND sound_id = ?',
      variables: [Variable<int>(padId), Variable<int>(soundId)],
    ).getSingle();
    if (existing.read<int>('c') > 0) return;

    final countRow = await _database.customSelect(
      'SELECT COUNT(*) AS c FROM pad_sounds WHERE pad_id = ?',
      variables: [Variable<int>(padId)],
    ).getSingle();
    final nextOrder = countRow.read<int>('c');

    await _database.into(_database.padSounds).insert(
      db.PadSoundsCompanion.insert(
        padId: padId,
        soundId: soundId,
        sortOrder: Value(nextOrder),
      ),
    );
    await _touchBoardOfPad(padId);
  }

  /// Retire un son d'un pad.
  Future<void> removeSoundFromPad(int padId, int soundId) async {
    await (_database.delete(_database.padSounds)
          ..where(
            (ps) => ps.padId.equals(padId) & ps.soundId.equals(soundId),
          ))
        .go();
    await _touchBoardOfPad(padId);
  }

  /// Réordonne les pads d'une board.
  Future<void> reorderBoardPads(int boardId, List<int> padIdsInOrder) async {
    await _database.transaction(() async {
      for (var i = 0; i < padIdsInOrder.length; i++) {
        await (_database.update(_database.pads)
              ..where(
                (p) =>
                    p.id.equals(padIdsInOrder[i]) & p.boardId.equals(boardId),
              ))
            .write(db.PadsCompanion(sortOrder: Value(i)));
      }
    });
    await _touchBoard(boardId);
  }

  /// Met à jour row_index et sort_order de chaque pad en une transaction.
  Future<void> applyPadsLayout(
    int boardId,
    List<({int padId, int rowIndex, int sortOrder})> layout,
  ) async {
    await _database.transaction(() async {
      for (final entry in layout) {
        await (_database.update(_database.pads)
              ..where(
                (p) => p.id.equals(entry.padId) & p.boardId.equals(boardId),
              ))
            .write(
          db.PadsCompanion(
            rowIndex: Value(entry.rowIndex),
            sortOrder: Value(entry.sortOrder),
          ),
        );
      }
    });
    await _touchBoard(boardId);
  }

  /// Met à jour les réglages d'un pad.
  Future<void> updatePadSettings({
    required int padId,
    String? name,
    bool updateName = false,
    int? colorValue,
    bool updateColor = false,
    domain_pad.PadPlayMode? playMode,
  }) async {
    final companion = db.PadsCompanion(
      name: updateName ? Value(name) : const Value.absent(),
      color: updateColor ? Value(colorValue) : const Value.absent(),
      playMode: playMode != null
          ? Value(
              playMode == domain_pad.PadPlayMode.random
                  ? db_sounds.PadPlayMode.random
                  : db_sounds.PadPlayMode.sequential,
            )
          : const Value.absent(),
    );
    await (_database.update(_database.pads)
          ..where((p) => p.id.equals(padId)))
        .write(companion);
    await _touchBoardOfPad(padId);
  }

  /// Met à jour l'override de volume d'un son DANS un pad ([volume] null =
  /// suivre le volume par défaut du son).
  Future<void> updatePadSoundVolume({
    required int padId,
    required int soundId,
    required double? volume,
  }) async {
    await (_database.update(_database.padSounds)
          ..where((ps) => ps.padId.equals(padId) & ps.soundId.equals(soundId)))
        .write(db.PadSoundsCompanion(volume: Value(volume)));
    await _touchBoardOfPad(padId);
  }

  Future<void> updatePadRowIndex(int padId, int newRowIndex) async {
    await (_database.update(_database.pads)
          ..where((p) => p.id.equals(padId)))
        .write(db.PadsCompanion(rowIndex: Value(newRowIndex)));
    await _touchBoardOfPad(padId);
  }

  /// Duplique tous les pads d'une board vers une autre board.
  Future<void> duplicatePads(int sourceBoardId, int targetBoardId) async {
    final sourcePads = await _database.customSelect(
      'SELECT id, name, color, sort_order, play_mode FROM pads '
      'WHERE board_id = ? ORDER BY sort_order',
      variables: [Variable<int>(sourceBoardId)],
    ).get();

    for (final padRow in sourcePads) {
      final newPadId = await _database.into(_database.pads).insert(
        db.PadsCompanion.insert(
          boardId: targetBoardId,
          name: Value(padRow.read<String?>('name')),
          color: Value(padRow.read<int?>('color')),
          sortOrder: Value(padRow.read<int>('sort_order')),
          playMode: Value(
            db_sounds.PadPlayMode.values[padRow.read<int>('play_mode')],
          ),
        ),
      );

      final soundRows = await _database.customSelect(
        'SELECT sound_id, sort_order, volume FROM pad_sounds '
        'WHERE pad_id = ? ORDER BY sort_order',
        variables: [Variable<int>(padRow.read<int>('id'))],
      ).get();

      for (final soundRow in soundRows) {
        await _database.into(_database.padSounds).insert(
          db.PadSoundsCompanion.insert(
            padId: newPadId,
            soundId: soundRow.read<int>('sound_id'),
            sortOrder: Value(soundRow.read<int>('sort_order')),
            volume: Value(soundRow.read<double?>('volume')),
          ),
        );
      }
    }
    await _touchBoard(targetBoardId);
  }

  /// Retourne les IDs de tous les sons présents dans les pads d'une board.
  Future<Set<int>> getSoundIdsInBoard(int boardId) async {
    final rows = await _database.customSelect(
      '''
      SELECT DISTINCT ps.sound_id
      FROM pad_sounds ps
      INNER JOIN pads p ON p.id = ps.pad_id
      WHERE p.board_id = ?
      ''',
      variables: [Variable<int>(boardId)],
    ).get();
    return rows.map((r) => r.read<int>('sound_id')).toSet();
  }

  /// Premier pad (ordre de la board) contenant chaque son.
  Future<Map<int, int>> getSoundIdToFirstPadIdInBoard(int boardId) async {
    final rows = await _database.customSelect(
      '''
      SELECT ps.sound_id, ps.pad_id
      FROM pad_sounds ps
      INNER JOIN pads p ON p.id = ps.pad_id
      WHERE p.board_id = ?
      ORDER BY p.sort_order, p.created_at, ps.sort_order, ps.added_at
      ''',
      variables: [Variable<int>(boardId)],
    ).get();
    final map = <int, int>{};
    for (final row in rows) {
      final soundId = row.read<int>('sound_id');
      map.putIfAbsent(soundId, () => row.read<int>('pad_id'));
    }
    return map;
  }
}
