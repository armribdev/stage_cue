part of 'sampler_provider.dart';

/// Déclenchement des pads (bruitages), panique et choix du son à jouer.
/// Méthodes de [SamplerNotifier] extraites via extension dans le même `part`.

extension SamplerPadPlayback on SamplerNotifier {
  Future<void> toggleSound(PadItem padItem) async {
    final resolved = _resolveBoardPadItem(padItem);
    AudioLoadLog.trace(
      '[TOGGLE] pad="${resolved.pad.displayName}" id=${resolved.pad.id} '
      'isPlayable=${resolved.isPlayable} isPlaying=${resolved.isPlaying} '
      'isMusicPad=${resolved.pad.isMusicPad} '
      'slots=${resolved.slots.length} readySlots=${resolved.slots.where((s) => s.isReady).length} '
      '_currentPlayerIndex=${resolved._currentPlayerIndex}',
    );
    if (!resolved.isPlayable) {
      AudioLoadLog.trace('[TOGGLE] ↩ not playable, ignoring');
      reportPadTriggerFailure(resolved);
      return;
    }
    if (resolved.pad.isMusicPad) {
      await _music._toggleMusicPad(resolved);
      return;
    }
    if (resolved.pad.isAmbiancePad) {
      await _ambiance._toggleAmbiancePad(resolved);
      return;
    }

    // Pads non-musique : polyphonie. Chaque tap empile un nouveau son (superposé)
    // sans couper les précédents ; sur un multipad la variante suivante est
    // choisie selon le mode de lecture. L'arrêt se fait via appui long (ce pad)
    // ou le bouton « Tout arrêter » — jamais par un second tap.
    await _playOverlappingSoundAtIndex(resolved, _pickSoundIndex(resolved));
  }

  /// Joue une variante précise d'un (multi)pad, en dehors du choix automatique
  /// (`_pickSoundIndex`) — ex. sélection explicite depuis la liste des sons
  /// d'un multipad. Pour un pad musique, court-circuite la file/reprise et
  /// joue directement ce son (comme un tap normal sur un pad simple).
  Future<void> playPadSoundAtIndex(PadItem padItem, int soundIndex) async {
    final resolved = _resolveBoardPadItem(padItem);
    if (!resolved.isPlayable) {
      reportPadTriggerFailure(resolved);
      return;
    }
    if (soundIndex < 0 || soundIndex >= resolved.slots.length) return;
    if (!_slotEligibleForPlayback(resolved, soundIndex)) {
      reportPadTriggerFailure(
        resolved,
        reason: 'variante ${soundIndex + 1} indisponible',
      );
      return;
    }

    if (resolved.pad.isMusicPad) {
      // Même mécanisme que « suivant » dans la file (`playNextInQueueNow`) :
      // `playMusicNow` coupe ce qui joue puis démarre cette variante — un seul
      // point d'entrée pour changer de musique, quel que soit le déclencheur.
      await _music.playMusicNow(resolved, soundIndex: soundIndex);
      return;
    }
    if (resolved.pad.isAmbiancePad) {
      await _ambiance.playAmbianceNow(resolved, soundIndex: soundIndex);
      return;
    }

    await _playOverlappingSoundAtIndex(resolved, soundIndex);
  }

