part of 'sampler_provider.dart';

/// Résolution de chemin jouable et disponibilité locale des pads (sonde cache
/// Drive, raisons d'indisponibilité, retry). Méthodes de [SamplerNotifier]
/// extraites via extension dans le même `part` pour garder l'accès aux membres
/// privés sans changer l'API publique.

extension SamplerPadAvailability on SamplerNotifier {
  /// Résout le chemin local jouable d'un son (cache Drive si bibliothèque).
  Future<String> _resolvePlayablePath(
    Sound sound, {
    bool downloadIfNeeded = false,
  }) async {
    final libraryRepository = _libraryRepository;
    if (libraryRepository != null) {
      try {
        final resolved = await libraryRepository.resolvePlayablePath(
          sound,
          downloadIfNeeded: downloadIfNeeded,
        );
        final file = File(resolved);
        if (!await file.exists()) {
          throw StateError('Fichier audio introuvable : ${sound.displayName}');
        }
        return file.absolute.path;
      } on SoundNotAvailableLocallyException {
        rethrow;
      } catch (e) {
        debugPrint('Résolution du chemin échouée pour ${sound.title}: $e');
        if (sound.libraryId != null && sound.relativePath != null) rethrow;
        final file = File(sound.filePath);
        if (!await file.exists() || !await isPlausibleAudioFile(file)) {
          throw StateError('Fichier audio introuvable : ${sound.displayName}');
        }
        return file.absolute.path;
      }
    }

    final file = File(sound.filePath);
    if (!await file.exists() || !await isPlausibleAudioFile(file)) {
      throw StateError('Fichier audio introuvable : ${sound.displayName}');
    }
    return file.absolute.path;
  }

  PadUnavailabilityReason? _worstReason(
    PadUnavailabilityReason? current,
    PadUnavailabilityReason next,
  ) {
    const priority = {
      PadUnavailabilityReason.offline: 0,
      PadUnavailabilityReason.missingFile: 1,
      PadUnavailabilityReason.unsupportedFormat: 1,
      PadUnavailabilityReason.needsDownload: 2,
    };
    if (current == null) return next;
    return (priority[current] ?? 99) <= (priority[next] ?? 99) ? current : next;
  }

  PadSoundAvailability _availabilityFromException(Object e) {
    if (e is SoundNotAvailableLocallyException) {
      return e.isOffline
          ? PadSoundAvailability.offline
          : PadSoundAvailability.needsDownload;
    }
    return PadSoundAvailability.missingFile;
  }

  PadUnavailabilityReason? _unavailabilityFromAvailability(
    PadSoundAvailability availability,
  ) {
    return switch (availability) {
      PadSoundAvailability.ready => null,
      PadSoundAvailability.cached => null,
      PadSoundAvailability.needsDownload =>
        PadUnavailabilityReason.needsDownload,
      PadSoundAvailability.offline => PadUnavailabilityReason.offline,
      PadSoundAvailability.missingFile => PadUnavailabilityReason.missingFile,
      PadSoundAvailability.unsupportedFormat =>
        PadUnavailabilityReason.unsupportedFormat,
    };
  }

  PadUnavailabilityReason? _unavailabilityFromSlot(PadSoundSlot slot) {
    if (slot.isReady || slot.isCached) return null;
    if (slot.availability == PadSoundAvailability.ready) {
      return PadUnavailabilityReason.missingFile;
    }
    return _unavailabilityFromAvailability(slot.availability);
  }

  PadSoundAvailability _availabilityFromProbe(LocalSoundProbeResult result) {
    return switch (result) {
      LocalSoundProbeResult.cached => PadSoundAvailability.cached,
      LocalSoundProbeResult.needsDownload => PadSoundAvailability.needsDownload,
      LocalSoundProbeResult.offline => PadSoundAvailability.offline,
      LocalSoundProbeResult.missingFile => PadSoundAvailability.missingFile,
    };
  }

  void _blockSoundDriveRetry(int soundId) =>
      _driveNotFoundSoundIds.add(soundId);

  bool _isRetryableMissingLibrarySound(Sound sound) =>
      sound.libraryId != null &&
      sound.relativePath != null &&
      sound.relativePath!.isNotEmpty &&
      !_driveNotFoundSoundIds.contains(sound.id);

  bool isPadRetryableFromDrive(PadItem padItem) =>
      padItem.pad.sounds.any(_isRetryableMissingLibrarySound);

