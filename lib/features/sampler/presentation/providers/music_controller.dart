part of 'sampler_provider.dart';

/// Gère la lecture, la file d'attente, les fondus et le volume global de la
/// musique, séparement de la logique de plateau (SFX, pads, boards).
///
/// Fichier `part of 'sampler_provider.dart'` : accès intentionnel aux membres
/// privés de [SamplerNotifier] via la même bibliothèque Dart — ce n'est pas un
/// contournement d'encapsulation mais la mécanique `part` conçue pour ça.
class MusicController {
  final SamplerNotifier _o;

  // ── Champs musique ────────────────────────────────────────────────────────

  double _musicVolume = 1.0;
  double _musicVolumeBeforeMute = 1.0;
  static const _sliderFadeDuration = Duration(milliseconds: 120);

  /// Verrou d'avance automatique : chaque opération qui ne doit pas déclencher
  /// l'avance automatique incrémente ce compteur et le décrémente dans finally.
  int _musicAdvanceLockCount = 0;
  bool get _skipMusicAutoAdvance => _musicAdvanceLockCount > 0;

  String? _lastPlaybackError;

  /// Pads musique hors-scène : créés à la volée depuis le sélecteur de la régie.
  final Map<int, PadItem> _offStageMusicPads = {};

  MusicController(this._o);

  // ── API publique ──────────────────────────────────────────────────────────

  double get musicVolume => _musicVolume;

  String? consumeLastPlaybackError() {
    final msg = _lastPlaybackError;
    _lastPlaybackError = null;
    return msg;
  }

  /// Volume effectif : pads musique soumis au volume global, SFX en direct.
  double _effectiveVolume(PadItem padItem) =>
      padItem.pad.isMusicPad
          ? padItem.pad.volume * _musicVolume
          : padItem.pad.volume;

  // ── File d'attente ────────────────────────────────────────────────────────

  void enqueueMusicPad(PadItem padItem) {
    if (padItem.pad.id == _o._state.currentMusicPad?.pad.id) return;
    if (_o._state.musicQueuePadIds.contains(padItem.pad.id)) return;
    _o._state = _o._state.copyWith(
      musicQueuePadIds: [..._o._state.musicQueuePadIds, padItem.pad.id],
    );
    _o._notify();
  }

  void _removeFromMusicQueue(int padId) {
    final nextQueue =
        _o._state.musicQueuePadIds.where((id) => id != padId).toList();
    if (nextQueue.length == _o._state.musicQueuePadIds.length) return;
    _o._state = _o._state.copyWith(musicQueuePadIds: nextQueue);
    _o._notify();
  }

  Future<void> removeFromMusicQueue(int padId) async {
    _removeFromMusicQueue(padId);
  }

  void reorderMusicQueue(int oldIndex, int newIndex) {
    final ids = List<int>.from(_o._state.musicQueuePadIds);
    if (oldIndex < 0 || oldIndex >= ids.length) return;
    if (newIndex < 0 || newIndex >= ids.length) return;
    if (oldIndex == newIndex) return;
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    _o._state = _o._state.copyWith(musicQueuePadIds: ids);
    _o._notify();
  }

  Future<void> clearMusicQueue() async {
    if (_o._state.musicQueuePadIds.isEmpty) return;
    _o._state = _o._state.copyWith(clearMusicQueue: true);
    _o._notify();
  }

  // ── Lecture musique ───────────────────────────────────────────────────────

  Future<void> _toggleMusicPad(PadItem padItem) async {
    if (!padItem.isPlayable) return;

    final currentMusic = _o._state.currentMusicPad;

    if (padItem.isPlaying) {
      await _stopMusicPad(padItem, manual: true);
      return;
    }

    if (_o._state.musicQueuePadIds.contains(padItem.pad.id)) {
      _removeFromMusicQueue(padItem.pad.id);
      return;
    }

    if (currentMusic != null &&
        currentMusic.pad.id != padItem.pad.id &&
        currentMusic.isPlaying) {
      enqueueMusicPad(padItem);
      return;
    }

    await playMusicNow(padItem);
  }

  Future<void> playMusicNow(PadItem padItem) async {
    if (!padItem.isPlayable) return;

    final current = _o._state.currentMusicPad;
    if (current != null &&
        current.pad.id != padItem.pad.id &&
        current.isPlaying) {
      await _stopMusicPad(current, manual: true);
    }

    _o._state = _o._state.copyWith(
      musicQueuePadIds: _o._state.musicQueuePadIds
          .where((id) => id != padItem.pad.id)
          .toList(),
    );
    await _playMusicPad(padItem);
  }

