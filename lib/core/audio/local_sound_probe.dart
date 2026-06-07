/// Résultat d'une sonde disque rapide (sans SoLoud ni réseau).
enum LocalSoundProbeResult {
  /// Fichier local valide détecté — lecteur SoLoud pas encore chargé.
  cached,

  /// Absent du cache, téléchargement possible.
  needsDownload,

  /// Absent du cache et Drive inaccessible.
  offline,

  /// Présent mais illisible, ou déjà signalé invalide.
  missingFile,
}
