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

  /// Bascule play/pause pour l'aperçu (lecteur unique, un son à la fois). C'est
  /// le seul point d'entrée de la pré-écoute : elle reste étrangère aux pads,
  /// à la régie et au bouton « Tout arrêter ».
  ///
  /// [requireCue] : n'a de sens qu'au casque — échoue plutôt que de sortir sur
  /// la salle quand aucun casque n'est configuré.
  Future<bool> toggleLibraryPreview(
    int soundId, {
    bool requireCue = false,
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
    stopLibraryPreview(notify: false);
    final sound = await _repository.getSoundById(soundId);
    if (sound == null) return false;
    return _startLibraryPreview(sound, requireCue: requireCue);
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

  /// Répercute en direct un changement de volume sur l'aperçu bibliothèque de
  /// [soundId] (curseur du formulaire d'édition). Sans effet si ce son n'est
  /// pas celui en aperçu.
  void setLibraryPreviewVolume(int soundId, double volume) {
    if (_libraryPreviewSoundId != soundId) return;
    _libraryPreviewPlayer?.setVolume(volume);
  }

  void stopLibraryPreview({bool notify = true}) {
    _libraryPreviewSub?.cancel();
    _libraryPreviewSub = null;
    _libraryPreviewPlayer?.dispose();
    _libraryPreviewPlayer = null;
    _libraryPreviewSoundId = null;
    if (notify) _notify();
  }

  Future<bool> _startLibraryPreview(
    Sound sound, {
    bool requireCue = false,
  }) async {
    try {
      final path = await _resolvePlayablePath(
        sound,
        downloadIfNeeded: allowsSoundDownload,
      );
      final player = await CueAudioService.instance.createPreviewPlayer(
        path,
        requireCue: requireCue,
      );
      _libraryPreviewPlayer = player;
      _libraryPreviewSoundId = sound.id;
      _libraryPreviewSub = player.onPlayerStateChanged.listen((playing) {
        if (playing) return;
        stopLibraryPreview();
      });
      var startOffsetMs = sound.startOffsetMs;
      final duration = player.duration;
      if (duration > Duration.zero) {
        final maxMs = duration.inMilliseconds;
        if (startOffsetMs >= maxMs) {
          startOffsetMs = (maxMs - 1).clamp(0, maxMs);
        }
      }
      await player.playFromPosition(
        Duration(milliseconds: startOffsetMs),
        volume: sound.volume,
      );
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
