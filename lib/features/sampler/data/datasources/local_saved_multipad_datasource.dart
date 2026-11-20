import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database.dart' as db;
import '../../../../core/database/sounds.dart' as db_sounds;
import '../../domain/entities/pad.dart' as domain_pad;
import '../../domain/entities/saved_multipad.dart';
import '../../domain/entities/sound.dart' as domain;
import 'sound_query_row.dart';

/// Multipads enregistrés dans la bibliothèque (décision 0051).
class LocalSavedMultipadDataSource {
  final db.AppDatabase _database;

  LocalSavedMultipadDataSource(this._database);

  static db_sounds.PadPlayMode _toDb(domain_pad.PadPlayMode mode) =>
      mode == domain_pad.PadPlayMode.random
      ? db_sounds.PadPlayMode.random
      : db_sounds.PadPlayMode.sequential;

  /// Tous les modèles, par nom, chacun avec ses sons dans l'ordre. Deux
  /// requêtes en tout (modèles, puis membres) : l'index de recherche relit
  /// cette liste à chaque rafraîchissement.
  Future<List<SavedMultipad>> getAll() async {
    final multipadRows = await _database
        .customSelect(
          'SELECT id, name, color, play_mode FROM saved_multipads '
          'ORDER BY name COLLATE NOCASE, id',
        )
        .get();
    if (multipadRows.isEmpty) return const [];

    final soundRows = await _database
        .customSelect(
          'SELECT m.multipad_id, $kPlayableSoundColumns '
          'FROM saved_multipad_sounds m '
          'INNER JOIN sounds s ON s.id = m.sound_id '
          'ORDER BY m.multipad_id, m.sort_order',
        )
        .get();
    final soundsByMultipad = <int, List<domain.Sound>>{};
    for (final row in soundRows) {
      (soundsByMultipad[row.read<int>('multipad_id')] ??= []).add(
        soundFromQueryRow(row),
      );
    }

    return [
      for (final row in multipadRows)
        SavedMultipad(
          id: row.read<int>('id'),
          name: row.read<String>('name'),
          colorValue: row.read<int?>('color'),
          playMode: row.read<int>('play_mode') == 0
              ? domain_pad.PadPlayMode.random
              : domain_pad.PadPlayMode.sequential,
          sounds: soundsByMultipad[row.read<int>('id')] ?? const [],
        ),
    ];
  }

  /// Bibliothèque Drive du plateau [boardId], `null` pour un plateau local ou
  /// inconnu : c'est elle qui publiera le modèle enregistré depuis ce plateau.
  Future<int?> libraryIdOfBoard(int boardId) async {
    final board = await (_database.select(
      _database.soundBoards,
    )..where((b) => b.id.equals(boardId))).getSingleOrNull();
    return board?.libraryId;
  }

  /// Enregistre un modèle et retourne son id. Un modèle sans son n'a aucun
  /// sens (il ne pourrait pas se poser) : [soundIds] ne peut pas être vide.
  /// [libraryId] le rattache à la bibliothèque qui le synchronise ; `null` le
  /// garde local à l'appareil.
  Future<int> create({
    required String name,
    required List<int> soundIds,
    int? colorValue,
    int? libraryId,
    domain_pad.PadPlayMode playMode = domain_pad.PadPlayMode.random,
  }) async {
    if (soundIds.isEmpty) {
      throw ArgumentError.value(soundIds, 'soundIds', 'Un modèle exige un son');
    }
    return _database.transaction(() async {
      final id = await _database
          .into(_database.savedMultipads)
          .insert(
            db.SavedMultipadsCompanion.insert(
              multipadKey: const Uuid().v4(),
              name: name,
              color: Value(colorValue),
              playMode: Value(_toDb(playMode)),
              libraryId: Value(libraryId),
            ),
          );
      await _replaceSounds(id, soundIds);
      return id;
    });
  }

  /// Met à jour les champs fournis et la date de modification. [clearColor]
  /// retire la couleur (un `colorValue` null seul signifie « inchangé »).
  /// [soundIds], s'il est fourni, remplace la liste entière (ordre compris) et
  /// ne peut pas être vide.
  Future<void> update(
    int id, {
    String? name,
    int? colorValue,
    bool clearColor = false,
    domain_pad.PadPlayMode? playMode,
    List<int>? soundIds,
  }) async {
    if (soundIds != null && soundIds.isEmpty) {
      throw ArgumentError.value(soundIds, 'soundIds', 'Un modèle exige un son');
    }
    await _database.transaction(() async {
      await (_database.update(
        _database.savedMultipads,
      )..where((m) => m.id.equals(id))).write(
        db.SavedMultipadsCompanion(
          name: name == null ? const Value.absent() : Value(name),
          color: clearColor
              ? const Value(null)
              : (colorValue == null ? const Value.absent() : Value(colorValue)),
          playMode: playMode == null
              ? const Value.absent()
              : Value(_toDb(playMode)),
          updatedAt: Value(DateTime.now()),
        ),
      );
      if (soundIds != null) await _replaceSounds(id, soundIds);
    });
  }

  /// Supprime le modèle ; ses sons suivent par le déclencheur de cascade. Les
  /// pads déjà posés sur un plateau ne sont pas touchés : ce sont des copies.
  ///
  /// Un modèle synchronisé (rattaché à une bibliothèque) laisse une trace de sa
  /// suppression, publiée avec le snapshot racine : sans elle, la fusion du
  /// snapshot d'un autre appareil le ramènerait.
  Future<void> delete(int id) async {
    await _database.transaction(() async {
      final saved = await (_database.select(
        _database.savedMultipads,
      )..where((m) => m.id.equals(id))).getSingleOrNull();
      if (saved == null) return;
      final libraryId = saved.libraryId;
      if (libraryId != null) {
        await _database
            .into(_database.savedMultipadTombstones)
            .insert(
              db.SavedMultipadTombstonesCompanion.insert(
                multipadKey: saved.multipadKey,
                libraryId: libraryId,
                deletedAt: Value(DateTime.now()),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
      await (_database.delete(
        _database.savedMultipads,
      )..where((m) => m.id.equals(id))).go();
    });
  }

  Future<void> _replaceSounds(int multipadId, List<int> soundIds) async {
    await (_database.delete(
      _database.savedMultipadSounds,
    )..where((s) => s.multipadId.equals(multipadId))).go();
    // `toSet` : un son ne figure qu'une fois (clé primaire), comme dans un pad.
    var order = 0;
    for (final soundId in soundIds.toSet()) {
      await _database
          .into(_database.savedMultipadSounds)
          .insert(
            db.SavedMultipadSoundsCompanion.insert(
              multipadId: multipadId,
              soundId: soundId,
              sortOrder: Value(order++),
            ),
          );
    }
  }
}
