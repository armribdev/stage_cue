part of 'sampler_provider.dart';

/// Pré-écoutes (recherche-éclair / bibliothèque), session live Mode Spectacle,
/// préparation quick-search et pads brouillon. Méthodes de [SamplerNotifier]
/// extraites via extension dans le même `part`.

extension SamplerPreviewsAndSession on SamplerNotifier {
  /// Pré-écoute d'un son (recherche-éclair).
  ///
  /// La musique passe par la régie live ; bruitages/ambiances en fire-and-forget
  /// depuis le [Sound.startOffsetMs].
  Future<bool> previewSound(int soundId) async {
    final sound = await _repository.getSoundById(soundId);
    if (sound == null) return false;
    if (sound.type == SoundType.music) {
      final padItem = await playMusicBySoundId(soundId);
      return padItem != null;
    }
    return _playEphemeralPreview(sound);
  }

  /// Son en cours d'aperçu dans la bibliothèque, ou `null`.
  int? get libraryPreviewSoundId => _libraryPreviewSoundId;

  /// Indique si l'aperçu bibliothèque de [soundId] est audible.
  bool libraryPreviewIsPlaying(int soundId) =>
      _libraryPreviewSoundId == soundId &&
      (_libraryPreviewPlayer?.isPlaying ?? false);

  /// Bascule play/pause pour l'aperçu bibliothèque (lecteur unique).
  Future<bool> toggleLibraryPreview(int soundId) async {
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

    stopLibraryPreview(notify: false);
    final sound = await _repository.getSoundById(soundId);
    if (sound == null) return false;
    return _startLibraryPreview(sound);
  }

  /// Arrête et libère l'aperçu bibliothèque.
  void stopLibraryPreview({bool notify = true}) {
    _libraryPreviewSub?.cancel();
    _libraryPreviewSub = null;
    _libraryPreviewPlayer?.dispose();
    _libraryPreviewPlayer = null;
    _libraryPreviewSoundId = null;
    if (notify) _notify();
  }

  Future<bool> _startLibraryPreview(Sound sound) async {
    try {
      final path = await _resolvePlayablePath(
        sound,
        downloadIfNeeded: allowsSoundDownload,
      );
      final player = await CueAudioService.instance.createPreviewPlayer(path);
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
      await player.playFromPosition(Duration(milliseconds: startOffsetMs));
      _markPlayed(sound.id);
      _notify();
      return true;
    } catch (e) {
      debugPrint('Aperçu bibliothèque échoué pour ${sound.title}: $e');
      stopLibraryPreview(notify: false);
      return false;
    }
  }

  /// Pré-écoute fire-and-forget depuis le point d'entrée du son.
  Future<bool> _playEphemeralPreview(Sound sound) async {
    try {
      final path = await _resolvePlayablePath(
        sound,
        downloadIfNeeded: allowsSoundDownload,
      );
      final player = await CueAudioService.instance.createPreviewPlayer(path);
      _previewPlayers.add(player);
      StreamSubscription<bool>? sub;
      sub = player.onPlayerStateChanged.listen((playing) {
        if (playing) return;
        sub?.cancel();
        _previewPlayers.remove(player);
        player.dispose();
        _notify();
      });
      var startOffsetMs = sound.startOffsetMs;
      final duration = player.duration;
      if (duration > Duration.zero) {
        final maxMs = duration.inMilliseconds;
        if (startOffsetMs >= maxMs) {
          startOffsetMs = (maxMs - 1).clamp(0, maxMs);
        }
      }
      await player.playFromPosition(Duration(milliseconds: startOffsetMs));
      _markPlayed(sound.id);
      _notify();
      return true;
    } catch (e) {
      debugPrint('Pré-écoute échouée pour ${sound.title}: $e');
      return false;
    }
  }

  /// Arrête et libère toutes les pré-écoutes en cours.
  void stopAllPreviews() {
    stopLibraryPreview(notify: false);
    if (_previewPlayers.isEmpty) return;
    final players = _previewPlayers.toList();
    _previewPlayers.clear();
    for (final player in players) {
      player.dispose();
    }
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
  /// son et active le suivi. `notifyListeners()` rafraîchit un éventuel
  /// `SoundPickerOverlay` déjà ouvert.
  void startLiveSession() {
    _sessionPlayCounts.clear();
    _isLiveSessionActive = true;
    _notify();
  }

  /// Termine la session live : gèle les compteurs (ni effacés, ni remis à
  /// zéro) — seule la prochaine [startLiveSession] repart propre.
  void endLiveSession() {
    _isLiveSessionActive = false;
    _notify();
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
  ) =>
      _pickLowestSessionCountIndex(padItem, readyIndices);

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

  Future<void> updateDraftPadSounds(
    int draftPadId,
    List<int> soundIds,
  ) async {
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
    final pads =
        _state.pads.where((pad) => pad.pad.id != draftPadId).toList();
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
