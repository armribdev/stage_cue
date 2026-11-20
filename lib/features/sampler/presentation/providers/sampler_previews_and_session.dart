part of 'sampler_provider.dart';

/// Pré-écoute (lecteur d'aperçu unique), lecture directe depuis la
/// recherche-éclair, session live Mode Spectacle, préparation quick-search et
/// pads brouillon. Méthodes de [SamplerNotifier] extraites via extension dans
/// le même `part`.

extension SamplerPreviewsAndSession on SamplerNotifier {
  /// Joue pour de vrai le son choisi en recherche-éclair (clic / Entrée), par
  /// la voie de son type — jamais par le lecteur d'aperçu : musique sur la
  /// régie, ambiance à l'antenne, bruitage en salle depuis son point d'entrée.
  ///
  /// Le bruitage passe par un pad hors-scène (aucun pad ajouté au plateau) ; il
  /// compte comme n'importe quel bruitage joué : « Tout arrêter » le coupe et
  /// la session live le comptabilise. Retourne `false` si rien n'a démarré (le
  /// motif est alors lisible via `consumeLastMusicPlaybackError`).
  Future<bool> playSoundFromQuickSearch(int soundId) async {
    final sound = await _repository.getSoundById(soundId);
    if (sound == null) return false;
    switch (sound.type) {
      case SoundType.music:
        return await playMusicBySoundId(soundId) != null;
      case SoundType.ambiance:
        return await playAmbianceBySoundId(soundId) != null;
      case SoundType.soundEffect:
      case null:
        return _playOffStageSfx(sound);
    }
  }

  Future<bool> _playOffStageSfx(Sound sound) async {
    _disposeIdleOffStageSfxPads();
    var padItem = _offStageSfxPads[-sound.id];
    if (padItem == null) {
      padItem = await _buildOffStagePad(sound);
      if (padItem == null) return false;
      _offStageSfxPads[padItem.pad.id] = padItem;
    }
    if (!padItem.isPlayable && !await downloadAndLoadPad(padItem)) {
      reportPadTriggerFailure(padItem);
      return false;
    }
    return _playOverlappingSoundAtIndex(padItem, 0);
  }

  /// Écoute au casque d'un pad du plateau, sans le déclencher en salle.
  ///
  /// Joue la première variante du pad depuis son point d'entrée. Avec un casque
  /// configuré, c'est strict (jamais de repli sur la salle, décision 0027). Sans
  /// casque : hors spectacle l'écoute sort sur le périphérique par défaut ; en
  /// spectacle rien ne sort — le refus est exposé via [consumeLastPreviewError].
  Future<bool> previewPadOnCue(PadItem padItem) async {
    final sounds = padItem.pad.sounds;
    if (sounds.isEmpty) return false;
    return toggleLibraryPreview(
      sounds.first.id,
      requireCue: _isLiveSessionActive,
    );
  }

  /// Message du dernier refus de pré-écoute au casque, sans le consommer.
  bool get hasPendingPreviewError => _lastPreviewError != null;

  /// Retourne puis efface le message du dernier refus de pré-écoute au casque.
  String? consumeLastPreviewError() {
    final message = _lastPreviewError;
    _lastPreviewError = null;
    return message;
  }

  /// Son en cours d'aperçu dans la bibliothèque, ou `null`.
  int? get libraryPreviewSoundId => _libraryPreviewSoundId;

  /// Indique si l'aperçu bibliothèque de [soundId] est audible.
  bool libraryPreviewIsPlaying(int soundId) =>
      _libraryPreviewSoundId == soundId &&
      (_libraryPreviewPlayer?.isPlaying ?? false);

  /// Position de lecture de l'aperçu de [soundId] (zéro s'il n'est pas chargé).
  Duration libraryPreviewPosition(int soundId) =>
      _libraryPreviewSoundId == soundId
      ? (_libraryPreviewPlayer?.position ?? Duration.zero)
      : Duration.zero;