  Future<PadItem?> playMusicBySoundId(int soundId) async {
    final sound = await _o._repository.getSoundById(soundId);
    if (sound == null) {
      _setMusicLoadError();
      return null;
    }
    if (sound.type != SoundType.music) {
      _lastPlaybackError = 'Ce son n\'est pas une musique.';
      _o._notify();
      return null;
    }

    final padItem = await _findOrCreateMusicPadForSound(soundId);
    if (padItem == null) return null;
    final ready = await _prepareMusicPadForPlayback(
      padItem,
      downloadIfNeeded: true,
    );
    if (!ready) {
      _setMusicLoadError(padItem);
      return null;
    }
    await playMusicNow(padItem);
    return padItem;
  }

  Future<PadItem?> enqueueMusicBySoundId(int soundId) async {
    final padItem = await _findOrCreateMusicPadForSound(soundId);
    if (padItem == null) return null;

    await _refreshPadAvailability(padItem);
    if (_isMusicPadPermanentlyUnavailable(padItem)) {
      _setMusicLoadError(padItem);
      return null;
    }

    final padId = padItem.pad.id;
    final current = _o._state.currentMusicPad;

    if (current?.pad.id == padId && (current?.isPlaying ?? false)) {
      return padItem;
    }
    if (_o._state.musicQueuePadIds.contains(padId)) {
      _scheduleMusicPadDownload(padItem);
      return padItem;
    }

    enqueueMusicPad(padItem);
    _scheduleMusicPadDownload(padItem);
    return padItem;
  }

  Future<bool> playNextInQueueNow() async {
    if (_o._state.musicQueuePadIds.isEmpty) return false;

    final nextId = _o._state.musicQueuePadIds.first;
    final next = await _prepareNextQueuedMusic(nextId);
    if (next == null) return false;

    final current = _o._state.currentMusicPad;
    if (current != null && current.isPlaying) {
      await _stopMusicPad(current, manual: true);
    }

    return _playMusicPad(next);
  }

  Future<void> stopCurrentMusic() async {
    final current = _o._state.currentMusicPad;
    if (current == null || !current.isPlaying) return;
    await _stopMusicPad(current, manual: true);
  }

  Future<void> toggleCurrentMusicPlayback() async {
    final current = _o._state.currentMusicPad;
    if (current == null) {
      if (_o._state.musicQueuePadIds.isNotEmpty) {
        await playNextInQueueNow();
      }
      return;
    }
    if (current.isPlaying) {
      await _stopMusicPad(current, manual: true, clearOnAir: false);
      return;
    }
    await _playMusicPad(
      current,
      fromPosition: current.pausedPlaybackPosition,
      soundIndex: current.pausedPlayerIndex,
    );
  }

  Future<void> restartCurrentMusic() async {
    final current = _o._state.currentMusicPad;
    if (current == null || !current.isPlayable) return;
    if (current.isPlaying) {
      _musicAdvanceLockCount++;
      try {
        await current.currentPlayer?.stop();
      } finally {
        if (_musicAdvanceLockCount > 0) _musicAdvanceLockCount--;
      }
    }
    await _playMusicPad(current);
  }

  Future<void> skipToNextMusic() async {
    if (_o._state.musicQueuePadIds.isEmpty) {
      await stopCurrentMusic();
      return;
    }
    await playNextInQueueNow();
  }

  /// Fondu sortant de la musique en cours (sans lancer la file).
  Future<void> fadeOutCurrentMusic(Duration duration) async {
    final current = _o._state.currentMusicPad;
    if (current == null || !current.isPlaying) return;
    if (duration == Duration.zero) {
      await _stopMusicPad(current, manual: true, clearOnAir: false);
      return;
    }
    final player = current.currentPlayer;
    if (player == null) return;

    _musicAdvanceLockCount++;
    try {
      player.fadeVolumeTo(0, duration);
      await Future<void>.delayed(duration);
      _capturePausedPlayback(current);
      await player.stop();
      current.isPlaying = false;
      current._currentPlayerIndex = null;
      _o._notify();
    } finally {
      if (_musicAdvanceLockCount > 0) _musicAdvanceLockCount--;
    }
  }

