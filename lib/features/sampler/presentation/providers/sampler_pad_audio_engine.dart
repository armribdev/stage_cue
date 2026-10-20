part of 'sampler_provider.dart';

/// Chargement des lecteurs audio des pads : slots, préchargement séquentiel,
/// listeners de fin de lecture et prefetch du plateau actif. Méthodes de
/// [SamplerNotifier] extraites via extension dans le même `part`.

extension SamplerPadAudioEngine on SamplerNotifier {
  Future<void> _loadSlotAtIndex(
    PadItem padItem,
    int index, {
    bool downloadIfNeeded = false,
  }) async {
    final previousSlot = padItem.slots[index];
    final keepReadyAppearance = previousSlot.appearsReady;

    try {
      previousSlot.dispose();
    } catch (e) {
      debugPrint('Dispose slot échoué: $e');
    }

    padItem.slots[index] = keepReadyAppearance
        ? PadSoundSlot(availability: PadSoundAvailability.cached)
        : PadSoundSlot();

    final sound = padItem.pad.sounds[index];
    String? resolvedPath;
    try {
      resolvedPath = await _resolvePlayablePath(
        sound,
        downloadIfNeeded: downloadIfNeeded,
      );
      if (isKnownUnloadablePath(resolvedPath)) {
        throw StateError('Fichier audio déjà signalé illisible');
      }
      padItem.slots[index] = PadSoundSlot(
        availability: PadSoundAvailability.ready,
        player: await AudioPlayerService.create(resolvedPath),
      );
      await _syncPadSoundMetadata(padItem, index);
      // Calcul paresseux de la waveform (régie musique) — en tâche de fond pour
      // ne pas retarder le démarrage de la lecture.
      unawaited(_ensureWaveformForSound(padItem, index, resolvedPath));
    } on SoundNotAvailableLocallyException catch (e) {
      padItem.slots[index] = PadSoundSlot(
        availability: _availabilityFromException(e),
      );
    } on UnsupportedAudioFormatException {
      _blockSoundDriveRetry(sound.id);
      padItem.slots[index] = PadSoundSlot(
        availability: PadSoundAvailability.unsupportedFormat,
      );
    } catch (e, stack) {
      if (resolvedPath != null) {
        markPathUnloadable(resolvedPath);
      }
      if (downloadIfNeeded ||
          (e is StateError && e.message.contains('introuvable sur Drive'))) {
        _blockSoundDriveRetry(sound.id);
      }
      AudioLoadLog.soundLoadFailed(
        soundId: sound.id,
        title: sound.displayName,
        padId: padItem.pad.id,
        resolvedPath: resolvedPath,
        legacyPath: sound.filePath,
        error: e,
        stackTrace: stack,
      );
      padItem.slots[index] = PadSoundSlot(
        availability: PadSoundAvailability.missingFile,
      );
    }
  }

  Future<void> _loadPlayersForPadSafe(PadItem padItem, Pad pad) async {
    final padLabel = padItem.displayName;
    try {
      await _loadPlayersForPad(padItem, pad);
      _notifyPad(padItem);
    } catch (e, stack) {
      AudioLoadLog.padPlayersFailed(
        padId: pad.id,
        padLabel: padLabel,
        error: e,
        stackTrace: stack,
      );
      _finalizePadAvailability(padItem);
      _notifyPad(padItem);
    }
  }

  Future<void> _preloadPadPlayersSequential(
    List<PadItem> padItems,
    int generation,
  ) async {
    final boardId = _activeBoardId;
    if (boardId == null || padItems.isEmpty) return;

    AudioLoadLog.preloadStarted(boardId: boardId, padCount: padItems.length);
    final stopwatch = Stopwatch()..start();
    for (final padItem in padItems) {
      if (generation != _padPreloadGeneration) {
        AudioLoadLog.preloadCancelled(boardId: boardId);
        return;
      }
      await _loadPlayersForPadSafe(padItem, padItem.pad);
    }

    if (generation != _padPreloadGeneration) {
      AudioLoadLog.preloadCancelled(boardId: boardId);
      return;
    }

    AudioLoadLog.preloadFinished(
      boardId: boardId,
      padCount: padItems.length,
      unavailableCount: padItems
          .where((item) => item.pad.sounds.isNotEmpty && !item.isPlayable)
          .length,
      elapsed: stopwatch.elapsed,
    );
    _notify();
    unawaited(_prefetchActiveBoard());
  }

  Future<void> _loadPlayersForPad(PadItem padItem, Pad pad) async {
    final alreadyReady = padItem.slots.where((s) => s.isReady).length;
    AudioLoadLog.trace(
      '[LOAD-PAD] pad="${pad.displayName}" id=${pad.id} '
      'sounds=${pad.sounds.length} slotsReady=$alreadyReady',
    );
    padItem.pad = pad;
    padItem.syncSlotCount();

    for (var i = 0; i < pad.sounds.length; i++) {
      if (isLiveOfflineMode && !padItem.slots[i].appearsReady) continue;
      if (padItem.slots[i].isReady) continue;
      if (padItem.slots[i].availability == PadSoundAvailability.missingFile) {
        continue;
      }
      await _loadSlotAtIndex(padItem, i);
    }

    _finalizePadAvailability(padItem);
    _attachPlayerListeners(padItem);
    AudioLoadLog.trace(
      '[LOAD-PAD] done pad="${pad.displayName}" '
      'isPlayable=${padItem.isPlayable} unavailabilityReason=${padItem.unavailabilityReason}',
    );
  }