  /// Charge l'aperçu de [soundId] sans le jouer et rend sa durée, ou `null` si
  /// le son n'est pas lisible ici (pas téléchargé, format, casque indisponible).
  ///
  /// Sert à l'éditeur du point d'entrée, qui a besoin de la durée avant tout
  /// ▶ : il charge ainsi le lecteur unique plutôt que d'en ouvrir un second.
  /// Ne télécharge rien. Un aperçu déjà chargé pour ce son (même en cours de
  /// lecture) est conservé tel quel ; celui d'un autre son est remplacé.
  Future<Duration?> loadLibraryPreview(int soundId) async {
    final existing = _libraryPreviewPlayer;
    if (_libraryPreviewSoundId == soundId && existing != null) {
      return existing.duration;
    }
    final sound = await _repository.getSoundById(soundId);
    if (sound == null) return null;
    // Le lecteur est unique : l'aperçu d'un autre son (▶ d'une ligne, son
    // précédent de la file de traitement) cède la place. Sans cela, le contrôle
    // ci-dessous le prendrait pour un concurrent et l'éditeur afficherait
    // « Téléchargez le son » alors que le fichier est bien là.
    if (_libraryPreviewSoundId != soundId) stopLibraryPreview();
    try {
      final path = await _resolvePlayablePath(sound);
      final player = await CueAudioService.instance.createPreviewPlayer(path);
      // Un autre aperçu (bouton de ligne) a pris le lecteur pendant le
      // chargement : il gagne, ce chargement-ci est jeté.
      if (_libraryPreviewPlayer != null) {
        player.dispose();
        return _libraryPreviewSoundId == soundId
            ? _libraryPreviewPlayer?.duration
            : null;
      }
      player.setGain(sound.gain);
      _attachLibraryPreview(sound.id, player);
      return player.duration;
    } catch (e) {
      // Pas de lecteur à montrer : l'éditeur affiche son message d'indisponibilité.
      AudioLoadLog.trace('Chargement de l\'aperçu « ${sound.title} » : $e');
      return null;
    }
  }

  /// Relance l'aperçu en cours de [soundId] depuis [position] (tête de lecture
  /// déplacée à la main). Sans effet si ce son n'est pas en train de jouer.
  Future<void> seekLibraryPreview(int soundId, Duration position) async {
    if (!libraryPreviewIsPlaying(soundId)) return;
    await _libraryPreviewPlayer?.playFromPosition(position);
  }

  /// Bascule play/pause pour l'aperçu (lecteur unique, un son à la fois). C'est
  /// le seul point d'entrée de la pré-écoute : elle reste étrangère aux pads,
  /// à la régie et au bouton « Tout arrêter ».
  ///
  /// [requireCue] : n'a de sens qu'au casque — échoue plutôt que de sortir sur
  /// la salle quand aucun casque n'est configuré.
  ///
  /// [from] et [gain] : départ et gain d'un nouvel aperçu, quand ils ne sont pas
  /// ceux enregistrés (l'éditeur écoute ses réglages non validés). Par défaut :
  /// point d'entrée et gain du son (décision 0045).
  Future<bool> toggleLibraryPreview(
    int soundId, {
    bool requireCue = false,
    Duration? from,
    double? gain,
  }) async {
    final player = _libraryPreviewPlayer;
    if (_libraryPreviewSoundId == soundId && player != null) {
      if (player.isPlaying) {
        await player.pause();
        _notify();
        return true;
      }
      if (player.isPaused) {
        await player.resume();
        _notify();
        return true;
      }
    }

    if (_refuseRoomPreviewInLive()) return false;
    final sound = await _repository.getSoundById(soundId);
    if (sound == null) return false;
    return _startLibraryPreview(
      sound,
      requireCue: requireCue,
      from: from,
      gain: gain,
    );
  }

  /// Vrai en Mode Spectacle quand une pré-écoute sortirait en salle (sortie
  /// casque possible sur la plateforme mais aucune choisie). L'UI s'en sert pour
  /// ne pas proposer les boutons d'aperçu.
  bool get isRoomPreviewBlockedInLive =>
      _isLiveSessionActive &&
      CueAudioService.isSupported &&
      !CueAudioService.instance.isCueActive;

  /// En Mode Spectacle, sur une plateforme capable d'une sortie casque, une
  /// pré-écoute sans casque choisi sortirait en salle : on la refuse (message
  /// via [consumeLastPreviewError]) plutôt que de la laisser entendre du
  /// public. Hors spectacle, ou sans sortie séparée possible, rien ne change.
  bool _refuseRoomPreviewInLive() {
    if (!isRoomPreviewBlockedInLive) return false;
    _refusePreview(
      const CueUnavailableException(
        'Aucun casque configuré — pré-écoute désactivée en Mode Spectacle '
        'pour ne pas sortir en salle.',
      ),
    );
    return true;
  }

