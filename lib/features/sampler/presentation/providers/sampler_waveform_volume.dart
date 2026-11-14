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

  /// Force une nouvelle extraction de l'enveloppe waveform d'un son, même si
  /// une enveloppe existe déjà — contrairement à [_ensureWaveformForSound],
  /// paresseux et gaté sur `waveform == null`. Action explicite demandée par
  /// l'opérateur depuis l'écran d'édition d'un son : télécharge le fichier si
  /// nécessaire (bibliothèque Drive non encore mise en cache).
  ///
  /// Peut lever [SoundNotAvailableLocallyException] ou [StateError] si le
  /// fichier est introuvable/hors ligne — laissé à l'appelant pour affichage.
  Future<WaveformProbeStatus> regenerateWaveform(Sound sound) async {
    final path = await _resolvePlayablePath(sound, downloadIfNeeded: true);
    final probe = await extractWaveform(path);
    if (probe.status != WaveformProbeStatus.transient) {
      await _repository.persistWaveformProbe(sound.id, probe);
    }
    return probe.status;
  }

  /// Volume « auto » d'un son : mesure sa sonie selon son type (sonie intégrée
  /// pour musique et ambiance, maximum court terme pour un bruitage) et renvoie
  /// le volume qui la ramène à la cible du type (normalisation). Un son sans
  /// type connu est traité comme de la musique. Ne persiste rien — l'appelant
  /// applique la valeur au formulaire, enregistrée au « Enregistrer » habituel.
  /// `null` si le fichier ne peut pas être mesuré (format non décodable, audio
  /// silencieux).
  ///
  /// Même contrat d'erreur que [regenerateWaveform] (fichier hors ligne).
  Future<double?> computeAutoVolume(Sound sound) async {
    final path = await _resolvePlayablePath(sound, downloadIfNeeded: true);
    return measureAutoVolume(File(path), loudnessProfileOf(sound.type));
  }
}
