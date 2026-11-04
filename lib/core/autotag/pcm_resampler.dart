import 'dart:math' as math;
import 'dart:typed_data';

/// Demi-largeur du filtre, en échantillons d'entrée (96 coefficients).
const int _halfTaps = 48;

/// Coupure du filtre : 0,45 × la plus basse des deux fréquences.
const double _cutoffRatio = 0.45;

/// Rééchantillonne [input] de [inRate] vers [outRate] (mono, flottants).
///
/// Sinc fenêtré (Hann) en version polyphasée : les coefficients de chaque phase
/// sont calculés une fois, puis chaque échantillon de sortie est un produit
/// scalaire de 96 termes. Mesuré contre soxr sur des mp3 réels : SNR 73 dB
/// (ADR 0029). Calcul pur, prévu pour un isolate de travail.
Float32List resamplePcm(Float32List input, int inRate, int outRate) {
  if (inRate <= 0 || outRate <= 0) {
    throw ArgumentError('Fréquences invalides : $inRate → $outRate');
  }
  if (inRate == outRate) return Float32List.fromList(input);

  final g = _gcd(inRate, outRate);
  final step = inRate ~/ g; // avance d'entrée pour `phases` sorties
  final phases = outRate ~/ g;
  final outLen = input.length * outRate ~/ inRate;

  // Coupure exprimée en cycles par échantillon d'entrée ; plafonnée à la
  // fréquence d'entrée quand on suréchantillonne.
  final cutoff = _cutoffRatio * math.min(inRate, outRate) / inRate;
  const taps = 2 * _halfTaps;
  final bank = Float64List(phases * taps);
  for (var p = 0; p < phases; p++) {
    final frac = p / phases;
    var sum = 0.0;
    for (var j = 0; j < taps; j++) {
      // Entrée k = i0 - half + 1 + j, i0 = partie entière de la position.
      final d = (j - _halfTaps + 1) - frac;
      final sinc = d == 0
          ? 2 * cutoff
          : math.sin(2 * math.pi * cutoff * d) / (math.pi * d);
      final window = 0.5 + 0.5 * math.cos(math.pi * d / _halfTaps);
      final h = sinc * window;
      bank[p * taps + j] = h;
      sum += h;
    }
    // Gain continu unitaire pour chaque phase.
    for (var j = 0; j < taps; j++) {
      bank[p * taps + j] /= sum;
    }
  }

  final out = Float32List(outLen);
  final n = input.length;
  for (var o = 0; o < outLen; o++) {
    final pos = o * step;
    final i0 = pos ~/ phases;
    final base = (pos % phases) * taps;
    final first = i0 - _halfTaps + 1;
    var acc = 0.0;
    if (first >= 0 && first + taps <= n) {
      for (var j = 0; j < taps; j++) {
        acc += input[first + j] * bank[base + j];
      }
    } else {
      for (var j = 0; j < taps; j++) {
        final k = first + j;
        if (k >= 0 && k < n) acc += input[k] * bank[base + j];
      }
    }
    out[o] = acc;
  }
  return out;
}

int _gcd(int a, int b) {
  while (b != 0) {
    final t = a % b;
    a = b;
    b = t;
  }
  return a;
}