  /// Répercute en direct un changement de gain (curseur ou « Auto » du
  /// formulaire d'édition, pas encore enregistré) sur l'aperçu bibliothèque de
  /// [soundId], voix en cours comprises. Sans effet si ce son n'est pas celui en
  /// aperçu.
  void setLibraryPreviewGain(int soundId, double gain) {
    if (_libraryPreviewSoundId != soundId) return;
    final player = _libraryPreviewPlayer;
    if (player == null) return;
    player.setGain(gain);
    // `setGain` ne touche pas aux voix déjà lancées : `setVolume` les rafraîchit.
    player.setVolume(1.0);
  }

  void stopLibraryPreview({bool notify = true}) {
    _libraryPreviewSub?.cancel();
    _libraryPreviewSub = null;
    _libraryPreviewPlayer?.dispose();
    _libraryPreviewPlayer = null;
    _libraryPreviewSoundId = null;
    if (notify) _notify();
  }

  /// Pose [player] comme lecteur d'aperçu unique de [soundId] : la fin de piste
  /// ou l'arrêt le libère.
  void _attachLibraryPreview(int soundId, PreviewPlayback player) {
    _libraryPreviewPlayer = player;
    _libraryPreviewSoundId = soundId;
    _libraryPreviewSub = player.onPlayerStateChanged.listen((playing) {
      if (playing) return;
      stopLibraryPreview();
    });
  }

  Future<bool> _startLibraryPreview(
    Sound sound, {
    bool requireCue = false,
    Duration? from,
    double? gain,
  }) async {
    try {
      // Un aperçu déjà chargé (et à l'arrêt) pour ce son est réutilisé, sauf
      // pour une écoute au casque obligatoire : il a pu être ouvert sans cette
      // garantie. Dans tous les autres cas le lecteur courant est remplacé.
      var player = _libraryPreviewSoundId == sound.id && !requireCue
          ? _libraryPreviewPlayer
          : null;
      if (player == null) {
        stopLibraryPreview(notify: false);
        final path = await _resolvePlayablePath(
          sound,
          downloadIfNeeded: allowsSoundDownload,
        );
        player = await CueAudioService.instance.createPreviewPlayer(
          path,
          requireCue: requireCue,
        );
        _attachLibraryPreview(sound.id, player);
      }
      // À chaque départ, même sur un lecteur réutilisé : le gain a pu changer
      // (« Auto » enregistré) depuis son chargement.
      player.setGain(gain ?? sound.gain);
      var startMs =
          (from ?? Duration(milliseconds: sound.startOffsetMs)).inMilliseconds;
      final duration = player.duration;
      if (duration > Duration.zero) {
        final maxMs = duration.inMilliseconds;
        if (startMs >= maxMs) {
          startMs = (maxMs - 1).clamp(0, maxMs);
        }
      }
      await player.playFromPosition(Duration(milliseconds: startMs));
      _markPlayed(sound.id);
      _notify();
      return true;
    } on CueUnavailableException catch (e) {
      stopLibraryPreview(notify: false);
      _refusePreview(e);
      return false;
    } catch (e) {
      AudioLoadLog.warn(
        'Aperçu bibliothèque échoué pour « ${sound.title} » : $e',
      );
      stopLibraryPreview(notify: false);
      return false;
    }
  }

  /// Mémorise le refus d'une pré-écoute au casque pour l'afficher une fois, et
  /// prévient les écrans (le plateau n'a pas d'autre moyen de le savoir).
  void _refusePreview(CueUnavailableException e) {
    _lastPreviewError = e.message;
    _notify();
  }

  /// À appeler à l'entrée en mode live (Mode Spectacle) : le prochain pad
  /// ajouté via la recherche-éclair démarre une nouvelle ligne plutôt que de
  /// s'ajouter à la suite de la dernière ligne déjà en place.
  void markPerformanceModeEntered() {
    _forceNewRowOnNextQuickAdd = true;
  }

  bool get isLiveSessionActive => _isLiveSessionActive;

  int sessionPlayCountFor(int soundId) => _sessionPlayCounts[soundId] ?? 0;