  /// Enchaîne vers la musique suivante avec un fondu enchaîné.
  Future<void> crossfadeToNextMusic(Duration duration) async {
    if (_o._state.musicQueuePadIds.isEmpty) return;

    if (duration == Duration.zero) {
      await playNextInQueueNow();
      return;
    }

    final current = _o._state.currentMusicPad;
    if (current == null || !current.isPlaying) {
      await _fadeInNextFromQueue(duration);
      return;
    }

    final nextId = _o._state.musicQueuePadIds.first;
    final next = await _prepareNextQueuedMusic(nextId);
    if (next == null) return;

    final currentPlayer = current.currentPlayer;
    if (currentPlayer == null) return;

    final soundIndex = _o._pickSoundIndex(next);
    final nextPlayer = next.slots[soundIndex].player;
    if (nextPlayer == null) {
      _setMusicLoadError(next);
      return;
    }
    final targetVolume = _effectiveVolume(next);

    _musicAdvanceLockCount++;
    try {
      _o._state = _o._state.copyWith(
        musicQueuePadIds: _o._state.musicQueuePadIds.sublist(1),
      );
      _o._notify();

      await nextPlayer.playAtVolume(0);
      next._currentPlayerIndex = soundIndex;
      next.isPlaying = true;

      currentPlayer.fadeVolumeTo(0, duration);
      nextPlayer.fadeVolumeTo(targetVolume, duration);

      await Future<void>.delayed(duration);

      if (currentPlayer.isPlaying) {
        await currentPlayer.stop();
      }
      current.isPlaying = false;
      current._currentPlayerIndex = null;

      _o._state = _o._state.copyWith(currentMusicPad: next);
      _o._notify();
    } finally {
      if (_musicAdvanceLockCount > 0) _musicAdvanceLockCount--;
    }
  }

  // ── Volume musique ────────────────────────────────────────────────────────

  Future<void> setMusicVolume(double value, {bool smooth = false}) async {
    final clamped = value.clamp(0.0, 1.0);
    if (_musicVolume == clamped) return;
    if (clamped > 0) {
      _musicVolumeBeforeMute = clamped;
    }
    _musicVolume = clamped;
    _applyMusicVolumeToPlayingPads(smooth: smooth);
    _o._notify();
  }

  Future<void> toggleMusicMute() async {
    if (_musicVolume > 0) {
      _musicVolumeBeforeMute = _musicVolume;
      await setMusicVolume(0);
      return;
    }
    await setMusicVolume(
      _musicVolumeBeforeMute > 0 ? _musicVolumeBeforeMute : 1.0,
    );
  }

  // ── Résolution de pads ────────────────────────────────────────────────────

  PadItem? _resolvePadItem(int? padId) {
    if (padId == null) return null;
    for (final padItem in _o._state.pads) {
      if (padItem.pad.id == padId) return padItem;
    }
    return _offStageMusicPads[padId];
  }

  /// Résout un pad musique par id — sur la scène ou hors-scène (régie seule).
  PadItem? resolveMusicPad(int padId) => _resolvePadItem(padId);

  PadItem? _findPadItemForSound(int soundId) {
    for (final padItem in _o._state.pads) {
      if (padItem.pad.sounds.any((sound) => sound.id == soundId)) {
        return padItem;
      }
    }
    for (final padItem in _offStageMusicPads.values) {
      if (padItem.pad.sounds.any((sound) => sound.id == soundId)) {
        return padItem;
      }
    }
    return null;
  }

  /// Pad musique correspondant à un son, sur la scène ou hors-scène.
  PadItem? findMusicPadForSound(int soundId) => _findPadItemForSound(soundId);

  // ── Synchronisation état ──────────────────────────────────────────────────

  void _syncMusicStateWithPads() {
    final currentId = _o._state.currentMusicPad?.pad.id;
    final nextCurrent = _resolvePadItem(currentId);
    final nextQueue = _o._state.musicQueuePadIds
        .where((id) => _resolvePadItem(id) != null && id != nextCurrent?.pad.id)
        .toList();

    if (nextCurrent == _o._state.currentMusicPad &&
        _listEquals(nextQueue, _o._state.musicQueuePadIds)) {
      return;
    }

    _o._state = _o._state.copyWith(
      currentMusicPad: nextCurrent,
      musicQueuePadIds: nextQueue,
      clearCurrentMusicPad: nextCurrent == null && currentId != null,
    );
  }

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

  // ── Interne ───────────────────────────────────────────────────────────────

