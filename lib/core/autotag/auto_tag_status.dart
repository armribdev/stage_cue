/// Où en est l'analyse automatique d'un son, tel qu'affiché dans sa fiche
/// (décisions 0029 à 0031).
enum SoundAnalysisStatus {
  /// Pas une musique : l'analyse ne s'applique qu'aux musiques.
  notMusic,

  /// Son « traité » : ses suggestions sont figées, l'IA n'y revient plus.
  processed,

  /// Éligible, jamais analysé : l'analyse peut être lancée.
  pending,

  /// Éligible, mais le pack de modèles n'est pas installé.
  packMissing,

  /// Dans la file d'un passage en cours, pas encore son tour.
  queued,

  /// Son en cours d'analyse à l'instant.
  analyzing,

  /// Empreinte calculée, suggestions pas encore posées (bibliothèque analysée
  /// trop petite pour recentrer les scores).
  awaitingSuggestions,

  /// Analyse terminée (avec ou sans suggestion).
  analyzed,

  /// Écarté pour de bon (format, durée, silence…).
  skipped,
}

/// Ce que fait le passage d'analyse en cours, publié par `AutoTagService`.
///
/// [queuedSoundIds] est une vue en lecture seule sur la file du service : elle
/// se vide au fil du passage, une nouvelle [AutoTagActivity] est publiée à
/// chaque son.
class AutoTagActivity {
  final bool running;
  final int? currentSoundId;
  final Set<int> queuedSoundIds;

  const AutoTagActivity({
    this.running = false,
    this.currentSoundId,
    this.queuedSoundIds = const {},
  });

  static const AutoTagActivity idle = AutoTagActivity();

  /// [SoundAnalysisStatus.analyzing] / [SoundAnalysisStatus.queued] si le
  /// passage en cours s'occupe de ce son, `null` sinon.
  SoundAnalysisStatus? liveStatusOf(int soundId) {
    if (!running) return null;
    if (currentSoundId == soundId) return SoundAnalysisStatus.analyzing;
    if (queuedSoundIds.contains(soundId)) return SoundAnalysisStatus.queued;
    return null;
  }
}