  bool hasPlayedInSession(int soundId) => sessionPlayCountFor(soundId) > 0;

  /// Démarre une session live : remet à zéro les compteurs de lecture par
  /// son et active le suivi. Coupe aussi les téléchargements et retire de la
  /// scène les pads sans son en cache (0037). `notifyListeners()` rafraîchit
  /// un éventuel `SoundPickerOverlay` déjà ouvert.
  void startLiveSession() {
    _sessionPlayCounts.clear();
    _isLiveSessionActive = true;
    _liveSessionStartedAt = DateTime.now();
    _downloadQueue.cancelQueued((_, _) => true);
    unawaited(_applyLiveSessionConstraints());
    _syncMultipadNumbers(_padsForMultipadNumbering());
    AppLog.info('Mode Spectacle activé.');
    _notify();
  }

  /// Termine la session live : gèle les compteurs (ni effacés, ni remis à
  /// zéro) — seule la prochaine [startLiveSession] repart propre.
  void endLiveSession() {
    final startedAt = _liveSessionStartedAt;
    if (_isLiveSessionActive && startedAt != null) {
      final totalPlays = _sessionPlayCounts.values.fold<int>(
        0,
        (a, b) => a + b,
      );
      final duration = DateTime.now().difference(startedAt);
      AppLog.info(
        'Mode Spectacle désactivé — durée ${_formatSessionDuration(duration)}, '
        '$totalPlays lecture(s) sur ${_sessionPlayCounts.length} son(s).',
      );
    }
    _liveSessionStartedAt = null;
    _isLiveSessionActive = false;
    // Les pads masqués reviennent : leur numéro de multipad aussi.
    _syncMultipadNumbers(_padsForMultipadNumbering());
    _notify();
  }

