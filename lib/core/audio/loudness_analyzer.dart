import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'soloud_file_loader.dart';

/// Sonie cible (RMS linéaire, ≈ -20 dBFS) vers laquelle le volume « auto »
/// ramène un son. Un son plus fort est atténué ; un son plus doux reste à 1.0
/// (le volume par son est plafonné à 1.0, on ne peut pas amplifier).
const double kAutoVolumeTargetRms = 0.1;

/// Volume plancher du mode auto : évite qu'un fichier masterisé très fort ne
/// devienne quasi inaudible, ce qui trahirait plutôt une mesure aberrante.
const double kAutoVolumeMin = 0.05;

/// Nombre de fenêtres RMS demandées à SoLoud pour la mesure.
const int _analysisWindows = 1024;

/// Fenêtres plus douces que ce seuil (≈ -50 dBFS) : silence ou fin de queue,
/// exclues de la moyenne pour qu'un son court au milieu de silence ne soit pas
/// jugé trop doux.
const double _silenceGateRms = 0.003;

/// Mesure la sonie RMS globale de [filePath] (0–1, silences exclus), ou `null`
/// si le moteur n'est pas prêt, si le fichier est illisible ou entièrement
/// silencieux.
///
/// Même API et même file sérialisée que [extractWaveform] : le décodage natif
/// ne doit jamais s'exécuter en concurrence ([décision 0001]).
Future<double?> measureRms(String filePath) async {
  if (!SoLoud.instance.isInitialized) return null;
  try {
    final windows = await enqueueSoLoudFileTask(
      // ignore: experimental_member_use — API waveform de flutter_soloud.
      () => SoLoud.instance.readSamplesFromFile(
        filePath,
        _analysisWindows,
        average: true,
      ),
    );
    return rmsOfWindows(windows);
  } catch (e) {
    debugPrint('measureRms: mesure impossible ($filePath) — $e');
    return null;
  }
}

/// RMS global à partir de fenêtres RMS de durée égale : racine de la moyenne
/// des carrés, fenêtres sous le seuil de silence ignorées. `null` si aucune
/// fenêtre audible.
@visibleForTesting
double? rmsOfWindows(Float32List windows) {
  var sumSquares = 0.0;
  var count = 0;
  for (final w in windows) {
    final a = w.abs();
    if (a < _silenceGateRms) continue;
    sumSquares += a * a;
    count++;
  }
  if (count == 0) return null;
  return math.sqrt(sumSquares / count);
}

/// Volume (0–1) qui ramène un son de sonie [rms] à [kAutoVolumeTargetRms].
double autoVolumeForRms(double rms) {
  if (rms <= 0) return 1.0;
  return (kAutoVolumeTargetRms / rms).clamp(kAutoVolumeMin, 1.0);
}
