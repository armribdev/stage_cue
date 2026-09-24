part of 'sampler_provider.dart';

/// Voie ambiance de la régie : une seule ambiance à la fois, jouée en boucle
/// depuis son point d'entrée. Un nouveau déclenchement remplace l'ambiance en
/// cours par un fondu enchaîné — pas de file, pas de reprise, pas de pause
/// (voir décision 0024).
///
/// Fichier `part of 'sampler_provider.dart'`, comme [MusicController] : accès
/// intentionnel aux membres privés de [SamplerNotifier].
class AmbianceController {
  final SamplerNotifier _o;

  double _ambianceVolume = 1.0;
  double _ambianceVolumeBeforeMute = 1.0;
  static const _sliderFadeDuration = Duration(milliseconds: 120);

  /// Fondu par défaut quand on coupe l'ambiance (tap sur le pad qui joue, ✕
  /// de la régie sans durée choisie) : une ambiance ne se coupe jamais sèche.
  /// Un tapis sonore doit s'effacer sans qu'on remarque sa sortie — d'où des
  /// durées nettement plus longues que les options de fondu musique.
  static const stopFadeDuration = Duration(seconds: 3);

  /// Fondu enchaîné par défaut quand une ambiance en remplace une autre.
  static const switchFadeDuration = Duration(seconds: 4);

  /// Fondu d'entrée quand une ambiance démarre sur un silence : elle monte
  /// progressivement au lieu d'arriver d'un coup à plein volume.
  static const fadeInDuration = Duration(seconds: 3);

  /// Verrou de transition : pendant un fondu, les notifications d'arrêt des
  /// lecteurs ne doivent pas effacer l'ambiance à l'antenne.
  int _transitionLockCount = 0;
  bool get _inTransition => _transitionLockCount > 0;

  /// Pads ambiance hors-scène : créés depuis le sélecteur de la régie, ou
  /// détachés du plateau quittant la scène pendant qu'ils jouent.
  final Map<int, PadItem> _offStageAmbiancePads = {};

  AmbianceController(this._o);

  // ── API publique ──────────────────────────────────────────────────────────

  double get ambianceVolume => _ambianceVolume;

  /// Gain appliqué aux pads ambiance, courbé comme le fader musique.
  double get _gain => _perceptualGain(_ambianceVolume);

  /// Résout un pad ambiance par id — sur la scène ou hors-scène.
  PadItem? resolveAmbiancePad(int padId) => _resolvePadItem(padId);

  Future<void> _toggleAmbiancePad(PadItem padItem) async {
    if (padItem.isPlaying) {
      await _fadeOutAndStop(padItem, stopFadeDuration);
      return;
    }
    await playAmbianceNow(padItem);
  }

  /// Met [padItem] à l'antenne. Si une autre ambiance joue, elle est
  /// remplacée par un fondu enchaîné de [crossfade] (`Duration.zero` =
  /// coupe sèche). [soundIndex] force une variante d'un multipad.
  Future<bool> playAmbianceNow(
    PadItem padItem, {
    int? soundIndex,
    Duration crossfade = switchFadeDuration,
  }) async {
    if (!padItem.pad.isAmbiancePad) return false;

    if (!padItem.isPlayable) {
      final ready = await _preparePadForPlayback(padItem);
      if (!ready) {
        _o._music._setMusicLoadError(padItem);
        return false;
      }
    }

    final index = soundIndex != null &&
            soundIndex >= 0 &&
            soundIndex < padItem.slots.length &&
            padItem.slots[soundIndex].isReady
        ? soundIndex
        : _o._pickSoundIndex(padItem);

    final previous = _o._state.currentAmbiancePad;
    final previousPlayer = previous?.currentPlayer;
    final previousPlaying = previous != null && previous.isPlaying;

    // Même variante déjà à l'antenne : rien à faire.
    if (previousPlaying &&
        identical(previous, padItem) &&
        padItem._currentPlayerIndex == index) {
      return true;
    }

    var player = padItem.slots[index].player;
    if (player == null) {
      _o._music._setMusicLoadError(padItem);
      return false;
    }

    await _o._syncPadSoundMetadata(padItem, index);
    final volume = _o._effectiveVolume(padItem, soundIndex: index);
    final startOffset = _o._music._startOffsetOf(padItem, index, player);

    _transitionLockCount++;
    try {
      if (previousPlaying &&
          previousPlayer != null &&
          crossfade > Duration.zero) {
        final previousVolume = _o._effectiveVolume(previous);
        await player.playAtVolume(0, startOffset: startOffset, looping: true);
        _setOnAir(padItem, index);

        // Équi-puissance, comme le fondu enchaîné musique.
        await Future.wait([
          previousPlayer.fadeEnvelope(
            previousVolume,
            crossfade,
            fadeIn: false,
            curve: FadeCurve.equalPower,
          ),
          player.fadeEnvelope(
            volume,
            crossfade,
            fadeIn: true,
            curve: FadeCurve.equalPower,
          ),
        ]);
        await previousPlayer.stop();
        if (!identical(previous, padItem)) {
          previous.isPlaying = false;
          previous._currentPlayerIndex = null;
        }
      } else {
        if (previousPlaying) {
          if (identical(previous, padItem)) {
            await previousPlayer?.stop();
          } else {
            await _stopPadPlayers(previous);
          }
        }

        // Démarre en silence puis monte (sauf coupe sèche demandée).
        final fadeIn = crossfade > Duration.zero;
        final initialVolume = fadeIn ? 0.0 : volume;
        var started = await player.playFromPosition(
          startOffset,
          volume: initialVolume,
          looping: true,
          loopStart: startOffset,
        );
        if (!started) {
          // Source SoLoud invalidée (ex. éditeur de point d'entrée) : recharge.
          await _o._loadSlotAtIndex(padItem, index, downloadIfNeeded: true);
          _o._attachPlayerListeners(padItem);
          final reloaded = padItem.slots[index].player;
          if (reloaded != null) {
            player = reloaded;
            started = await reloaded.playFromPosition(
              startOffset,
              volume: initialVolume,
              looping: true,
              loopStart: startOffset,
            );
          }
        }
        if (!started) {
          if (previousPlaying &&
              _o._state.currentAmbiancePad?.pad.id == previous.pad.id) {
            _o._state = _o._state.copyWith(clearCurrentAmbiancePad: true);
          }
          _o._music._setMusicLoadError(padItem);
          return false;
        }
        _setOnAir(padItem, index);
        if (fadeIn) {
          // Non attendu : l'ambiance est déjà à l'antenne, la montée se fait
          // en fond. Courbe cubique : départ très doux, sans à-coup audible.
          unawaited(
            player.fadeEnvelope(
              volume,
              fadeInDuration,
              fadeIn: true,
              curve: FadeCurve.cubic,
            ),
          );
        }
      }
    } finally {
      if (_transitionLockCount > 0) _transitionLockCount--;
    }

    _o._markPlayedAt(padItem, index);
    _o._notify();
    return true;
  }

