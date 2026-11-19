part of 'sampler_provider.dart';

/// Fondus de la musique : sortant, enchaîné, entrée depuis la file.
/// Méthodes de [MusicController] extraites via extension dans le même `part`.

extension MusicFades on MusicController {
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
      await player.fadeEnvelope(
        _busVolume(current),
        duration,
        fadeIn: false,
        curve: FadeCurve.cubic,
      );
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
    final targetVolume = _busVolume(next);

    _musicAdvanceLockCount++;
    try {
      _o._state = _o._state.copyWith(
        musicQueuePadIds: _o._state.musicQueuePadIds.sublist(1),
      );
      _o._notify();

      await nextPlayer.playAtVolume(
        0,
        startOffset: _startOffsetOf(next, soundIndex, nextPlayer),
      );
      next._currentPlayerIndex = soundIndex;
      next.isPlaying = true;

      // Équi-puissance : les deux voix se croisent à loudness constante, sans
      // creux au milieu (contrairement à un croisement cubique).
      await Future.wait([
        currentPlayer.fadeEnvelope(
          _busVolume(current),
          duration,
          fadeIn: false,
          curve: FadeCurve.equalPower,
        ),
        nextPlayer.fadeEnvelope(
          targetVolume,
          duration,
          fadeIn: true,
          curve: FadeCurve.equalPower,
        ),
      ]);

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

  /// Coupe un pad musique avec un fondu sortant, sans mémoriser de position
  /// de reprise (contrairement à [fadeOutCurrentMusic]) : le pad repart de
  /// zéro — et pioche un nouveau son via [_pickSoundIndex] pour un multipad —
  /// au prochain tap plutôt que de reprendre en pause.
  Future<void> _fadeOutAndStopMusicPad(
    PadItem padItem,
    Duration duration,
  ) async {
    final player = padItem.currentPlayer;
    if (duration == Duration.zero || player == null) {
      await _stopMusicPad(padItem, manual: true);
      return;
    }

    _musicAdvanceLockCount++;
    try {
      await player.fadeEnvelope(
        _busVolume(padItem),
        duration,
        fadeIn: false,
        curve: FadeCurve.cubic,
      );
    } finally {
      if (_musicAdvanceLockCount > 0) _musicAdvanceLockCount--;
    }
    await _stopMusicPad(padItem, manual: true);
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
      final targetVolume = _busVolume(next);

      await nextPlayer.playAtVolume(
        0,
        startOffset: _startOffsetOf(next, soundIndex, nextPlayer),
      );
      next._currentPlayerIndex = soundIndex;
      next.isPlaying = true;
      await nextPlayer.fadeEnvelope(
        targetVolume,
        duration,
        fadeIn: true,
        curve: FadeCurve.equalPower,
      );

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
}
