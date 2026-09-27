part of 'sampler_provider.dart';

/// Édition des pads (réglages, volume, layout, undo, ajout/retrait).
/// Méthodes de [SamplerNotifier] extraites via extension dans le même `part`.

extension SamplerPadEditing on SamplerNotifier {
  Future<void> updatePadItemSettings(
    PadItem padItem, {
    Color? buttonColor,
    bool updateColor = false,
    String? displayName,
    bool updateDisplayName = false,
    PadPlayMode? playMode,
  }) async {
    var hasChanged = false;
    String? nextName = padItem.pad.name;
    int? nextColor = padItem.pad.colorValue;
    PadPlayMode? nextPlayMode;

    if (updateColor) {
      nextColor = buttonColor?.toARGB32();
      hasChanged = true;
    }
    if (updateDisplayName) {
      final trimmed = displayName?.trim();
      nextName = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
      if (nextName != padItem.pad.name) hasChanged = true;
    }
    if (playMode != null && playMode != padItem.pad.playMode) {
      nextPlayMode = playMode;
      hasChanged = true;
    }

    if (!hasChanged) return;

    padItem.pad = padItem.pad.copyWith(
      name: nextName,
      clearName: updateDisplayName && nextName == null,
      colorValue: nextColor,
      clearColor: updateColor && nextColor == null,
      playMode: nextPlayMode,
    );
    _notify();

    await _repository.updatePadSettings(
      padId: padItem.pad.id,
      name: nextName,
      updateName: updateDisplayName,
      colorValue: updateColor ? nextColor : null,
      updateColor: updateColor,
      playMode: nextPlayMode,
    );
  }

  /// Met à jour le volume d'un son DANS un pad (override propre à ce pad).
  /// [volume] null = suivre le volume par défaut du son. Applique le volume au
  /// lecteur en cours si ce son joue actuellement.
  Future<void> updatePadSoundVolume(
    PadItem padItem,
    int soundId,
    double? volume,
  ) async {
    final index = padItem.pad.sounds.indexWhere((s) => s.id == soundId);
    if (index < 0) return;

    final clamped = volume?.clamp(0.0, 1.0);
    final nextVolumes = List<double?>.filled(
      padItem.pad.sounds.length,
      null,
    );
    for (var i = 0; i < nextVolumes.length; i++) {
      nextVolumes[i] = i < padItem.pad.soundVolumes.length
          ? padItem.pad.soundVolumes[i]
          : null;
    }
    nextVolumes[index] = clamped;

    padItem.pad = padItem.pad.copyWith(soundVolumes: nextVolumes);

    // Applique en direct si ce son précis est en cours de lecture.
    if (padItem.isPlaying && padItem.currentSoundIndex == index) {
      padItem.currentPlayer
          ?.setVolume(_effectiveVolume(padItem, soundIndex: index));
    }
    _notify();

    await _repository.updatePadSoundVolume(
      padId: padItem.pad.id,
      soundId: soundId,
      volume: clamped,
    );
  }

  Future<void> updatePadRowIndex(int padId, int newRowIndex) async {
    await _repository.updatePadRowIndex(padId, newRowIndex);
    await loadSounds(silent: true);
  }