  bool isPadPreparable(PadItem padItem) => padItem.isPreparableForDownload;

  bool isPadTapBlocked(PadItem padItem) => padItem.isBlockedForPlayback;

  Future<void> _prepareRetryForMissingLibrarySound(
    PadItem padItem,
    int index,
  ) async {
    final sound = padItem.pad.sounds[index];
    if (!_isRetryableMissingLibrarySound(sound)) return;

    await _libraryRepository?.clearPlaybackBlockForSound(sound);
    padItem.slots[index] = PadSoundSlot(
      availability: PadSoundAvailability.needsDownload,
    );
    _finalizePadAvailability(padItem);
  }

  Future<PadSoundAvailability> _probeSoundLocalAvailability(Sound sound) async {
    final libraryRepository = _libraryRepository;
    if (libraryRepository != null &&
        sound.libraryId != null &&
        sound.relativePath != null &&
        sound.relativePath!.isNotEmpty) {
      // Sonde uniquement le cache local — pas de requête Drive ici.
      // Si le fichier est absent du cache, on reste en needsDownload.
      // L'état missingFile est établi à l'échec réel du téléchargement,
      // ce qui évite N requêtes Drive au chargement du plateau.
      return _availabilityFromProbe(
        await libraryRepository.probeLocalCache(sound),
      );
    }

    if (isKnownUnloadablePath(sound.filePath)) {
      return PadSoundAvailability.missingFile;
    }
    final file = File(sound.filePath);
    if (await isPlausibleAudioFile(file)) {
      return PadSoundAvailability.cached;
    }
    return PadSoundAvailability.missingFile;
  }

  Future<void> _probeSlotAtIndex(PadItem padItem, int index) async {
    if (index < 0 || index >= padItem.slots.length) return;
    final slot = padItem.slots[index];
    if (slot.isReady || slot.isCached) return;
    if (slot.availability == PadSoundAvailability.missingFile ||
        slot.availability == PadSoundAvailability.unsupportedFormat) {
      return;
    }

    final availability = await _probeSoundLocalAvailability(
      padItem.pad.sounds[index],
    );
    slot.dispose();
    padItem.slots[index] = PadSoundSlot(availability: availability);
  }

  Future<void> _probePadLocalAvailability(PadItem padItem) async {
    padItem.syncSlotCount();
    for (var i = 0; i < padItem.pad.sounds.length; i++) {
      await _probeSlotAtIndex(padItem, i);
    }
    _finalizePadAvailability(padItem);
  }

  /// Raison lisible pour laquelle [padItem] ne peut pas jouer, destinée au
  /// journal : c'est la réponse à « pourquoi ce pad n'a-t-il rien joué ? ».
  String triggerFailureReason(PadItem padItem) {
    if (padItem.pad.sounds.isEmpty) return 'pad sans son';
    if (padItem.isDownloading) return 'téléchargement en cours';
    if (isLiveOfflineMode && !padItem.hasLocallyAvailableSound) {
      return 'mode hors-ligne : fichier absent du cache local';
    }
    return switch (padItem.unavailabilityReason) {
      PadUnavailabilityReason.needsDownload =>
        'fichier non téléchargé (téléchargement à lancer)',
      PadUnavailabilityReason.offline => 'hors-ligne, fichier absent du cache',
      PadUnavailabilityReason.missingFile => 'fichier introuvable',
      PadUnavailabilityReason.unsupportedFormat =>
        'format audio non pris en charge',
      null =>
        driveSessionExpired
            ? 'session Google expirée, fichier non téléchargé'
            : 'aucun lecteur chargé (préchargement en cours ou échoué)',
    };
  }

  /// Journalise qu'un déclenchement n'a rien joué (warn, dédupliqué par
  /// [AudioLoadLog.padTriggerFailed]).
  void reportPadTriggerFailure(PadItem padItem, {String? reason}) {
    AudioLoadLog.padTriggerFailed(
      padId: padItem.pad.id,
      padLabel: padItem.displayName,
      reason: reason ?? triggerFailureReason(padItem),
    );
  }

  void _finalizePadAvailability(PadItem padItem) {
    if (padItem.isPlayable) {
      padItem.unavailabilityReason = null;
      return;
    }
    PadUnavailabilityReason? worst;
    for (final slot in padItem.slots) {
      final reason = _unavailabilityFromSlot(slot);
      if (reason != null) worst = _worstReason(worst, reason);
    }
    padItem.unavailabilityReason = worst;
  }
}