  /// Retourne `false` si aucune voix n'a démarré (déjà journalisé).
  Future<bool> _playOverlappingSoundAtIndex(
    PadItem resolved,
    int soundIndex,
  ) async {
    final player = resolved.slots[soundIndex].player;
    AudioLoadLog.trace(
      '[TOGGLE] → play overlapping soundIndex=$soundIndex '
      'playerNull=${player == null} '
      '_nextSoundIndex=${resolved._nextSoundIndex}',
    );
    if (player == null) {
      reportPadTriggerFailure(
        resolved,
        reason: 'aucun lecteur chargé pour la variante ${soundIndex + 1}',
      );
      return false;
    }
    await _syncPadSoundMetadata(resolved, soundIndex);
    // Point d'entrée : le déclenchement démarre à cet offset au lieu du sample 0.
    var startOffsetMs = resolved.pad.sounds[soundIndex].startOffsetMs;
    final duration = player.duration;
    if (duration > Duration.zero) {
      final maxMs = duration.inMilliseconds;
      if (startOffsetMs >= maxMs) {
        startOffsetMs = (maxMs - 1).clamp(0, maxMs);
      }
    }
    final startOffset = Duration(milliseconds: startOffsetMs);
    final started = await player.playOverlapping(
      volume: _effectiveVolume(resolved, soundIndex: soundIndex),
      startOffset: startOffset,
    );
    if (!started) {
      reportPadTriggerFailure(
        resolved,
        reason: player.lastStartFailure ?? 'voix non démarrée',
      );
    }
    // Ticket de progression : une barre superposée par voix, auto-supprimée à
    // la fin du son (bump de révision pour rafraîchir le seul PadButton). La
    // durée restante tient compte du point d'entrée sauté en tête.
    final remaining = player.duration - startOffset;
    resolved.addPlaybackTicket(
      remaining > Duration.zero ? remaining : player.duration,
      onExpire: () => _notifyPad(resolved),
    );
    _markPlayedAt(resolved, soundIndex);
    _notifyPad(resolved);
    _notify();
    return started;
  }

  /// Coupe tous les bruitages en cours (bouton panique « Tout arrêter »).
  /// Laisse jouer musique et ambiance : utile en live pour tuer un bruitage
  /// sans casser le tapis sonore. Ne touche pas à l'aperçu, qui est un lecteur
  /// indépendant.
  Future<void> stopAllNonMusicSounds() async {
    var changed = false;
    final playing = [
      for (final padItem in _state.pads)
        if (!padItem.pad.isExclusiveVoicePad) padItem,
      ..._offStageSfxPads.values,
    ].where((padItem) => padItem.isPlaying);
    for (final padItem in playing.toList()) {
      await _stopAllSlotPlayers(padItem);
      changed = true;
    }
    _disposeIdleOffStageSfxPads();
    if (changed) _notify();
  }

  /// Bouton panique « Tout arrêter » : coupe les bruitages en cours, laisse
  /// musique et ambiance, et journalise ce qui a été coupé et ce qui est resté.
  /// Distinct de [stopAllNonMusicSounds], aussi appelé en changeant de plateau
  /// (geste programmatique, pas une panique).
  Future<void> panicStop() async {
    final stopped = _state.pads
        .where((p) => !p.pad.isExclusiveVoicePad && p.isPlaying)
        .length;
    await stopAllNonMusicSounds();
    AudioLoadLog.panic(
      stoppedPads: stopped,
      musicStillPlaying: _state.currentMusicPad?.isPlaying ?? false,
      ambianceStillPlaying: _state.currentAmbiancePad?.isPlaying ?? false,
    );
  }

  /// Au moins un bruitage (ni musique ni ambiance) joue actuellement. L'aperçu
  /// n'en fait pas partie : c'est un lecteur indépendant.
  bool get hasNonMusicSoundsPlaying =>
      _state.pads.any((p) => !p.pad.isExclusiveVoicePad && p.isPlaying) ||
      _offStageSfxPads.values.any((p) => p.isPlaying);

  /// Libère les pads de bruitage hors-scène qui ne jouent plus.
  void _disposeIdleOffStageSfxPads() {
    _offStageSfxPads.removeWhere((_, padItem) {
      if (padItem.isPlaying) return false;
      padItem.dispose();
      return true;
    });
  }

  /// Arrête toutes les voix de chaque variante du pad (sans notifier).
  Future<void> _stopAllSlotPlayers(PadItem padItem) async {
    for (final slot in padItem.slots) {
      final player = slot.player;
      if (player != null && player.isPlaying) {
        await player.stop();
      }
    }
    padItem.clearPlaybackTickets();
    padItem.isPlaying = false;
    padItem._currentPlayerIndex = null;
  }

