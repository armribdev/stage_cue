import 'dart:ui';

/// Outils de rendu d'une enveloppe waveform : ré-échantillonnage de l'enveloppe
/// stockée (voir `waveform_extractor.dart`, ~480 points) vers la densité de
/// pixels disponible, et construction du chemin continu rempli en miroir autour
/// de l'axe médian.
///
/// Remplace l'ancien rendu « bâton » (barres espacées). L'enveloppe hugge les
/// crêtes point par point : le tracé est plus précis et lit mieux les
/// transitoires courts que la nouvelle indexation sur-échantillonnée préserve.
class WaveformEnvelope {
  const WaveformEnvelope._();

  /// Densité de tracé : un point d'enveloppe tous les [pointSpacing] pixels.
  /// ~1,5 px offre un contour lisse sans multiplier inutilement les segments.
  static const double pointSpacing = 1.5;

  /// Nombre de points d'enveloppe à tracer pour une largeur [width] donnée.
  static int pointCountFor(double width) {
    if (width <= 0) return 0;
    return (width / pointSpacing).ceil().clamp(2, 4096);
  }

  /// Ré-échantillonne [src] (amplitudes 0..1) vers [count] points.
  ///
  /// - Sur-échantillonnage (count > src.length) : interpolation linéaire entre
  ///   points voisins → contour lisse, pas de marches d'escalier.
  /// - Sous-échantillonnage (count <= src.length) : PIC (max) de chaque groupe →
  ///   préserve les crêtes au lieu de les moyenner.
  static List<double> resample(List<double> src, int count) {
    if (src.isEmpty || count <= 0) return const [];
    if (src.length == 1) return List<double>.filled(count, src.first);

    if (count >= src.length) {
      final out = List<double>.filled(count, 0);
      final lastSrc = src.length - 1;
      for (var i = 0; i < count; i++) {
        // Position fractionnaire dans la source, bornes incluses.
        final pos = i * lastSrc / (count - 1);
        final lo = pos.floor();
        final hi = (lo + 1).clamp(0, lastSrc);
        final t = pos - lo;
        out[i] = src[lo] + (src[hi] - src[lo]) * t;
      }
      return out;
    }

    final out = List<double>.filled(count, 0);
    for (var t = 0; t < count; t++) {
      final start = (t * src.length) ~/ count;
      var end = ((t + 1) * src.length) ~/ count;
      if (end <= start) end = start + 1;
      if (end > src.length) end = src.length;
      var peak = 0.0;
      for (var j = start; j < end; j++) {
        if (src[j] > peak) peak = src[j];
      }
      out[t] = peak;
    }
    return out;
  }

  /// Construit le chemin fermé d'une enveloppe symétrique pour [amps] (0..1)
  /// réparties sur toute la largeur de [size], en miroir autour de l'axe médian.
  ///
  /// [minHalf] garantit un plancher visuel : même un silence garde une fine
  /// bande centrale au lieu de disparaître.
  static Path buildPath(List<double> amps, Size size, {double minHalf = 0.75}) {
    final path = Path();
    if (amps.isEmpty || size.width <= 0) return path;

    final centerY = size.height / 2;
    final maxHalf = size.height / 2;
    final n = amps.length;
    // n points répartis de x=0 à x=width (bornes incluses).
    final dx = n == 1 ? 0.0 : size.width / (n - 1);

    double halfAt(int i) => (amps[i] * maxHalf).clamp(minHalf, maxHalf);

    // Bord supérieur, gauche → droite.
    path.moveTo(0, centerY - halfAt(0));
    for (var i = 1; i < n; i++) {
      path.lineTo(i * dx, centerY - halfAt(i));
    }
    // Bord inférieur, droite → gauche (miroir).
    for (var i = n - 1; i >= 0; i--) {
      path.lineTo(i * dx, centerY + halfAt(i));
    }
    path.close();
    return path;
  }
}
