/// Durées prédéfinies pour les fondus et enchaînements musique.
enum MusicTransitionDuration {
  /// Fade out ~2 s.
  short(Duration(seconds: 2)),

  /// Fade out ~8 s.
  long(Duration(seconds: 8));

  const MusicTransitionDuration(this.duration);

  final Duration duration;
}

/// Durées prédéfinies pour les enchaînements (crossfade).
enum MusicCrossfadeDuration {
  /// Crossfade ~3 s.
  short(Duration(seconds: 3)),

  /// Crossfade ~10 s.
  long(Duration(seconds: 10));

  const MusicCrossfadeDuration(this.duration);

  final Duration duration;
}
