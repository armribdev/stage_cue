/// Surface commune des lecteurs de pré-écoute (audition).
///
/// Deux implémentations la respectent :
/// - [AudioPlayerService] (flutter_soloud) — sortie « salle » par défaut ;
/// - `CuePreviewPlayer` (media_kit) — sortie « cue » sur un device séparé.
///
/// Le routage entre les deux se fait dans `CueAudioService.createPreviewPlayer`
/// selon le device de pré-écoute configuré (opt-in, desktop uniquement).
abstract interface class PreviewPlayback {
  /// Durée totale de la source (0 si indisponible).
  Duration get duration;

  /// Position de lecture courante (0 si aucune voix active).
  Duration get position;

  /// Vrai si au moins une voix est audible (hors pause).
  bool get isPlaying;

  /// Vrai si la lecture est en pause (source chargée, position conservée).
  bool get isPaused;

  /// Émet true à la lecture, false à l'arrêt ou en fin de piste.
  Stream<bool> get onPlayerStateChanged;

  /// Lance la lecture depuis [position] au volume [volume] (0.0 → 1.0).
  /// Retourne false si la voix n'a pas pu démarrer.
  Future<bool> playFromPosition(Duration position, {double volume});

  /// Met la lecture en pause (position conservée).
  Future<void> pause();

  /// Reprend la lecture après une pause.
  Future<void> resume();

  /// Arrête la lecture (la source reste chargée : re-lecture possible).
  Future<void> stop();

  /// Libère les ressources du lecteur.
  void dispose();
}