  void _markPlayed(int soundId) {
    unawaited(_repository.markSoundPlayed(soundId));
    // Patch de l'index plutôt qu'invalidation : en spectacle chaque
    // déclenchement passe ici, et reconstruire l'index à chaque son ferait
    // repartir la recherche sur la base au pire moment. Seul le tri par
    // récence dépend de ce champ.
    final playedAt = DateTime.now();
    _searchIndex.patchSound(
      soundId,
      (sound) => sound.copyWith(lastPlayedAt: playedAt),
    );
  }

  void _markPlayedAt(PadItem padItem, int soundIndex) {
    if (soundIndex < 0 || soundIndex >= padItem.pad.sounds.length) return;
    final soundId = padItem.pad.sounds[soundIndex].id;
    _markPlayed(soundId);
    if (_isLiveSessionActive) {
      _sessionPlayCounts[soundId] = (_sessionPlayCounts[soundId] ?? 0) + 1;
    }
  }

  bool _slotEligibleForPlayback(PadItem padItem, int index) {
    final slot = padItem.slots[index];
    // Un slot `ready` a forcément son fichier local (`isReady` ⇒ `appearsReady`) :
    // le Mode Spectacle n'a rien de plus à exiger ici.
    return slot.isReady ||
        (debugTreatReadyAvailabilityAsEligible &&
            slot.availability == PadSoundAvailability.ready);
  }

  int _pickSoundIndex(PadItem padItem) {
    final readyIndices = <int>[
      for (var i = 0; i < padItem.slots.length; i++)
        if (_slotEligibleForPlayback(padItem, i)) i,
    ];
    AudioLoadLog.trace(
      '[PICK] pad="${padItem.pad.displayName}" '
      'slots=${padItem.slots.length} readyIndices=$readyIndices '
      '_nextSoundIndex=${padItem._nextSoundIndex} '
      'playedIndices=${padItem._playedSoundIndices} '
      'playMode=${padItem.pad.playMode}',
    );
    if (readyIndices.isEmpty) return 0;
    if (readyIndices.length == 1) return readyIndices.first;

    if (_isLiveSessionActive) {
      final chosen = _pickLowestSessionCountIndex(padItem, readyIndices);
      AudioLoadLog.trace('[PICK] → chosen(live)=$chosen');
      return chosen;
    }

    final chosen = switch (padItem.pad.playMode) {
      PadPlayMode.random => () {
        var available = readyIndices
            .where((i) => !padItem._playedSoundIndices.contains(i))
            .toList();
        if (available.isEmpty) {
          padItem.resetRandomPlaySession();
          available = List<int>.from(readyIndices);
        }
        final idx = available[_random.nextInt(available.length)];
        padItem._playedSoundIndices.add(idx);
        return idx;
      }(),
      PadPlayMode.sequential => () {
        final total = padItem.slots.length;
        for (var step = 0; step < total; step++) {
          final idx = (padItem._nextSoundIndex + step) % total;
          if (_slotEligibleForPlayback(padItem, idx)) {
            padItem._nextSoundIndex = (idx + 1) % total;
            return idx;
          }
        }
        return readyIndices.first;
      }(),
    };
    AudioLoadLog.trace(
      '[PICK] → chosen=$chosen _nextSoundIndex(after)=${padItem._nextSoundIndex}',
    );
    return chosen;
  }

  /// Mode live : ignore `playMode`, pioche parmi les sons du multipad au
  /// compte de lecture de session le plus bas (égalité → tirage aléatoire
  /// parmi les ex-æquo). Ne mute volontairement PAS `_playedSoundIndices`/
  /// `_nextSoundIndex` : l'algorithme habituel doit reprendre sainement une
  /// fois la session terminée (voir décision 0014).
  int _pickLowestSessionCountIndex(PadItem padItem, List<int> readyIndices) {
    var minCount = 1 << 31;
    for (final i in readyIndices) {
      final count = sessionPlayCountFor(padItem.pad.sounds[i].id);
      if (count < minCount) minCount = count;
    }
    final lowest = [
      for (final i in readyIndices)
        if (sessionPlayCountFor(padItem.pad.sounds[i].id) == minCount) i,
    ];
    return lowest[_random.nextInt(lowest.length)];
  }
}
