part of 'sampler_provider.dart';

/// Waveform d'un son et volume « auto » (sonie).
/// Méthodes de [SamplerNotifier] extraites via extension dans le même `part`.

extension SamplerWaveformVolume on SamplerNotifier {
  /// Calcule et persiste l'enveloppe waveform d'un son (tout type) dont le
  /// fichier vient d'être chargé, si elle manque ou si elle date d'une
  /// génération d'extraction obsolète (`waveformNeedsProbe`). Réinjecte ensuite
  /// le son (avec sa waveform) dans le pad en mémoire et notifie — la régie
  /// l'affiche dès qu'elle est prête, sans bloquer le démarrage de la lecture.
  Future<void> _ensureWaveformForSound(
    PadItem padItem,
    int index,
    String filePath,
  ) async {
    if (index < 0 || index >= padItem.pad.sounds.length) return;
    final sound = padItem.pad.sounds[index];
    // Génération courante (enveloppe ou échec « format » déjà acté) : rien à faire.
    if (!waveformNeedsProbe(sound.waveformProbeGeneration)) return;
    // Simple rafraîchissement d'une enveloppe déjà affichable : jamais en Mode
    // Spectacle. L'extraction décode le fichier entier sur la file native
    // partagée avec le préchargement (décision 0001) — elle retarderait le
    // chargement des pads pour un gain purement cosmétique. Reporté à la
    // prochaine session hors spectacle.
    if (sound.waveform != null && isLiveSessionActive) return;

    // Le board peut changer pendant le décodage (tâche de fond) : on capture son
    // identité pour ne pas muter/notifier un plateau devenu obsolète après l'await.
    final boardId = padItem.pad.boardId;

    final probe = await extractWaveform(filePath);
    if (_activeBoardId != boardId) return;
    // Moteur non prêt : rien à persister, on retentera au prochain chargement.
    if (probe.status == WaveformProbeStatus.transient) return;

    try {
      // Persiste soit l'enveloppe (succès), soit le marqueur d'échec (unsupported).
      await _repository.persistWaveformProbe(sound.id, probe);
    } catch (e) {
      AudioLoadLog.warn('Persistance waveform échouée (${sound.title}): $e');
      return;
    }
    if (_activeBoardId != boardId) return;

    // Le pad a pu changer depuis (re-tri, suppression) : relocaliser par id.
    final freshIndex = padItem.pad.sounds.indexWhere((s) => s.id == sound.id);
    if (freshIndex < 0) return;
    // Réinjecte le son à jour même sur un échec `unsupported` : l'entité en
    // mémoire porte alors la génération d'échec, ce qui évite de re-sonder le
    // même fichier au prochain chargement de ce slot dans la même session.
    final updated = await _repository.getSoundById(sound.id);
    if (updated == null || _activeBoardId != boardId) return;
    final sounds = List<Sound>.from(padItem.pad.sounds);
    sounds[freshIndex] = updated;
    padItem.pad = padItem.pad.copyWith(sounds: sounds);
    // Ne notifier que sur un vrai changement visuel (nouvelle enveloppe).
    if (probe.status == WaveformProbeStatus.success) _notify();
  }

  /// Enveloppe waveform de [soundId], calculée **à la demande** quand un écran
  /// l'affiche (régie musique, fiche de la bibliothèque) et que le son n'en a
  /// pas encore : les sons indexés avant que la waveform couvre tous les types
  /// n'en ont jamais eu, et seul le chargement d'un pad la rattrapait. À lancer
  /// en tâche de fond (`unawaited`) : le décodage passe par la file native.
  ///
  /// Relit le son en base (l'entité de l'écran peut être périmée) et ne
  /// télécharge rien. Une fois l'enveloppe disponible, la réinjecte dans les
  /// pads en mémoire (scène et hors-scène) et notifie, d'où l'affichage de la
  /// régie. `null` si rien à afficher : fichier indisponible, format refusé
  /// (mémorisé, pas de nouvelle tentative), moteur pas prêt (on retentera).
  Future<Uint8List?> ensureWaveform(int soundId) async {
    final sound = await _repository.getSoundById(soundId);
    if (sound == null) return null;

    var waveform = sound.waveform;
    if (waveform == null && waveformNeedsProbe(sound.waveformProbeGeneration)) {
      final String path;
      try {
        path = await _resolvePlayablePath(sound);
      } catch (e) {
        AudioLoadLog.trace(
          'Waveform « ${sound.title} » : fichier indisponible ($e)',
        );
        return null;
      }
      final probe = await extractWaveform(path);
      if (probe.status == WaveformProbeStatus.transient) return null;
      await _repository.persistWaveformProbe(sound.id, probe);
      waveform = probe.waveformValue;
    }
    if (waveform != null) await refreshSoundMetadata(soundId);
    return waveform;
  }

  /// Gain de sonie « auto » d'un son : mesure sa sonie et son pic selon son type
  /// (sonie intégrée pour musique et ambiance, maximum court terme pour un
  /// bruitage) et renvoie le facteur qui la ramène à la cible du type, relevé au
  /// plus jusqu'au plafond de pic (décision 0044). Un son sans type connu est
  /// traité comme de la musique. Ne persiste rien — l'appelant garde la valeur
  /// dans le formulaire, enregistrée au « Enregistrer » habituel. `null` si le
  /// fichier ne peut pas être mesuré (format non décodable, audio silencieux).
  ///
  /// Peut lever [SoundNotAvailableLocallyException] ou [StateError] si le
  /// fichier est introuvable/hors ligne — laissé à l'appelant pour affichage.
  Future<double?> computeAutoLoudnessGain(Sound sound) async {
    final path = await _resolvePlayablePath(sound, downloadIfNeeded: true);
    final profile = loudnessProfileOf(sound.type);
    final measurement = await measureAutoVolume(File(path), profile);
    return measurement == null ? null : autoLoudnessGain(measurement, profile);
  }
}