  Future<void> movePadToPosition(
    int padId,
    int targetRowIndex,
    int insertionPosition,
  ) async {
    final boardId = _activeBoardId;
    if (boardId == null) return;

    final drafts =
        _state.pads.where((item) => item.isDraft).toList(growable: false);

    final byRow = <int, List<PadItem>>{};
    for (final p in _state.pads) {
      if (p.isDraft) continue;
      (byRow[p.pad.rowIndex] ??= []).add(p);
    }
    for (final list in byRow.values) {
      list.sort((a, b) => a.pad.sortOrder.compareTo(b.pad.sortOrder));
    }

    int? sourceRowIndex;
    var sourceIndexInRow = -1;
    for (final entry in byRow.entries) {
      final idx = entry.value.indexWhere((p) => p.pad.id == padId);
      if (idx != -1) {
        sourceRowIndex = entry.key;
        sourceIndexInRow = idx;
        break;
      }
    }
    if (sourceRowIndex == null) return;

    final moved = byRow[sourceRowIndex]!.removeAt(sourceIndexInRow);
    final targetList = byRow[targetRowIndex] ?? <PadItem>[];
    final clampedPos = insertionPosition.clamp(0, targetList.length);

    targetList.insert(clampedPos, moved);
    byRow[targetRowIndex] = targetList;

    final allRows = byRow.keys.toList()..sort();
    final layout = <({int padId, int rowIndex, int sortOrder})>[];
    final newPadItems = <PadItem>[];
    var globalSort = 0;
    for (final rowIdx in allRows) {
      for (final item in byRow[rowIdx]!) {
        item.pad = item.pad.copyWith(
          rowIndex: rowIdx,
          sortOrder: globalSort,
        );
        layout.add((
          padId: item.pad.id,
          rowIndex: rowIdx,
          sortOrder: globalSort,
        ));
        newPadItems.add(item);
        globalSort++;
      }
    }

    _state = _state.copyWith(pads: [...newPadItems, ...drafts]);
    _notify();

    try {
      await _repository.applyPadsLayout(boardId, layout);
    } catch (e) {
      debugPrint('Erreur lors du déplacement du pad: $e');
      await loadSounds();
    }
  }

  Future<void> stopAllSounds() async {
    _music._musicAdvanceLockCount++;
    try {
      for (final padItem in _state.pads) {
        if (padItem.isPlaying) {
          await _stopAllSlotPlayers(padItem);
        }
      }
    } finally {
      if (_music._musicAdvanceLockCount > 0) _music._musicAdvanceLockCount--;
    }
    _music._clearMusicState();
    await _ambiance._stopImmediately();
    _notify();
  }

  Future<void> reorderSoundsFromList(List<PadItem> newOrder) async {
    if (_activeBoardId == null) return;
    _syncMultipadNumbers(newOrder);
    _state = _state.copyWith(pads: newOrder);
    _notify();
    try {
      await _repository.reorderBoardPads(
        _activeBoardId!,
        newOrder.map((p) => p.pad.id).toList(),
      );
    } catch (e) {
      debugPrint('Erreur lors du réordonnancement: $e');
      await loadSounds();
    }
  }

  Future<bool> removeSound(PadItem padItem) async {
    if (padItem.isDraft) {
      cancelDraftPad(padItem.pad.id);
      return true;
    }

    final currentBoardId = _activeBoardId;
    if (currentBoardId == null) return false;

    final previousIndex = _state.pads.indexOf(padItem);
    if (previousIndex < 0) return false;

    if (_removePadUseCase != null) {
      try {
        await _removePadUseCase(padItem.pad.id);
      } catch (e) {
        debugPrint('Erreur lors du retrait du pad: $e');
        _state = _state.copyWith(error: 'Impossible de retirer ce pad.');
        _notify();
        return false;
      }
    }

    _lastRemovedPad = _RemovedPadSnapshot(
      boardId: currentBoardId,
      pad: padItem.pad,
      index: previousIndex,
    );
    if (padItem.isPlaying) {
      try {
        await padItem.currentPlayer?.stop();
      } catch (_) {}
    }
    padItem.dispose();

    final remainingPads =
        _state.pads.where((p) => p != padItem).toList();
    _syncMultipadNumbers(remainingPads);
    _state = _state.copyWith(pads: remainingPads, error: null);
    _syncVoicesWithPads();
    _notify();
    return true;
  }

  Future<int?> undoLastRemoval() async {
    final snapshot = _lastRemovedPad;
    final currentBoardId = _activeBoardId;
    if (snapshot == null || currentBoardId == null) return null;
    if (snapshot.boardId != currentBoardId) return null;

    try {
      await _repository.createPadWithSettings(
        boardId: snapshot.boardId,
        soundIds: snapshot.pad.sounds.map((s) => s.id).toList(),
        name: snapshot.pad.name,
        colorValue: snapshot.pad.colorValue,
        soundVolumes: [
          for (var i = 0; i < snapshot.pad.sounds.length; i++)
            i < snapshot.pad.soundVolumes.length
                ? snapshot.pad.soundVolumes[i]
                : null,
        ],
        playMode: snapshot.pad.playMode,
        sortOrder: snapshot.index,
      );

      _lastRemovedPad = null;
      await loadSounds(boardId: snapshot.boardId);
      _state = _state.copyWith(error: null);
      _notify();

      final restored = _state.pads
          .where((p) => p.pad.sortOrder == snapshot.index)
          .firstOrNull;
      return restored?.pad.id;
    } catch (e) {
      debugPrint('Erreur lors de l\'annulation de suppression: $e');
      _state = _state.copyWith(
        error: 'Impossible d\'annuler la suppression du pad.',
      );
      _notify();
      return null;
    }
  }