  static String _formatSessionDuration(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  /// Expose `_markPlayedAt` pour les tests unitaires (simule une lecture
  /// réelle sans passer par un lecteur audio natif).
  @visibleForTesting
  void debugMarkPlayedAt(PadItem padItem, int soundIndex) =>
      _markPlayedAt(padItem, soundIndex);

  /// Expose `_markPlayed` seul (chemin pré-écoute) pour vérifier qu'il
  /// n'incrémente jamais le compteur de session.
  @visibleForTesting
  void debugMarkPlayedPreviewOnly(int soundId) => _markPlayed(soundId);

  /// Expose la logique pure de sélection « compteur le plus bas » sans
  /// dépendre d'un `PadSoundSlot` jouable (évite de fabriquer un
  /// `AudioPlayerService` natif en test).
  @visibleForTesting
  int debugPickLowestSessionCountIndex(
    PadItem padItem,
    List<int> readyIndices,
  ) => _pickLowestSessionCountIndex(padItem, readyIndices);

  /// Dispatch complet de [_pickSoundIndex] (voir [debugTreatReadyAvailabilityAsEligible]).
  @visibleForTesting
  int debugPickSoundIndex(PadItem padItem) => _pickSoundIndex(padItem);

  /// Choix du son d'un multipad enregistré (voir [_pickSavedMultipadSound]).
  @visibleForTesting
  Sound? debugPickSavedMultipadSound(SavedMultipad saved) =>
      _pickSavedMultipadSound(saved);

  Future<QuickSearchPrepareResult> prepareSoundFromQuickSearch(
    int soundId,
  ) async {
    final sound = await _repository.getSoundById(soundId);
    if (sound == null) return const QuickSearchPrepareResult.none();

    if (sound.type == SoundType.music) {
      await enqueueMusicBySoundId(soundId);
      return const QuickSearchPrepareResult.none();
    }

    return _prepareSfxPadOnBoard(soundId);
  }

  Iterable<({Pad pad, bool isDraft})> _padsOnBoardRefs() {
    return [
      for (final item in _state.pads) (pad: item.pad, isDraft: item.isDraft),
    ];
  }

  Future<QuickSearchPrepareResult> _prepareSfxPadOnBoard(int soundId) async {
    final boardId = _activeBoardId;
    if (boardId == null) return const QuickSearchPrepareResult.none();

    final forceNewRow = _forceNewRowOnNextQuickAdd;

    final result = await prepareSfxOnBoard(
      soundId: soundId,
      padsOnBoard: _padsOnBoardRefs(),
      forceNewRow: forceNewRow,
      createPad: (placement) {
        _forceNewRowOnNextQuickAdd = false;
        return _repository.createPadWithSettings(
          boardId: boardId,
          soundIds: [soundId],
          rowIndex: placement.rowIndex,
          sortOrder: placement.globalSortOrder,
        );
      },
      reloadPads: () async {
        await loadSounds(boardId: boardId, silent: true);
        return _padsOnBoardRefs();
      },
    );

    final highlightId = result.highlightPadId;
    if (highlightId != null) {
      final padItem = findPadItemById(highlightId);
      if (padItem != null) {
        final slotIndex = padItem.pad.sounds.indexWhere((s) => s.id == soundId);
        if (slotIndex >= 0) _maybeAutoDownloadPadSound(padItem, slotIndex);
      }
    }

    return result;
  }

  /// Son que [saved] joue à ce tour, selon son mode de lecture — comme un pad :
  /// aléatoire sans répétition jusqu'à épuisement, ou dans l'ordre. En Mode
  /// Spectacle, le mode est ignoré au profit du son le moins joué de la session
  /// (décision 0014). `null` pour un modèle sans son.
  Sound? _pickSavedMultipadSound(SavedMultipad saved) {
    final sounds = saved.sounds;
    if (sounds.isEmpty) return null;
    if (sounds.length == 1) return sounds.first;

    if (_isLiveSessionActive) {
      int countOf(Sound s) => _sessionPlayCounts[s.id] ?? 0;
      final min = sounds.map(countOf).reduce((a, b) => a < b ? a : b);
      final lowest = sounds.where((s) => countOf(s) == min).toList();
      return lowest[_random.nextInt(lowest.length)];
    }

    switch (saved.playMode) {
      case PadPlayMode.random:
        final played = _savedMultipadPlayedIds.putIfAbsent(saved.id, () => {});
        var available = sounds.where((s) => !played.contains(s.id)).toList();
        if (available.isEmpty) {
          played.clear();
          available = sounds;
        }
        final picked = available[_random.nextInt(available.length)];
        played.add(picked.id);
        return picked;
      case PadPlayMode.sequential:
        // Suit le dernier son joué dans la liste courante (et non un indice) :
        // une édition du modèle ne décale pas le curseur. Aucun son joué → 0.
        final last = sounds.indexWhere(
          (s) => s.id == _savedMultipadLastSoundId[saved.id],
        );
        final picked = sounds[(last + 1) % sounds.length];
        _savedMultipadLastSoundId[saved.id] = picked.id;
        return picked;
    }
  }

  /// Clic / Entrée sur un multipad en recherche-éclair : joue pour de vrai le
  /// son que le modèle désigne à ce tour, par la voie de son type — exactement
  /// comme [playSoundFromQuickSearch], sans rien poser sur le plateau.
  Future<bool> playSavedMultipadFromQuickSearch(SavedMultipad saved) async {
    final sound = _pickSavedMultipadSound(saved);
    if (sound == null) return false;
    return playSoundFromQuickSearch(sound.id);
  }

  /// Vrai si l'aperçu en cours est celui d'un des sons de [saved].
  bool savedMultipadPreviewIsPlaying(SavedMultipad saved) =>
      saved.sounds.any((s) => libraryPreviewIsPlaying(s.id));

  /// Bascule play/pause de l'aperçu d'un multipad : un aperçu déjà chargé de
  /// l'un de ses sons est mis en pause / repris, sinon le son désigné à ce tour
  /// est écouté (lecteur d'aperçu unique, voir [toggleLibraryPreview]).
  Future<bool> toggleSavedMultipadPreview(SavedMultipad saved) async {
    final current = _libraryPreviewSoundId;
    final loaded = current != null && saved.sounds.any((s) => s.id == current);
    final soundId = loaded ? current : _pickSavedMultipadSound(saved)?.id;
    if (soundId == null) return false;
    return toggleLibraryPreview(soundId);
  }

  /// Pose une copie du multipad enregistré [saved] en fin de dernière ligne du
  /// plateau : nom, couleur, mode de lecture et sons du modèle, sans lien avec
  /// lui ensuite (décision 0051). Toujours un nouveau pad — poser deux fois le
  /// même modèle donne deux pads. Le pad créé est rendu pour être mis en
  /// évidence.
  Future<QuickSearchPrepareResult> placeSavedMultipadOnBoard(
    SavedMultipad saved,
  ) async {
    final boardId = _activeBoardId;
    if (boardId == null || saved.sounds.isEmpty) {
      return const QuickSearchPrepareResult.none();
    }

    final placement = computeLastRowAppendPlacement([
      for (final item in _state.pads)
        if (!item.isDraft) item.pad,
    ], forceNewRow: _forceNewRowOnNextQuickAdd);
    _forceNewRowOnNextQuickAdd = false;

    final padId = await _repository.createPadWithSettings(
      boardId: boardId,
      soundIds: [for (final sound in saved.sounds) sound.id],
      name: saved.name,
      colorValue: saved.colorValue,
      playMode: saved.playMode,
      rowIndex: placement.rowIndex,
      sortOrder: placement.globalSortOrder,
    );
    await loadSounds(boardId: boardId, silent: true);

    final padItem = findPadItemById(padId);
    if (padItem == null) return const QuickSearchPrepareResult.none();
    _maybeAutoDownloadPad(padItem);
    return QuickSearchPrepareResult.highlight(padId);
  }

  int? beginDraftPad({required int rowIndex}) {
    final boardId = _activeBoardId;
    if (boardId == null) return null;

    final draftId = _draftPadIdSeq--;
    final pad = Pad(
      id: draftId,
      boardId: boardId,
      sortOrder: _state.pads.where((item) => !item.isDraft).length,
      rowIndex: rowIndex,
      createdAt: DateTime.now(),
    );
    final item = PadItem(pad: pad)..isDraft = true;
    _finalizePadAvailability(item);

    final pads = [..._state.pads, item];
    _syncMultipadNumbers(pads);
    _state = _state.copyWith(pads: pads);
    _notify();
    return draftId;
  }

  Future<void> updateDraftPadSounds(int draftPadId, List<int> soundIds) async {
    final item = findPadItemById(draftPadId);
    if (item == null || !item.isDraft) return;

    final sounds = <Sound>[];
    for (final id in soundIds) {
      final sound = await _repository.getSoundById(id);
      if (sound != null) sounds.add(sound);
    }

    item.pad = item.pad.copyWith(sounds: sounds);
    item.syncSlotCount();
    await _probePadLocalAvailability(item);
    _syncMultipadNumbers(_state.pads);
    item.bumpRevision();
    _notify();
  }

  void cancelDraftPad(int draftPadId) {
    final item = findPadItemById(draftPadId);
    if (item == null || !item.isDraft) return;

    item.dispose();
    final pads = _state.pads.where((pad) => pad.pad.id != draftPadId).toList();
    _syncMultipadNumbers(pads);
    _state = _state.copyWith(pads: pads);
    _notify();
  }

  Future<PadItem?> commitDraftPad({
    required int draftPadId,
    required List<int> soundIds,
  }) async {
    final draftIndex = _state.pads.indexWhere(
      (item) => item.pad.id == draftPadId && item.isDraft,
    );
    if (draftIndex < 0) return null;

    final draft = _state.pads[draftIndex];
    final boardId = _activeBoardId;
    if (boardId == null) return null;

    final padId = await _repository.createPadWithSettings(
      boardId: boardId,
      soundIds: soundIds,
      rowIndex: draft.pad.rowIndex,
    );

    final pads = await _loadPadsUseCase(boardId);
    Pad? createdPad;
    for (final pad in pads) {
      if (pad.id == padId) {
        createdPad = pad;
        break;
      }
    }
    if (createdPad == null) {
      cancelDraftPad(draftPadId);
      await loadSounds(boardId: boardId, silent: true);
      final fallback = _music._resolvePadItem(padId);
      if (fallback != null) _maybeAutoDownloadPad(fallback);
      return fallback;
    }

    draft.dispose();
    final padItem = PadItem(pad: createdPad);
    await _probePadLocalAvailability(padItem);

    final nextPads = List<PadItem>.from(_state.pads);
    nextPads[draftIndex] = padItem;
    _syncMultipadNumbers(nextPads);
    _state = _state.copyWith(pads: nextPads);
    _syncVoicesWithPads();
    _notify();

    unawaited(_loadPlayersForPadSafe(padItem, createdPad));
    _maybeAutoDownloadPad(padItem);
    return padItem;
  }
}
