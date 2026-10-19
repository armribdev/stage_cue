part of 'local_sound_datasource.dart';

/// Lecture et mutations des sons (CRUD, scènes, réglages, favoris).
/// Méthodes de [LocalSoundDataSource] extraites via extension dans le même `part`.
extension LocalSoundCrud on LocalSoundDataSource {

  /// Récupère tous les sons
  Future<List<domain.Sound>> getAllSounds() async {
    final sounds = await _database.select(_database.sounds).get();
    return sounds.map((s) => SoundModel.toEntity(s)).toList();
  }

  /// Récupère uniquement les sons qui sont dans la board, triés par sort_order puis added_at
  /// Utilise une jointure SQL pour de meilleures performances et éviter les problèmes de sons supprimés
  Future<List<domain.Sound>> getBoardSounds(int boardId) async {
    final rows = await _database
        .customSelect(
          '''
      SELECT
        s.id AS id,
        s.title AS title,
        COALESCE(bss.display_name, s.display_name) AS display_name,
        s.file_path AS file_path,
        s.type AS type,
        COALESCE(bss.color, s.color) AS color,
        COALESCE(bss.volume, s.volume) AS volume,
        s.created_at AS created_at
      FROM sounds s
      INNER JOIN board_sounds bs
        ON bs.sound_id = s.id
      LEFT JOIN board_sound_settings bss
        ON bss.board_id = bs.board_id
       AND bss.sound_id = bs.sound_id
      WHERE bs.board_id = ?
      ORDER BY bs.sort_order, bs.added_at
      ''',
          variables: [Variable<int>(boardId)],
        )
        .get();

    return rows.map((row) {
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
      );
    }).toList();
  }

  /// Ajoute un son à la board
  Future<void> addSoundToBoard(int boardId, int soundId) async {
    // Vérifier si le son est déjà dans la board
    final existing =
        await (_database.select(_database.boardSounds)..where(
              (b) => b.boardId.equals(boardId) & b.soundId.equals(soundId),
            ))
            .getSingleOrNull();

    if (existing == null) {
      // Calculer le prochain sort_order (compte des sons déjà dans la board)
      final boardSoundsList = await (_database.select(
        _database.boardSounds,
      )..where((b) => b.boardId.equals(boardId))).get();
      final nextOrder = boardSoundsList.length;

      await _database
          .into(_database.boardSounds)
          .insert(
            db.BoardSoundsCompanion.insert(
              boardId: boardId,
              soundId: soundId,
              addedAt: Value(DateTime.now()),
              sortOrder: Value(nextOrder),
            ),
          );
    }
  }

  /// Retire un son de la board
  Future<void> removeSoundFromBoard(int boardId, int soundId) async {
    await (_database.delete(_database.boardSounds)
          ..where((b) => b.boardId.equals(boardId) & b.soundId.equals(soundId)))
        .go();
  }

  /// Réordonne les sons de la board selon la liste fournie (soundIds dans l'ordre voulu)
  Future<void> reorderBoardSounds(
    int boardId,
    List<int> soundIdsInOrder,
  ) async {
    // Applique l'ordre en une transaction pour éviter les états partiels
    // si une écriture échoue au milieu de la séquence.
    await _database.transaction(() async {
      for (var i = 0; i < soundIdsInOrder.length; i++) {
        await (_database.update(_database.boardSounds)..where(
              (b) =>
                  b.boardId.equals(boardId) &
                  b.soundId.equals(soundIdsInOrder[i]),
            ))
            .write(db.BoardSoundsCompanion(sortOrder: Value(i)));
      }
    });
  }

  /// Vérifie si un son est dans la board
  Future<bool> isSoundInBoard(int boardId, int soundId) async {
    final result =
        await (_database.select(_database.boardSounds)..where(
              (b) => b.boardId.equals(boardId) & b.soundId.equals(soundId),
            ))
            .getSingleOrNull();
    return result != null;
  }

  /// Récupère un son par son ID
  Future<domain.Sound?> getSoundById(int id) async {
    final sound = await (_database.select(
      _database.sounds,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
    return sound != null ? SoundModel.toEntity(sound) : null;
  }

  /// Ajoute un son
  Future<int> insertSound(domain.Sound sound) async {
    return await _database
        .into(_database.sounds)
        .insert(SoundModel.toCompanion(sound));
  }

  /// Supprime un son
  Future<void> deleteSound(int id) async {
    await (_database.delete(
      _database.sounds,
    )..where((s) => s.id.equals(id))).go();
  }

  /// Met à jour les réglages d'un son (couleur, volume, point d'entrée) ;
  /// [isProcessed] marque le son comme traité (`null` = inchangé).
  Future<void> updateSoundSettings({
    required int id,
    int? colorValue,
    bool updateColor = false,
    String? displayName,
    bool updateDisplayName = false,
    double? volume,
    int? startOffsetMs,
    bool? isProcessed,
  }) async {
    // Le nom affiché n'est jamais vide : un nom vide retombe sur le titre du
    // fichier (invariant garanti ici, pas seulement par le formulaire).
    String? resolvedName = displayName?.trim();
    if (updateDisplayName && (resolvedName == null || resolvedName.isEmpty)) {
      final row = await (_database.select(_database.sounds)
            ..where((s) => s.id.equals(id)))
          .getSingleOrNull();
      resolvedName = row?.title;
    }
    final companion = db.SoundsCompanion(
      color: updateColor ? Value(colorValue) : const Value.absent(),
      displayName: updateDisplayName && resolvedName != null
          ? Value(resolvedName)
          : const Value.absent(),
      volume: volume != null ? Value(volume) : const Value.absent(),
      startOffsetMs:
          startOffsetMs != null ? Value(startOffsetMs) : const Value.absent(),
      isProcessed:
          isProcessed != null ? Value(isProcessed) : const Value.absent(),
    );
    await (_database.update(
      _database.sounds,
    )..where((s) => s.id.equals(id))).write(companion);
  }

  /// Marque une liste de sons comme traités en une seule requête (validation
  /// en masse depuis la file « À traiter »). Ne touche à aucun autre réglage.
  Future<void> markSoundsProcessed(Iterable<int> ids) async {
    final idList = ids.toList();
    if (idList.isEmpty) return;
    await (_database.update(_database.sounds)
          ..where((s) => s.id.isIn(idList)))
        .write(const db.SoundsCompanion(isProcessed: Value(true)));
  }

  /// Change le type d'un son (corrige une auto-détection par durée erronée).
  Future<void> updateSoundType(int id, domain.SoundType type) async {
    final dbType = switch (type) {
      domain.SoundType.soundEffect => db_sounds.SoundType.soundEffect,
      domain.SoundType.music => db_sounds.SoundType.music,
      domain.SoundType.ambiance => db_sounds.SoundType.ambiance,
    };
    await (_database.update(_database.sounds)..where((s) => s.id.equals(id)))
        .write(db.SoundsCompanion(type: Value(dbType)));
  }

  /// Persiste l'issue d'une extraction waveform (régie musique) : l'enveloppe en
  /// cas de succès, ou le marqueur de génération d'échec pour un `unsupported`.
  /// Un échec `transient` (moteur non prêt) n'écrit rien — on retentera.
  Future<void> persistWaveformProbe(int id, WaveformProbe probe) async {
    if (probe.status == WaveformProbeStatus.transient) return;
    await (_database.update(_database.sounds)..where((s) => s.id.equals(id)))
        .write(db.SoundsCompanion(
      waveform: Value(probe.waveformValue),
      waveformProbeGeneration: Value(probe.generationValue),
    ));
  }

  /// Marque ou démarque un son comme favori (accès rapide en recherche).
  Future<void> setFavorite(int id, bool isFavorite) async {
    await (_database.update(_database.sounds)..where((s) => s.id.equals(id)))
        .write(db.SoundsCompanion(isFavorite: Value(isFavorite)));
  }

  /// Enregistre l'instant de dernière lecture (tri par récence).
  ///
  /// Écriture **muette** : `customUpdate` sans `updates` n'émet aucun
  /// événement `tableUpdates`. Via l'API typée, chaque lecture signalait
  /// « `sounds` modifiée » à `AutoSyncCoordinator`, qui planifiait un push
  /// Drive (ré-export + upload de tous les snapshots, révisions incrémentées)
  /// pour un contenu identique : `last_played_at` est une annotation locale,
  /// absente de l'export du snapshot dossier. Aucun flux `watch()` ne lit
  /// `sounds` ; l'index de recherche est patché en mémoire par l'appelant.
  Future<void> markPlayed(int id, {DateTime? at}) async {
    await _database.customUpdate(
      'UPDATE sounds SET last_played_at = ? WHERE id = ?',
      variables: [
        Variable.withDateTime(at ?? DateTime.now()),
        Variable.withInt(id),
      ],
    );
  }

  /// Met à jour les réglages d'un pad pour une board spécifique.
  Future<void> upsertBoardSoundSettings({
    required int boardId,
    required int soundId,
    int? colorValue,
    bool updateColor = false,
    String? displayName,
    bool updateDisplayName = false,
    double? volume,
  }) async {
    final existing = await _database
        .customSelect(
          '''
      SELECT display_name, color, volume
      FROM board_sound_settings
      WHERE board_id = ? AND sound_id = ?
      LIMIT 1
      ''',
          variables: [Variable<int>(boardId), Variable<int>(soundId)],
        )
        .getSingleOrNull();

    final nextDisplayName = updateDisplayName
        ? displayName
        : existing?.read<String?>('display_name');
    final nextColor = updateColor ? colorValue : existing?.read<int?>('color');
    final nextVolume = volume ?? existing?.read<double?>('volume');

    await _database.customStatement(
      '''
      INSERT INTO board_sound_settings (board_id, sound_id, display_name, color, volume)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(board_id, sound_id) DO UPDATE SET
        display_name = excluded.display_name,
        color = excluded.color,
        volume = excluded.volume
      ''',
      [boardId, soundId, nextDisplayName, nextColor, nextVolume],
    );
  }

  /// Copie les réglages par-board d'une scène source vers une scène cible.
  Future<void> copyBoardSoundSettings(int sourceBoardId, int targetBoardId) async {
    await _database.customStatement(
      '''
      INSERT OR IGNORE INTO board_sound_settings (board_id, sound_id, display_name, color, volume)
      SELECT ?, sound_id, display_name, color, volume
      FROM board_sound_settings
      WHERE board_id = ?
      ''',
      [targetBoardId, sourceBoardId],
    );
  }
}
