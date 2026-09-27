part of 'sampler_provider.dart';

/// Téléchargements pad et préparation hors-ligne. Méthodes de
/// [SamplerNotifier] extraites via extension dans le même `part`.

extension SamplerPadDownloads on SamplerNotifier {
  /// Tâche de téléchargement éventuellement en vol pour ce pad — `null` si
  /// aucune, auquel cas l'appelant enfile **sans suspension** (le prefetch
  /// s'appuie sur l'ordre d'enqueue, cf. [_prefetchActiveBoard]).
  ///
  /// La file déduplique par `pad.id`, et c'est voulu : deux tâches concurrentes
  /// muteraient le même [PadItem] (slots, compteurs) sans verrou. Mais une
  /// demande de portée large (pad entier) tombant sur une tâche étroite (un
  /// slot) recevrait son future sans que les autres slots soient téléchargés.
  /// L'appelant attend donc la tâche en cours, puis reprend sur un état frais.
  ///
  /// Une seule attente, jamais de boucle : si un nouveau tap s'intercale entre
  /// l'attente et l'enfilage, on retombe sur la déduplication — fenêtre étroite,
  /// et sans conséquence pire que le comportement d'avant.
  Future<void>? _inFlightPadDownload(PadItem padItem) {
    final pending = _downloadQueue.inFlight(_resolveBoardPadItem(padItem).pad.id);
    // L'échec ou l'annulation de la tâche en cours ne doit pas empêcher la
    // reprise : on ne consomme que son achèvement.
    return pending?.catchError((_) {});
  }

  Future<bool> downloadPadSoundAtIndex(PadItem padItem, int index) async {
    if (!allowsSoundDownload) return false;
    // Sans cette attente, la dédup renverrait la disponibilité du PAD ENTIER
    // pour une question portant sur un slot précis.
    final pending = _inFlightPadDownload(padItem);
    if (pending != null) await pending;

    final resolved = _resolveBoardPadItem(padItem);
    if (index < 0 || index >= resolved.slots.length) return false;
    final slot = resolved.slots[index];
    if (slot.isReady) return true;
    if (slot.availability == PadSoundAvailability.unsupportedFormat) return false;
    if (slot.availability == PadSoundAvailability.missingFile) {
      if (!_isRetryableMissingLibrarySound(resolved.pad.sounds[index])) {
        return false;
      }
      await _prepareRetryForMissingLibrarySound(resolved, index);
    }

    try {
      return await _downloadQueue.enqueue<bool>(
        key: resolved.pad.id,
        priority: SamplerNotifier._downloadPriorityTap,
        task: () => _downloadPadSoundAtIndexImpl(resolved, index),
      );
    } on DownloadCancelledException {
      final current = _resolveBoardPadItem(padItem);
      return index < current.slots.length && current.slots[index].isReady;
    }
  }

  Future<bool> _downloadPadSoundAtIndexImpl(PadItem padItem, int index) async {
    if (padItem.isDownloading) {
      return padItem.slots[index].isReady;
    }

    final slot = padItem.slots[index];
    if (slot.isReady) return true;
    if (slot.availability == PadSoundAvailability.unsupportedFormat) return false;
    if (slot.availability == PadSoundAvailability.missingFile &&
        !_isRetryableMissingLibrarySound(padItem.pad.sounds[index])) {
      return false;
    }
    if (slot.availability == PadSoundAvailability.missingFile) {
      await _prepareRetryForMissingLibrarySound(padItem, index);
    }

    padItem.downloadingSlotIndex = index;
    _notifyPad(padItem);

    try {
      final libraryRepository = _libraryRepository;
      if (libraryRepository != null) {
        final connected = await libraryRepository.ensureDriveConnected();
        if (!connected) {
          if (slot.availability == PadSoundAvailability.needsDownload ||
              slot.availability == PadSoundAvailability.offline) {
            padItem.slots[index] = PadSoundSlot(
              availability: PadSoundAvailability.offline,
            );
          }
          _finalizePadAvailability(padItem);
          _notifyPad(padItem);
          _notify();
          return false;
        }
      }

      await _loadSlotAtIndex(padItem, index, downloadIfNeeded: true);

      if (padItem.isPlayable) {
        await _loadPlayersForPad(padItem, padItem.pad);
      } else {
        _finalizePadAvailability(padItem);
      }
      _notifyPad(padItem);
      _notify();
      return padItem.slots[index].isReady;
    } finally {
      padItem.downloadingSlotIndex = null;
      _notifyPad(padItem);
    }
  }