  Future<bool> _playMusicPad(
    PadItem padItem, {
    Duration? fromPosition,
    int? soundIndex,
  }) async {
    if (!padItem.pad.isMusicPad) return false;

    if (!padItem.isPlayable) {
      final ready = await _prepareMusicPadForPlayback(
        padItem,
        downloadIfNeeded: true,
      );
      if (!ready) {
        _setMusicLoadError(padItem);
        return false;
      }
    }

    final resumePosition = fromPosition;
    final resumeIndex = soundIndex;

    final index = () {
      if (resumeIndex != null &&
          resumeIndex < padItem.slots.length &&
          padItem.slots[resumeIndex].isReady) {
        return resumeIndex;
      }
      return _o._pickSoundIndex(padItem);
    }();
    final player = padItem.slots[index].player;
    if (player == null) {
      _setMusicLoadError(padItem);
      return false;
    }

    padItem.clearPausedPlayback();
    _o._state = _o._state.copyWith(
      currentMusicPad: padItem,
      musicQueuePadIds: _o._state.musicQueuePadIds
          .where((id) => id != padItem.pad.id)
          .toList(),
    );

    player.setVolume(_effectiveVolume(padItem));
    if (resumePosition != null && resumePosition > Duration.zero) {
      await player.playFromPosition(resumePosition);
    } else {
      await player.play();
    }
    _o._markPlayedAt(padItem, index);
    _o._notify();
    return true;
  }

  Future<void> _stopMusicPad(
    PadItem padItem, {
    required bool manual,
    bool clearOnAir = true,
  }) async {
    if (manual) {
      _musicAdvanceLockCount++;
    }
    if (!clearOnAir && manual) {
      _capturePausedPlayback(padItem);
    }
    try {
      await padItem.currentPlayer?.stop();
    } finally {
      if (manual) {
        if (_musicAdvanceLockCount > 0) _musicAdvanceLockCount--;
      }
    }

    var nextState = _o._state;
    if (clearOnAir && _o._state.currentMusicPad?.pad.id == padItem.pad.id) {
      nextState = nextState.copyWith(clearCurrentMusicPad: true);
    }
    if (_o._state.musicQueuePadIds.contains(padItem.pad.id)) {
      nextState = nextState.copyWith(
        musicQueuePadIds: nextState.musicQueuePadIds
            .where((id) => id != padItem.pad.id)
            .toList(),
      );
    }
    _o._state = nextState;
    _o._notify();
  }

  void _handleMusicPlaybackEnded(PadItem padItem) {
    if (_skipMusicAutoAdvance) return;
    if (_o._state.currentMusicPad?.pad.id != padItem.pad.id) return;

    final queue = _o._state.musicQueuePadIds;
    _o._state = _o._state.copyWith(clearCurrentMusicPad: true);
    _o._notify();

    if (queue.isEmpty) return;

    final nextId = queue.first;
    final next = _resolvePadItem(nextId);
    if (next == null) {
      _setMusicLoadError();
      return;
    }
    unawaited(_playMusicPad(next));
  }

  void _clearMusicState() {
    _o._state = _o._state.copyWith(
      clearCurrentMusicPad: true,
      clearMusicQueue: true,
    );
  }

  Future<PadItem?> _findOrCreateMusicPadForSound(int soundId) async {
    var existing = _findPadItemForSound(soundId);
    if (existing != null) {
      for (var i = 0; i < existing.pad.sounds.length; i++) {
        await _o._syncPadSoundMetadata(existing, i);
      }
      return existing;
    }

    final boardId = _o._activeBoardId;
    if (boardId != null) {
      final padIdBySound =
          await _o._repository.getSoundIdToFirstPadIdInBoard(boardId);
      if (padIdBySound.containsKey(soundId)) {
        await _o.loadSounds(boardId: boardId);
        existing = _findPadItemForSound(soundId);
        if (existing != null) return existing;
      }
    }

    return _createOffStageMusicPad(soundId);
  }

  Future<void> _refreshPadAvailability(PadItem padItem) async {
    if (padItem.isPlayable) return;
    await _o._loadPlayersForPad(padItem, padItem.pad);
  }

  Future<bool> _prepareMusicPadForPlayback(
    PadItem padItem, {
    required bool downloadIfNeeded,
  }) async {
    if (padItem.isPlayable) return true;
    await _o._loadPlayersForPad(padItem, padItem.pad);
    if (padItem.isPlayable) return true;
    if (!downloadIfNeeded) return false;
    return _o.downloadAndLoadPad(padItem);
  }

  bool _isMusicPadPermanentlyUnavailable(PadItem padItem) {
    return padItem.unavailabilityReason == PadUnavailabilityReason.offline ||
        padItem.unavailabilityReason == PadUnavailabilityReason.missingFile;
  }

  void _scheduleMusicPadDownload(PadItem padItem) {
    if (padItem.isPlayable) return;
    if (_isMusicPadPermanentlyUnavailable(padItem)) return;
    if (padItem.pendingDownloadCount == 0) return;
    unawaited(_o.downloadAndLoadPad(padItem));
  }

