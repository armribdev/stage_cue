import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'soloud_file_loader.dart';

/// Nombre de barres de l'enveloppe waveform stockée par son (~1 octet/barre).
/// 480 offre un rendu fin même sur écran large, pour ~480 octets en base.
const int kWaveformBars = 480;

/// Décode [filePath] hors du thread UI (SoLoud le fait via un isolate interne)
/// et renvoie une enveloppe RMS quantifiée : [kWaveformBars] octets, chacun
/// dans 0–255, normalisés par le pic pour remplir la hauteur.
///
/// Renvoie `null` si le moteur n'est pas prêt, si le fichier est illisible, ou
/// si l'audio est silencieux — l'appelant retombe alors sur la barre linéaire.
Future<Uint8List?> extractWaveform(
  String filePath, {
  int bars = kWaveformBars,
}) async {
  if (!SoLoud.instance.isInitialized) return null;

  try {
    // `average: true` → chaque valeur retournée est la RMS des échantillons de
    // sa barre (toujours positive) : exactement l'enveloppe visuelle voulue.
    // Sérialisé sur la file de `loadMem` : évite un accès natif concurrent au
    // moteur SoLoud (isolate `compute`) pendant le préchargement d'un board.
    final samples = await enqueueSoLoudFileTask(
      // ignore: experimental_member_use — API waveform de flutter_soloud (stable en pratique).
      () => SoLoud.instance.readSamplesFromFile(
        filePath,
        bars,
        average: true,
      ),
    );
    if (samples.isEmpty) return null;

    var peak = 0.0;
    for (final s in samples) {
      final a = s.abs();
      if (a > peak) peak = a;
    }
    if (peak <= 0) return null;

    final out = Uint8List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      out[i] = ((samples[i].abs() / peak) * 255).round().clamp(0, 255);
    }
    return out;
  } catch (e) {
    debugPrint('extractWaveform échoué ($filePath): $e');
    return null;
  }
}

/// Convertit l'enveloppe stockée (octets 0–255) en amplitudes 0.0–1.0 prêtes à
/// dessiner. Renvoie une liste vide si [bytes] est nul ou vide.
List<double> decodeWaveformBars(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return const [];
  return [for (final b in bytes) b / 255.0];
}
