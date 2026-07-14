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
  /// pads musique sont en plus soumis au volume global.
  double _effectiveVolume(PadItem padItem, {int? soundIndex}) {
    final index = soundIndex ?? padItem.currentSoundIndex ?? 0;
    final base = padItem.pad.effectiveVolume(index);
    return padItem.pad.isMusicPad ? base * _musicVolume : base;
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

    // Ce pad n'est pas jouable → rien
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
      final sameSlot = current.pad.id == target.pad.id &&
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
    final targetVolume = _effectiveVolume(next, soundIndex: soundIndex);

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
      await _o._loadSlotAtIndex(
        padItem,
        index,
        downloadIfNeeded: true,
      );
      _o._attachPlayerListeners(padItem);
      final reloaded = padItem.slots[index].player;
      if (reloaded == null) {
        _setMusicLoadError(padItem);
        return false;
      }
      started = await reloaded.playFromPosition(startPos, volume: volume);
    }

    if (!started) {
      _setMusicLoadError(padItem);
      return false;
    }

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

  /// Coupe un pad musique avec un fondu sortant, sans mémoriser de position
  /// de reprise (contrairement à [fadeOutCurrentMusic]) : le pad repart de
  /// zéro — et pioche un nouveau son via [_pickSoundIndex] pour un multipad —
  /// au prochain tap plutôt que de reprendre en pause.
  Future<void> _fadeOutAndStopMusicPad(PadItem padItem, Duration duration) async {
    final player = padItem.currentPlayer;
    if (duration == Duration.zero || player == null) {
      await _stopMusicPad(padItem, manual: true);
      return;
    }

    _musicAdvanceLockCount++;
    try {
      player.fadeVolumeTo(0, duration);
      await Future<void>.delayed(duration);
    } finally {
      if (_musicAdvanceLockCount > 0) _musicAdvanceLockCount--;
    }
    await _stopMusicPad(padItem, manual: true);
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

  void _clearMusicState() {
    _o._state = _o._state.copyWith(
      clearCurrentMusicPad: true,
      clearMusicQueue: true,
    );
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
      final padIdBySound =
          await _o._repository.getSoundIdToFirstPadIdInBoard(boardId);
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
        padItem.unavailabilityReason == PadUnavailabilityReason.missingFile ||
        padItem.unavailabilityReason == PadUnavailabilityReason.unsupportedFormat;
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
      // Sonde le cache local d'abord (comme les pads du plateau) : sinon, en
      // mode live hors-ligne, `_loadPlayersForPad` saute un slot dont
      // `appearsReady` est faux, même si le fichier est déjà en cache.
      await _o._probePadLocalAvailability(padItem);
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
      PadUnavailabilityReason.unsupportedFormat => 'Format audio non supporté.',
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
      final targetVolume = _effectiveVolume(next, soundIndex: soundIndex);

      await nextPlayer.playAtVolume(
        0,
        startOffset: _startOffsetOf(next, soundIndex, nextPlayer),
      );
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