  /// Lance l'ambiance d'un son précis (sélecteur de la régie) : réutilise un
  /// pad ambiance simple du plateau s'il existe, sinon un pad hors-scène.
  Future<PadItem?> playAmbianceBySoundId(int soundId) async {
    final sound = await _o._repository.getSoundById(soundId);
    if (sound == null) {
      _o._music._setMusicLoadError();
      return null;
    }
    if (sound.type != SoundType.ambiance) {
      _o._music._reportPlaybackError('Ce son n\'est pas une ambiance.');
      return null;
    }

    var padItem = _findSimpleAmbiancePadForSound(soundId);
    if (padItem != null) {
      for (var i = 0; i < padItem.pad.sounds.length; i++) {
        await _o._syncPadSoundMetadata(padItem, i);
      }
    } else {
      padItem = await _o._buildOffStagePad(sound);
      if (padItem == null) {
        _o._music._reportPlaybackError(
          'Impossible de préparer cette ambiance.',
        );
        return null;
      }
      _offStageAmbiancePads[padItem.pad.id] = padItem;
    }

    final started = await playAmbianceNow(padItem);
    return started ? padItem : null;
  }

  /// Coupe l'ambiance à l'antenne avec un fondu de [fade].
  Future<void> stopCurrentAmbiance({
    Duration fade = stopFadeDuration,
  }) async {
    final current = _o._state.currentAmbiancePad;
    if (current == null) return;
    await _fadeOutAndStop(current, fade);
  }

  // ── Volume ambiance ───────────────────────────────────────────────────────

  Future<void> setAmbianceVolume(double value, {bool smooth = false}) async {
    final clamped = value.clamp(0.0, 1.0);
    if (_ambianceVolume == clamped) return;
    if (clamped > 0) {
      _ambianceVolumeBeforeMute = clamped;
    }
    _ambianceVolume = clamped;
    _applyVolumeToCurrent(smooth: smooth);
    _o._notify();
  }

  Future<void> toggleAmbianceMute() async {
    if (_ambianceVolume > 0) {
      _ambianceVolumeBeforeMute = _ambianceVolume;
      await setAmbianceVolume(0);
      return;
    }
    await setAmbianceVolume(
      _ambianceVolumeBeforeMute > 0 ? _ambianceVolumeBeforeMute : 1.0,
    );
  }

  void _applyVolumeToCurrent({bool smooth = false}) {
    final current = _o._state.currentAmbiancePad;
    if (current == null || !current.isPlaying) return;
    final player = current.currentPlayer;
    if (player == null) return;
    final volume = _o._effectiveVolume(current);
    if (smooth) {
      player.fadeVolumeTo(volume, _sliderFadeDuration);
    } else {
      player.setVolume(volume);
    }
  }

  // ── Hors-scène ────────────────────────────────────────────────────────────

  PadItem? _resolvePadItem(int? padId) {
    if (padId == null) return null;
    for (final padItem in _o._state.pads) {
      if (padItem.pad.id == padId) return padItem;
    }
    return _offStageAmbiancePads[padId];
  }