  void _attachPlayerListeners(PadItem padItem) {
    int attachedCount = 0;
    for (var i = 0; i < padItem.slots.length; i++) {
      final slot = padItem.slots[i];
      final idx = i;
      // attachListener annule toute subscription précédente — exactement un
      // listener actif par player, même si appelé plusieurs fois sur le même pad.
      slot.attachListener((playing) {
        AudioLoadLog.trace(
          '[LISTENER] pad="${padItem.pad.displayName}" slot=$idx playing=$playing '
          'currentPlayerIndex=${padItem._currentPlayerIndex} isPlaying=${padItem.isPlaying}',
        );
        if (padItem.pad.isAmbiancePad) {
          // Ambiance : mono-voix en boucle. L'antenne est posée explicitement
          // par AmbianceController ; seule une fin inattendue la retire ici.
          if (playing) {
            padItem._currentPlayerIndex = idx;
            padItem.isPlaying = true;
          } else if (padItem._currentPlayerIndex == idx) {
            padItem.isPlaying = false;
            padItem._currentPlayerIndex = null;
            _ambiance._handleAmbiancePlaybackEnded(padItem);
          }
        } else if (padItem.pad.isMusicPad) {
          // Musique : mono-voix, la variante courante est la source de vérité.
          if (playing) {
            padItem._currentPlayerIndex = idx;
            padItem.isPlaying = true;
            // Ne pas mettre à jour currentMusicPad pendant un fondu enchaîné :
            // crossfadeToNextMusic démarre le prochain lecteur à volume 0, ce
            // qui déclenche playing=true avant la fin du fondu. La mise à jour
            // explicite en fin de fondu est la source de vérité.
            if (!_music._skipMusicAutoAdvance) {
              _state = _state.copyWith(currentMusicPad: padItem);
            }
          } else if (padItem._currentPlayerIndex == idx) {
            padItem.isPlaying = false;
            padItem._currentPlayerIndex = null;
            _music._handleMusicPlaybackEnded(padItem);
          } else {
            AudioLoadLog.trace(
              '[LISTENER] ↩ false ignored: currentPlayerIndex=${padItem._currentPlayerIndex} != slot=$idx',
            );
          }
        } else {
          // Non-musique : polyphonie. isPlaying reflète l'ensemble des variantes
          // encore actives (plusieurs voix peuvent se superposer sur un pad).
          if (playing) {
            padItem._currentPlayerIndex = idx;
            padItem.isPlaying = true;
          } else {
            final anyPlaying = padItem.slots.any(
              (s) => s.player?.isPlaying ?? false,
            );
            padItem.isPlaying = anyPlaying;
            if (!anyPlaying) padItem._currentPlayerIndex = null;
          }
        }
        AudioLoadLog.trace(
          '[LISTENER] after: isPlaying=${padItem.isPlaying} '
          'currentPlayerIndex=${padItem._currentPlayerIndex}',
        );
        _notify();
      });
      if (slot.player != null) attachedCount++;
    }
    AudioLoadLog.trace(
      '[ATTACH] pad="${padItem.pad.displayName}" attached $attachedCount listeners '
      '(total slots=${padItem.slots.length})',
    );
  }

  Future<void> _prefetchActiveBoard() async {
    if (!allowsSoundDownload) return;
    final libraryRepository = _libraryRepository;
    if (libraryRepository == null) return;

    final generation = ++_prefetchGeneration;
    final boardId = _activeBoardId;
    if (boardId == null) return;
    if (_state.isBoardPreparing) return;

    if (!await libraryRepository.ensureDriveConnected()) return;
    if (generation != _prefetchGeneration || _activeBoardId != boardId) return;

    _downloadQueue.cancelQueued(
      (key, priority) => priority <= SamplerNotifier._downloadPriorityPrefetch,
    );

    // Favoris d'abord, puis par dernière lecture (desc), puis par position grille.
    // Les tâches sont enfilées dans cet ordre : à priorité égale la file est FIFO,
    // donc le seq d'enqueue détermine l'ordre effectif de téléchargement.
    final padsToFetch = List<PadItem>.from(_state.pads)
      ..sort((a, b) {
        final aFav = a.pad.sounds.any((s) => s.isFavorite) ? 1 : 0;
        final bFav = b.pad.sounds.any((s) => s.isFavorite) ? 1 : 0;
        if (aFav != bFav) return bFav - aFav;

        DateTime? latestFor(PadItem item) => item.pad.sounds
            .map((s) => s.lastPlayedAt)
            .whereType<DateTime>()
            .fold<DateTime?>(
              null,
              (best, d) => best == null || d.isAfter(best) ? d : best,
            );

        final aLast = latestFor(a);
        final bLast = latestFor(b);
        if (aLast == null && bLast == null) return 0;
        if (aLast == null) return 1;
        if (bLast == null) return -1;
        return bLast.compareTo(aLast);
      });

    for (final padItem in padsToFetch) {
      if (padItem.pendingDownloadCount == 0) continue;
      unawaited(
        downloadAndLoadPad(
          padItem,
          priority: SamplerNotifier._downloadPriorityPrefetch,
        ).catchError((_) => false),
      );
    }
  }
}