  void _applySoundAddedToPad(
    PadItem padItem,
    Sound sound, {
    bool notify = true,
  }) {
    if (padItem.pad.sounds.any((s) => s.id == sound.id)) return;
    padItem.pad = padItem.pad.copyWith(
      sounds: [...padItem.pad.sounds, sound],
    );
    padItem.syncSlotCount();
    _finalizePadAvailability(padItem);
    _syncMultipadNumbers(_state.pads);
    if (!notify) return;
    _notifyPad(padItem);
    _notify();
  }

  void _applySoundRemovedFromPad(PadItem padItem, int soundId) {
    final index = padItem.pad.sounds.indexWhere((s) => s.id == soundId);
    if (index < 0) return;
    final sounds = List<Sound>.from(padItem.pad.sounds)..removeAt(index);
    padItem.pad = padItem.pad.copyWith(sounds: sounds);
    if (index < padItem.slots.length) {
      padItem.slots.removeAt(index).dispose();
    }
    padItem.syncSlotCount();
    _finalizePadAvailability(padItem);
    _syncMultipadNumbers(_state.pads);
    _notifyPad(padItem);
    _notify();
  }

  Future<void> _reloadPadPlayersInBackground(PadItem padItem) async {
    await _loadPlayersForPadSafe(padItem, padItem.pad);
    _notify();
  }

  Future<void> addSoundToPad(int padId, int soundId) async {
    final padItem = findPadItemById(padId);
    if (padItem == null) return;

    await _repository.addSoundToPad(padId, soundId);

    final sound = await _repository.getSoundById(soundId);
    if (sound == null) return;

    _applySoundAddedToPad(padItem, sound, notify: false);
    final slotIndex = padItem.pad.sounds.length - 1;
    await _probeSlotAtIndex(padItem, slotIndex);
    _finalizePadAvailability(padItem);
    _notifyPadAndBoard(padItem);
    unawaited(_reloadPadPlayersInBackground(padItem));
    _maybeAutoDownloadPadSound(padItem, slotIndex);
  }

  void _maybeAutoDownloadPadSound(PadItem padItem, int slotIndex) {
    if (_appPreferences?.autoDownloadPadSounds != true) return;
    if (_libraryRepository == null) return;
    if (slotIndex < 0 || slotIndex >= padItem.slots.length) return;
    final slot = padItem.slots[slotIndex];
    if (slot.isReady) return;
    if (slot.availability == PadSoundAvailability.unsupportedFormat) return;
    if (slot.availability == PadSoundAvailability.missingFile &&
        !_isRetryableMissingLibrarySound(padItem.pad.sounds[slotIndex])) {
      return;
    }
    unawaited(
      downloadPadSoundAtIndex(padItem, slotIndex).catchError((_) => false),
    );
  }

  void _maybeAutoDownloadPad(PadItem padItem) {
    if (_appPreferences?.autoDownloadPadSounds != true) return;
    if (_libraryRepository == null) return;
    if (padItem.pendingDownloadCount == 0) return;
    unawaited(downloadAndLoadPad(padItem).catchError((_) => false));
  }

  Future<void> removeSoundFromPad(int padId, int soundId) async {
    final padItem = findPadItemById(padId);
    if (padItem == null) return;
    if (padItem.pad.sounds.length <= 1) {
      await removeSound(padItem);
    } else {
      await _repository.removeSoundFromPad(padId, soundId);
      _applySoundRemovedFromPad(padItem, soundId);
    }
  }
}