  /// Pad ambiance **simple** (un seul son) correspondant à un son — jamais un
  /// multipad, pour ne jouer que le son précis choisi dans le sélecteur.
  PadItem? _findSimpleAmbiancePadForSound(int soundId) {
    bool matches(PadItem padItem) {
      final sounds = padItem.pad.sounds;
      return padItem.pad.isAmbiancePad &&
          sounds.length == 1 &&
          sounds.first.id == soundId;
    }

    for (final padItem in _o._state.pads) {
      if (matches(padItem)) return padItem;
    }
    for (final padItem in _offStageAmbiancePads.values) {
      if (matches(padItem)) return padItem;
    }
    return null;
  }

  /// Détache l'ambiance qui joue vers la réserve hors-scène pour qu'elle
  /// survive au changement de plateau.
  void _detachPlayingToOffStage() {
    final current = _o._state.currentAmbiancePad;
    if (current == null || !current.isPlaying) return;
    _offStageAmbiancePads[current.pad.id] = current;
  }

  PadItem? _reclaimOffStagePad(int padId) =>
      _offStageAmbiancePads.remove(padId);

  bool _isKeptOffStage(int padId) =>
      _offStageAmbiancePads.containsKey(padId);

  /// Libère les pads hors-scène qui ne jouent plus.
  void cleanupOffStagePads() {
    final toRemove = _offStageAmbiancePads.entries
        .where((e) => !e.value.isPlaying)
        .map((e) => e.key)
        .toList();
    for (final id in toRemove) {
      _offStageAmbiancePads.remove(id)?.dispose();
    }
  }

  /// Réinjecte les métadonnées à jour d'un son dans les pads hors-scène (les
  /// pads du plateau sont traités par [MusicController.refreshSoundMetadata]).
  Future<void> refreshOffStageSoundMetadata(int soundId) async {
    await _o._music._syncSoundMetadataInPads(
      _offStageAmbiancePads.values,
      soundId,
    );
  }

  void _syncStateWithPads() {
    final current = _o._state.currentAmbiancePad;
    if (current == null) return;
    final resolved = _resolvePadItem(current.pad.id);
    if (identical(resolved, current)) return;
    _o._state = resolved == null
        ? _o._state.copyWith(clearCurrentAmbiancePad: true)
        : _o._state.copyWith(currentAmbiancePad: resolved);
  }

  void _disposeOffStagePads() {
    for (final padItem in _offStageAmbiancePads.values) {
      padItem.dispose();
    }
    _offStageAmbiancePads.clear();
  }

  // ── Interne ───────────────────────────────────────────────────────────────

  /// Appelé par le listener d'un lecteur quand la voix courante d'un pad
  /// ambiance s'arrête hors de nos propres transitions (voix invalidée).
  void _handleAmbiancePlaybackEnded(PadItem padItem) {
    if (_inTransition) return;
    if (_o._state.currentAmbiancePad?.pad.id != padItem.pad.id) return;
    _o._state = _o._state.copyWith(clearCurrentAmbiancePad: true);
    _o._notify();
  }

  void _setOnAir(PadItem padItem, int index) {
    padItem._currentPlayerIndex = index;
    padItem.isPlaying = true;
    _o._state = _o._state.copyWith(currentAmbiancePad: padItem);
    _o._notify();
  }

  Future<bool> _preparePadForPlayback(PadItem padItem) async {
    await _o._loadPlayersForPad(padItem, padItem.pad);
    if (padItem.isPlayable) return true;
    return _o.downloadAndLoadPad(padItem);
  }

  Future<void> _fadeOutAndStop(PadItem padItem, Duration fade) async {
    final player = padItem.currentPlayer;
    if (player != null && padItem.isPlaying && fade > Duration.zero) {
      _transitionLockCount++;
      try {
        await player.fadeEnvelope(
          _o._effectiveVolume(padItem),
          fade,
          fadeIn: false,
          curve: FadeCurve.cubic,
        );
      } finally {
        if (_transitionLockCount > 0) _transitionLockCount--;
      }
    }
    await _stopPadPlayers(padItem);
    _o._notify();
  }

  /// Coupe toutes les voix du pad et le retire de l'antenne s'il y était.
  Future<void> _stopPadPlayers(PadItem padItem) async {
    _transitionLockCount++;
    try {
      for (final slot in padItem.slots) {
        final player = slot.player;
        if (player != null && player.isPlaying) {
          await player.stop();
        }
      }
    } finally {
      if (_transitionLockCount > 0) _transitionLockCount--;
    }
    padItem.isPlaying = false;
    padItem._currentPlayerIndex = null;
    if (_o._state.currentAmbiancePad?.pad.id == padItem.pad.id) {
      _o._state = _o._state.copyWith(clearCurrentAmbiancePad: true);
    }
  }

  /// Arrêt immédiat, sans fondu ni notification (Tout arrêter, hors-ligne).
  Future<void> _stopImmediately() async {
    final current = _o._state.currentAmbiancePad;
    if (current == null) return;
    await _stopPadPlayers(current);
  }
}