  Future<bool> downloadAndLoadPad(
    PadItem padItem, {
    int priority = SamplerNotifier._downloadPriorityTap,
  }) async {
    if (isLiveOfflineMode) return _resolveBoardPadItem(padItem).isPlayable;
    // Une tâche « un seul slot » peut être en vol : l'attendre, sinon la dédup
    // renverrait son résultat et les autres slots ne seraient jamais chargés.
    final pending = _inFlightPadDownload(padItem);
    if (pending != null) await pending;

    final resolved = _resolveBoardPadItem(padItem);
    try {
      return await _downloadQueue.enqueue<bool>(
        key: resolved.pad.id,
        priority: priority,
        task: () => _downloadAndLoadPadImpl(resolved),
      );
    } on DownloadCancelledException {
      return _resolveBoardPadItem(padItem).isPlayable;
    }
  }

  Future<bool> _downloadAndLoadPadImpl(PadItem padItem) async {
    if (padItem.isDownloading) return padItem.isPlayable;

    final pendingIndices = <int>[];
    for (var i = 0; i < padItem.slots.length; i++) {
      final slot = padItem.slots[i];
      if (slot.isReady) continue;
      if (slot.availability == PadSoundAvailability.unsupportedFormat) continue;
      if (slot.availability == PadSoundAvailability.missingFile) {
        if (!_isRetryableMissingLibrarySound(padItem.pad.sounds[i])) continue;
        await _prepareRetryForMissingLibrarySound(padItem, i);
      }
      pendingIndices.add(i);
    }
    if (pendingIndices.isEmpty) {
      if (padItem.isPlayable) return true;
      _finalizePadAvailability(padItem);
      _notifyPadAndBoard(padItem);
      return padItem.isPlayable;
    }

    padItem.isDownloading = true;
    padItem.downloadDone = 0;
    padItem.downloadTotal = pendingIndices.length;
    _notifyPad(padItem);

    try {
      final libraryRepository = _libraryRepository;
      if (libraryRepository != null) {
        final connected = await libraryRepository.ensureDriveConnected();
        if (!connected) {
          _markSlotsOffline(padItem);
          _notifyPadAndBoard(padItem);
          return false;
        }
      }

      for (final index in pendingIndices) {
        padItem.downloadingSlotIndex = index;
        _notifyPad(padItem);
        await _loadSlotAtIndex(padItem, index, downloadIfNeeded: true);
        padItem.downloadDone++;
        _notifyPad(padItem);
      }
    } finally {
      padItem.isDownloading = false;
      padItem.downloadDone = 0;
      padItem.downloadTotal = 0;
      padItem.downloadingSlotIndex = null;
      _notifyPad(padItem);
    }

    if (padItem.isPlayable) {
      await _loadPlayersForPad(padItem, padItem.pad);
    } else if (padItem.pendingDownloadCount > 0) {
      _markSlotsMissingAfterFailedDownload(padItem);
    } else {
      _finalizePadAvailability(padItem);
    }
    _notifyPadAndBoard(padItem);
    return padItem.isPlayable;
  }

  void _markSlotsOffline(PadItem padItem) {
    for (var i = 0; i < padItem.slots.length; i++) {
      final slot = padItem.slots[i];
      if (slot.availability == PadSoundAvailability.needsDownload ||
          slot.availability == PadSoundAvailability.offline) {
        padItem.slots[i] = PadSoundSlot(
          availability: PadSoundAvailability.offline,
        );
      }
    }
    _finalizePadAvailability(padItem);
  }

  void _markSlotsMissingAfterFailedDownload(PadItem padItem) {
    for (var i = 0; i < padItem.slots.length; i++) {
      if (padItem.slots[i].availability == PadSoundAvailability.needsDownload) {
        _blockSoundDriveRetry(padItem.pad.sounds[i].id);
        padItem.slots[i] = PadSoundSlot(
          availability: PadSoundAvailability.missingFile,
        );
      }
    }
    _finalizePadAvailability(padItem);
  }

  Future<void> prepareBoardForOffline() async {
    if (!allowsSoundDownload) return;
    if (_state.isBoardPreparing) return;

    final toDownload = _state.pads.where(isPadPreparable).toList();
    if (toDownload.isEmpty) return;

    _state = _state.copyWith(
      isBoardPreparing: true,
      boardPrepareDone: 0,
      boardPrepareTotal: toDownload.length,
    );
    _notify();

    try {
      for (var i = 0; i < toDownload.length; i++) {
        await downloadAndLoadPad(
          toDownload[i],
          priority: SamplerNotifier._downloadPriorityManualPrepare,
        );
        _state = _state.copyWith(boardPrepareDone: i + 1);
        _notify();
      }
    } finally {
      _state = _state.copyWith(isBoardPreparing: false);
      _notify();
    }
  }
}