  Future<PadItem?> _createOffStageMusicPad(int soundId) async {
    try {
      final sound = await _o._repository.getSoundById(soundId);
      if (sound == null) {
        _setMusicLoadError();
        return null;
      }
      if (sound.type != SoundType.music) {
        _lastPlaybackError = 'Ce son n\'est pas une musique.';
        _o._notify();
        return null;
      }

      final pad = Pad(
        id: -soundId,
        boardId: -1,
        sortOrder: 0,
        createdAt: DateTime.now(),
        sounds: [sound],
      );
      final padItem = PadItem(pad: pad);
      await _o._loadPlayersForPad(padItem, pad);
      _offStageMusicPads[pad.id] = padItem;
      return padItem;
    } catch (e) {
      debugPrint('Impossible de préparer la musique pour la régie: $e');
      _lastPlaybackError = 'Impossible de préparer cette musique.';
      _o._notify();
      return null;
    }
  }

  void _setMusicLoadError([PadItem? padItem]) {
    _lastPlaybackError = switch (padItem?.unavailabilityReason) {
      PadUnavailabilityReason.offline => 'Son indisponible hors-ligne.',
      PadUnavailabilityReason.missingFile => 'Fichier audio introuvable.',
      _ => 'Fichier audio introuvable ou indisponible hors-ligne.',
    };
    _o._notify();
  }

  void _capturePausedPlayback(PadItem padItem) {
    final player = padItem.currentPlayer;
    if (player == null) return;
    padItem.pausedPlaybackPosition = player.position;
    padItem.pausedPlayerIndex = padItem._currentPlayerIndex;
  }

  Future<void> _fadeInNextFromQueue(Duration duration) async {
    if (_o._state.musicQueuePadIds.isEmpty) return;

    final nextId = _o._state.musicQueuePadIds.first;
    final next = await _prepareNextQueuedMusic(nextId);
    if (next == null) return;

    final previous = _o._state.currentMusicPad;

    _musicAdvanceLockCount++;
    try {
      _o._state = _o._state.copyWith(
        musicQueuePadIds: _o._state.musicQueuePadIds.sublist(1),
      );
      _o._notify();

      final soundIndex = _o._pickSoundIndex(next);
      final nextPlayer = next.slots[soundIndex].player;
      if (nextPlayer == null) {
        _setMusicLoadError(next);
        return;
      }
      final targetVolume = _effectiveVolume(next);

      await nextPlayer.playAtVolume(0);
      next._currentPlayerIndex = soundIndex;
      next.isPlaying = true;
      nextPlayer.fadeVolumeTo(targetVolume, duration);

      await Future<void>.delayed(duration);

      if (previous != null && previous.pad.id != next.pad.id) {
        await previous.currentPlayer?.stop();
        previous.isPlaying = false;
        previous._currentPlayerIndex = null;
      }

      _o._state = _o._state.copyWith(currentMusicPad: next);
      _o._notify();
    } finally {
      if (_musicAdvanceLockCount > 0) _musicAdvanceLockCount--;
    }
  }

  Future<PadItem?> _prepareNextQueuedMusic(int nextId) async {
    final next = _resolvePadItem(nextId);
    if (next == null) {
      _setMusicLoadError();
      return null;
    }

    if (!next.isPlayable) {
      final ready = await _prepareMusicPadForPlayback(
        next,
        downloadIfNeeded: true,
      );
      if (!ready) {
        _setMusicLoadError(next);
        return null;
      }
    }

    return next;
  }

  void _applyMusicVolumeToPlayingPads({bool smooth = false}) {
    for (final padItem in _o._state.pads) {
      if (padItem.isPlaying && padItem.pad.isMusicPad) {
        _applyEffectiveVolumeToPlayer(padItem, smooth: smooth);
      }
    }
    for (final padItem in _offStageMusicPads.values) {
      if (padItem.isPlaying) {
        _applyEffectiveVolumeToPlayer(padItem, smooth: smooth);
      }
    }
  }

  void _applyEffectiveVolumeToPlayer(PadItem padItem, {bool smooth = false}) {
    final player = padItem.currentPlayer;
    if (player == null) return;
    final volume = _effectiveVolume(padItem);
    if (smooth) {
      player.fadeVolumeTo(volume, _sliderFadeDuration);
    } else {
      player.setVolume(volume);
    }
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _disposeOffStagePads() {
    for (final padItem in _offStageMusicPads.values) {
      padItem.dispose();
    }
    _offStageMusicPads.clear();
  }
}
