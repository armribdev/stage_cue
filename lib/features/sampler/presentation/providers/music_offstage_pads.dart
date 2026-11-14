part of 'sampler_provider.dart';

/// Résolution des pads musique (scène ou hors-scène), réserve hors-scène,
/// création et libération.
/// Méthodes de [MusicController] extraites via extension dans le même `part`.

extension MusicOffStagePads on MusicController {
  PadItem? _resolvePadItem(int? padId) {
    if (padId == null) return null;
    for (final padItem in _o._state.pads) {
      if (padItem.pad.id == padId) return padItem;
    }
    return _offStageMusicPads[padId];
  }

  /// Résout un pad musique par id — sur la scène ou hors-scène (régie seule).
  PadItem? resolveMusicPad(int padId) => _resolvePadItem(padId);

  /// Pad musique **simple** (un seul son) correspondant à un son, sur la scène
  /// ou hors-scène. Un multipad ne doit jamais être résolu ici : depuis la
  /// recherche, on ne veut déclencher que le son précis choisi, pas laisser le
  /// multipad piocher parmi ses variantes ([_pickSoundIndex]).
  PadItem? _findSimpleMusicPadForSound(int soundId) {
    for (final padItem in _o._state.pads) {
      final sounds = padItem.pad.sounds;
      if (sounds.length == 1 && sounds.first.id == soundId) return padItem;
    }
    for (final padItem in _offStageMusicPads.values) {
      final sounds = padItem.pad.sounds;
      if (sounds.length == 1 && sounds.first.id == soundId) return padItem;
    }
    return null;
  }

  /// Pad musique correspondant à un son, sur la scène ou hors-scène — ne
  /// renvoie jamais un multipad (voir [_findSimpleMusicPadForSound]).
  PadItem? findMusicPadForSound(int soundId) =>
      _findSimpleMusicPadForSound(soundId);

  /// Réinjecte en mémoire les métadonnées à jour d'un son (point d'entrée,
  /// volume, etc.) sur tous les pads qui le référencent, sans toucher aux
  /// lecteurs audio en cours — le nouveau point d'entrée s'applique à la
  /// prochaine lecture seulement.
  Future<void> refreshSoundMetadata(int soundId) async {
    await _syncSoundMetadataInPads(_o._state.pads, soundId);
    await _syncSoundMetadataInPads(_offStageMusicPads.values, soundId);
    _o._notify();
  }

  Future<void> _syncSoundMetadataInPads(
    Iterable<PadItem> padItems,
    int soundId,
  ) async {
    for (final padItem in padItems) {
      for (var i = 0; i < padItem.pad.sounds.length; i++) {
        if (padItem.pad.sounds[i].id == soundId) {
          await _o._syncPadSoundMetadata(padItem, i);
        }
      }
    }
  }

  /// Détache le pad musique en cours de lecture vers la réserve hors-scène afin
  /// qu'il survive à un changement de plateau (tapis sonore continu) : il n'est
  /// pas disposé par le rechargement et reste piloté par la régie. Idempotent si
  /// le pad courant est déjà hors-scène.
  void _detachPlayingMusicToOffStage() {
    final current = _o._state.currentMusicPad;
    if (current == null || !current.isPlaying) return;
    _offStageMusicPads[current.pad.id] = current;
  }

  /// Ré-adopte un pad musique précédemment détaché hors-scène quand on revient
  /// sur son plateau d'origine (le retire de la réserve pour le remettre en
  /// scène), évitant la création d'un second lecteur pour un son déjà en cours.
  PadItem? _reclaimOffStagePad(int padId) => _offStageMusicPads.remove(padId);

  /// true si [padId] correspond à un pad conservé hors-scène (à ne pas disposer
  /// lors du rechargement du plateau).
  bool _isKeptOffStage(int padId) => _offStageMusicPads.containsKey(padId);

  /// Supprime les pads hors-scène qui ne jouent plus (appelé au changement de plateau).
  void cleanupOffStagePads() {
    final toRemove = _offStageMusicPads.entries
        .where((e) => !e.value.isPlaying)
        .map((e) => e.key)
        .toList();
    for (final id in toRemove) {
      _offStageMusicPads.remove(id)?.dispose();
    }
  }

  Future<PadItem?> _findOrCreateMusicPadForSound(int soundId) async {
    var existing = _findSimpleMusicPadForSound(soundId);
    if (existing != null) {
      for (var i = 0; i < existing.pad.sounds.length; i++) {
        await _o._syncPadSoundMetadata(existing, i);
      }
      return existing;
    }

    final boardId = _o._activeBoardId;
    if (boardId != null) {
      final padIdBySound = await _o._repository.getSoundIdToFirstPadIdInBoard(
        boardId,
      );
      if (padIdBySound.containsKey(soundId)) {
        await _o.loadSounds(boardId: boardId);
        existing = _findSimpleMusicPadForSound(soundId);
        if (existing != null) {
          for (var i = 0; i < existing.pad.sounds.length; i++) {
            await _o._syncPadSoundMetadata(existing, i);
          }
          return existing;
        }
      }
    }

    return _createOffStageMusicPad(soundId);
  }

  Future<PadItem?> _createOffStageMusicPad(int soundId) async {
    final Sound? sound;
    try {
      sound = await _o._repository.getSoundById(soundId);
    } catch (e) {
      AudioLoadLog.warn('Impossible de préparer la musique pour la régie : $e');
      _reportPlaybackError('Impossible de préparer cette musique.');
      return null;
    }
    if (sound == null) {
      _setMusicLoadError();
      return null;
    }
    if (sound.type != SoundType.music) {
      _reportPlaybackError('Ce son n\'est pas une musique.');
      return null;
    }

    final padItem = await _o._buildOffStagePad(sound);
    if (padItem == null) {
      _reportPlaybackError('Impossible de préparer cette musique.');
      return null;
    }
    _offStageMusicPads[padItem.pad.id] = padItem;
    return padItem;
  }

  void _disposeOffStagePads() {
    for (final padItem in _offStageMusicPads.values) {
      padItem.dispose();
    }
    _offStageMusicPads.clear();
  }
}
