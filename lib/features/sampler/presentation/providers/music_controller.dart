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

  /// Fondu appliqué quand un tap coupe un multipad musique en cours de
  /// lecture (évite la coupure sèche à l'antenne) — même durée que la plus
  /// courte option manuelle du sélecteur de régie.
  static const _multipadTapStopFadeDuration = Duration(seconds: 1);

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

  /// Erreur de lecture en attente sans la consommer — permet à l'UI de décider
  /// si elle doit l'afficher (route active) avant de la retirer.
  bool get hasPendingPlaybackError => _lastPlaybackError != null;

  String? consumeLastPlaybackError() {
    final msg = _lastPlaybackError;
    _lastPlaybackError = null;
    return msg;
  }

  /// Point d'entrée configuré sur le son du slot [index] d'un pad — position de
  /// départ d'une lecture fraîche (0 si l'index est hors limites).
  /// [player] sert à borner l'offset à la durée du fichier (évite un seek hors
  /// fin qui termine la voix immédiatement sans son audible).
  Duration _startOffsetOf(
    PadItem padItem,
    int index,
    AudioPlayerService player,
  ) {
    final sounds = padItem.pad.sounds;
    if (index < 0 || index >= sounds.length) return Duration.zero;
    var ms = sounds[index].startOffsetMs;
    final duration = player.duration;
    if (duration > Duration.zero) {
      final maxMs = duration.inMilliseconds;
      if (ms >= maxMs) {
        ms = (maxMs - 1).clamp(0, maxMs);
      }
    }
    return Duration(milliseconds: ms);
  }

  /// Volume effectif du son à [soundIndex] (défaut : le son courant du pad, ou
  /// le premier). Base = override du pad-son ou volume par défaut du son ; les
  /// pads musique et ambiance sont en plus soumis au volume de leur voie
  /// (courbé, voir [_perceptualGain]).
  double _effectiveVolume(PadItem padItem, {int? soundIndex}) {
    final index = soundIndex ?? padItem.currentSoundIndex ?? 0;
    final base = padItem.pad.effectiveVolume(index);
    if (padItem.pad.isMusicPad) return base * _perceptualGain(_musicVolume);
    if (padItem.pad.isAmbiancePad) return base * _o._ambiance._gain;
    return base;
  }

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
    final nextQueue = _o._state.musicQueuePadIds
        .where((id) => id != padId)
        .toList();
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
    // Ce pad joue :
    // - multipad → coupe (fondu) sans mémoriser de reprise ; le prochain tap
    //   choisira un autre son du multipad (aléatoire ou séquentiel selon le
    //   mode de lecture du pad, voir `_pickSoundIndex`).
    // - pad simple → pause (mémorise la position pour reprise à l'identique).
    if (padItem.isPlaying) {
      if (padItem.pad.sounds.length > 1) {
        await _fadeOutAndStopMusicPad(padItem, _multipadTapStopFadeDuration);
      } else {
        await _stopMusicPad(padItem, manual: true, clearOnAir: false);
      }
      return;
    }

    // Ce pad est en pause → reprendre depuis la position mémorisée
    if (padItem.isPaused && padItem.isPlayable) {
      final current = _o._state.currentMusicPad;
      if (current != null && current.pad.id != padItem.pad.id) {
        if (current.isPlaying) {
          await _stopMusicPad(current, manual: true);
        } else if (current.isPaused) {
          current.clearPausedPlayback();
          _o._state = _o._state.copyWith(clearCurrentMusicPad: true);
          _o._notify();
        }
      }
      await _playMusicPad(
        padItem,
        fromPosition: padItem.pausedPlaybackPosition,
        soundIndex: padItem.pausedPlayerIndex,
      );
      return;
    }

    if (!padItem.isPlayable) return;

    // Ce pad n'est pas joué → jouer immédiatement (arrête l'éventuelle
    // musique en cours, retire ce pad de la file s'il y était)
    await playMusicNow(padItem);
  }

  /// [soundIndex] : force la variante à jouer (ex. choix explicite dans un
  /// multipad) au lieu de laisser `_pickSoundIndex` piocher automatiquement.
  Future<void> playMusicNow(PadItem padItem, {int? soundIndex}) async {
    if (!padItem.isPlayable) return;
    await _switchToMusic(padItem, soundIndex: soundIndex);
  }

  /// Point d'entrée unique pour « passer » à une autre musique — déclenchement
  /// explicite (pad, variante d'un multipad, recherche) ou avance dans la file
  /// ([playNextInQueueNow]) : coupe ce qui joue, puis démarre [target]. Une
  /// seule musique joue à la fois, hors fondu enchaîné explicite (crossfade).
  Future<bool> _switchToMusic(PadItem target, {int? soundIndex}) async {
    final current = _o._state.currentMusicPad;
    if (current != null) {
      // Même pad ET même variante déjà en cours (ex. simple pad relancé, ou
      // ré-appui sur la variante déjà jouée dans le picker) : pas de coupure,
      // `_playMusicPad` ci-dessous relance ce même lecteur.
      final sameSlot =
          current.pad.id == target.pad.id &&
          (soundIndex == null || soundIndex == current.currentSoundIndex);
      if (!sameSlot) {
        if (current.isPlaying) {
          await _stopMusicPad(current, manual: true);
        } else if (current.isPaused) {
          // Abandon la pause du pad courant avant d'en jouer un autre.
          current.clearPausedPlayback();
          _o._state = _o._state.copyWith(clearCurrentMusicPad: true);
          _o._notify();
        }
      }
    }

    _o._state = _o._state.copyWith(
      musicQueuePadIds: _o._state.musicQueuePadIds
          .where((id) => id != target.pad.id)
          .toList(),
    );
    return _playMusicPad(target, soundIndex: soundIndex);
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

    if (current?.pad.id == padId) {
      if (current?.isPlaying ?? false) {
        return padItem;
      }
      // Même pad à l'antenne mais arrêté ou en pause : relancer (point d'entrée
      // frais) au lieu d'un no-op silencieux via enqueueMusicPad.
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

    return _switchToMusic(next);
  }

  Future<void> stopCurrentMusic() async {
    final current = _o._state.currentMusicPad;
    if (current == null) return;
    if (current.isPlaying) {
      await _stopMusicPad(current, manual: true);
    } else if (current.isPaused) {
      current.clearPausedPlayback();
      _o._state = _o._state.copyWith(clearCurrentMusicPad: true);
      _o._notify();
    }
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

  /// Repositionne la lecture du pad musique courant EN PAUSE (scrub sur la
  /// waveform de régie) : met à jour la position mémorisée, d'où la reprise
  /// repartira. Sans effet si aucun pad n'est en pause. La lecture n'est jamais
  /// relancée ici — c'est un simple repérage.
  Future<void> seekPausedMusic(Duration position) async {
    final current = _o._state.currentMusicPad;
    if (current == null || !current.isPaused) return;

    final duration = current.progressPlayer?.duration ?? Duration.zero;
    var target = position;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;

    current.pausedPlaybackPosition = target;
    _o._notify();
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

  /// Message d'erreur de lecture destiné à la régie (musique ou ambiance).
  void _reportPlaybackError(String message) {
    _lastPlaybackError = message;
    _o._notify();
  }

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
      _setMusicLoadError(
        padItem,
        'aucun lecteur chargé pour la variante ${index + 1}',
      );
      return false;
    }

    // Métadonnées à jour (point d'entrée édité en bibliothèque, etc.).
    await _o._syncPadSoundMetadata(padItem, index);

    padItem.clearPausedPlayback();

    final volume = _effectiveVolume(padItem, soundIndex: index);
    final startPos = resumePosition != null && resumePosition > Duration.zero
        ? resumePosition
        : _startOffsetOf(padItem, index, player);

    var started = await player.playFromPosition(startPos, volume: volume);
    if (!started) {
      // Source SoLoud peut avoir été invalidée (ex. éditeur de point d'entrée).
      await _o._loadSlotAtIndex(padItem, index, downloadIfNeeded: true);
      _o._attachPlayerListeners(padItem);
      final reloaded = padItem.slots[index].player;
      if (reloaded == null) {
        _setMusicLoadError(padItem, 'rechargement du son impossible');
        return false;
      }
      started = await reloaded.playFromPosition(startPos, volume: volume);
      if (!started) {
        _setMusicLoadError(padItem, reloaded.lastStartFailure);
        return false;
      }
    }

    if (!started) {
      _setMusicLoadError(padItem, player.lastStartFailure);
      return false;
    }
    AudioLoadLog.musicStarted(
      padLabel: padItem.displayName,
      padId: padItem.pad.id,
    );

    _o._state = _o._state.copyWith(
      currentMusicPad: padItem,
      musicQueuePadIds: _o._state.musicQueuePadIds
          .where((id) => id != padItem.pad.id)
          .toList(),
    );
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
    if (padItem.isPlaying) {
      AudioLoadLog.musicStopped(
        padLabel: padItem.displayName,
        padId: padItem.pad.id,
        paused: !clearOnAir && manual,
      );
    }
    try {
      // On coupe toute voix réellement active du pad plutôt que de se fier au
      // seul `currentPlayer` (résolu via `_currentPlayerIndex`) : cet index
      // n'est mis à jour que de façon asynchrone par le listener
      // `onPlayerStateChanged` (voir `_attachPlayerListeners`), donc pas fiable
      // juste après un `play` récent — un stop ciblé sur un index pas encore à
      // jour deviendrait un no-op silencieux et laisserait l'ancienne variante
      // jouer en même temps que la nouvelle.
      for (final slot in padItem.slots) {
        final player = slot.player;
        if (player != null && player.isPlaying) {
          await player.stop();
        }
      }
    } finally {
      if (manual) {
        if (_musicAdvanceLockCount > 0) _musicAdvanceLockCount--;
      }
    }
    // Le stream `onPlayerStateChanged` ne notifie l'arrêt qu'après ce point
    // (au-delà du verrou ci-dessus) : figer isPlaying/_currentPlayerIndex ici
    // évite que le listener tardif ne (re)déclenche `_handleMusicPlaybackEnded`
    // et n'efface `currentMusicPad` pour un simple pause manuel.
    padItem.isPlaying = false;
    padItem._currentPlayerIndex = null;

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

    if (queue.isEmpty) {
      cleanupOffStagePads();
      return;
    }

    final nextId = queue.first;
    final next = _resolvePadItem(nextId);
    if (next == null) {
      _setMusicLoadError();
      return;
    }
    unawaited(_playMusicPad(next));
  }

  void _capturePausedPlayback(PadItem padItem) {
    final player = padItem.currentPlayer;
    if (player == null) return;
    padItem.pausedPlaybackPosition = player.position;
    padItem.pausedPlayerIndex = padItem._currentPlayerIndex;
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
}

/// Convertit la position d'un fader de régie (0→1, linéaire, telle qu'affichée
/// en %) en gain audio via une loi cubique. L'oreille perçoit le volume de
/// façon logarithmique : un fader linéaire concentre toute la variation
/// audible dans le bas de course (coupure quasi sèche près du silence, quasi
/// rien en haut). Le cube étale la sensation régulièrement sur toute la
/// course et atteint zéro proprement, sans plancher à gérer. Ne s'applique
/// qu'au gain envoyé au moteur — le volume de voie, le mute et le ramp du
/// fader restent en espace « position » linéaire. Partagé par les voies
/// musique et ambiance.
double _perceptualGain(double position) {
  final p = position.clamp(0.0, 1.0);
  return p * p * p;
}
