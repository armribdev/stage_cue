part of 'local_sound_datasource.dart';

/// Lecture et mutations des sons (CRUD, scènes, réglages, favoris).
/// Méthodes de [LocalSoundDataSource] extraites via extension dans le même `part`.
extension LocalSoundCrud on LocalSoundDataSource {
  Future<List<domain.Sound>> getAllSounds() async {
    final sounds = await _database.select(_database.sounds).get();
    return sounds.map((s) => SoundModel.toEntity(s)).toList();
  }

  Future<domain.Sound?> getSoundById(int id) async {
    final sound = await (_database.select(
      _database.sounds,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
    return sound != null ? SoundModel.toEntity(sound) : null;
  }

  Future<int> insertSound(domain.Sound sound) async {
    return await _database
        .into(_database.sounds)
        .insert(SoundModel.toCompanion(sound));
  }

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
      final row = await (_database.select(
        _database.sounds,
      )..where((s) => s.id.equals(id))).getSingleOrNull();
      resolvedName = row?.title;
    }
    final companion = db.SoundsCompanion(
      color: updateColor ? Value(colorValue) : const Value.absent(),
      displayName: updateDisplayName && resolvedName != null
          ? Value(resolvedName)
          : const Value.absent(),
      volume: volume != null ? Value(volume) : const Value.absent(),
      startOffsetMs: startOffsetMs != null
          ? Value(startOffsetMs)
          : const Value.absent(),
      isProcessed: isProcessed != null
          ? Value(isProcessed)
          : const Value.absent(),
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
    await (_database.update(_database.sounds)..where((s) => s.id.isIn(idList)))
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

  /// Persiste l'issue d'une extraction waveform (régie musique) : l'enveloppe et
  /// la génération courante en cas de succès, ou le seul marqueur de génération
  /// pour un `unsupported`. Un échec `unsupported` n'efface JAMAIS une enveloppe
  /// existante : un re-sondage (rafraîchissement, régénération) qui échoue ne
  /// doit pas détruire une waveform valable. Un échec `transient` (moteur non
  /// prêt) n'écrit rien — on retentera.
  Future<void> persistWaveformProbe(int id, WaveformProbe probe) async {
    if (probe.status == WaveformProbeStatus.transient) return;
    await (_database.update(
      _database.sounds,
    )..where((s) => s.id.equals(id))).write(
      db.SoundsCompanion(
        waveform: probe.status == WaveformProbeStatus.success
            ? Value(probe.waveformValue)
            : const Value.absent(),
        waveformProbeGeneration: Value(probe.generationValue),
      ),
    );
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
}
