import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'soloud_file_loader.dart';

/// Nombre de barres de l'enveloppe waveform stockée par son (~1 octet/barre).
/// 480 offre un rendu fin même sur écran large, pour ~480 octets en base.
const int kWaveformBars = 480;

/// Génération de la CAPACITÉ d'extraction waveform. À INCRÉMENTER à chaque
/// montée de version de flutter_soloud (ou changement de logique d'extraction)
/// susceptible de faire réussir des fichiers auparavant en échec.
///
/// Sert de « tampon » sur les échecs `unsupported` persistés en base
/// (`sounds.waveformProbeGeneration`) : un fichier marqué en échec sous une
/// génération < à la génération courante est re-sondé automatiquement. C'est ce
/// qui « guérit » d'un coup les fichiers accentués sous Windows après le passage
/// en flutter_soloud 4.x (fix conversion UTF-8 de `readSamplesFromFile`).
///
/// - gén. 1 : flutter_soloud 3.x — `readSamplesFromFile` échouait sur les noms
///   de fichiers non-ASCII sous Windows (backend de sampling `NoBackend`).
/// - gén. 2 : flutter_soloud 4.x — conversion UTF-8 corrigée ; re-tente tout
///   fichier marqué en échec sous une génération antérieure.
const int kWaveformProbeGeneration = 2;

/// true si une (nouvelle) extraction est justifiée pour un son musique dont
/// l'enveloppe est absente : jamais tentée (`generation == null`), ou échec
/// enregistré sous une génération d'extraction devenue obsolète.
bool waveformNeedsProbe(int? generation) =>
    generation == null || generation < kWaveformProbeGeneration;

/// Issue d'une tentative d'extraction, qui pilote la persistance et le retry.
enum WaveformProbeStatus {
  /// Enveloppe extraite avec succès.
  success,

  /// Échec TRANSITOIRE (moteur audio non initialisé) : rien à mémoriser, on
  /// retentera librement à la prochaine occasion.
  transient,

  /// Le backend de sampling refuse ce fichier à CETTE génération (format non
  /// géré, MP3 exotique, ou audio silencieux). On mémorise la génération pour ne
  /// pas re-sonder en boucle ; re-tenté seulement après un bump de génération.
  unsupported,
}

/// Résultat d'`extractWaveform` : le statut + l'éventuelle enveloppe, et les deux
/// valeurs à écrire en base (`waveform` et `waveformProbeGeneration`).
@immutable
class WaveformProbe {
  final WaveformProbeStatus status;
  final Uint8List? bytes;

  const WaveformProbe._(this.status, [this.bytes]);
  const WaveformProbe.success(Uint8List bytes)
      : this._(WaveformProbeStatus.success, bytes);
  const WaveformProbe.transient() : this._(WaveformProbeStatus.transient);
  const WaveformProbe.unsupported() : this._(WaveformProbeStatus.unsupported);

  /// Valeur à écrire dans `sounds.waveform` (null hors succès).
  Uint8List? get waveformValue => bytes;

  /// Valeur à écrire dans `sounds.waveformProbeGeneration` :
  /// - `unsupported` → génération courante (bloque le retry jusqu'au prochain bump) ;
  /// - `success`/`transient` → null (efface tout marqueur / re-tentera).
  int? get generationValue =>
      status == WaveformProbeStatus.unsupported ? kWaveformProbeGeneration : null;
}

/// Décode [filePath] hors du thread UI (SoLoud le fait via un isolate interne)
/// et renvoie une enveloppe RMS quantifiée : [kWaveformBars] octets, chacun
/// dans 0–255, normalisés par le pic pour remplir la hauteur.
///
/// Le résultat porte un [WaveformProbeStatus] pour que l'appelant persiste soit
/// l'enveloppe (succès), soit la génération d'échec (`unsupported`), soit rien
/// (`transient`) — l'affichage retombe alors sur la barre linéaire.
Future<WaveformProbe> extractWaveform(
  String filePath, {
  int bars = kWaveformBars,
}) async {
  if (!SoLoud.instance.isInitialized) {
    // Moteur pas prêt : ce n'est pas un défaut du fichier — on ne mémorise rien.
    return const WaveformProbe.transient();
  }

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
    if (samples.isEmpty) {
      debugPrint(
        'extractWaveform: aucun échantillon lu ($filePath) — fichier vide ou '
        'silencieux ; marqué non extractible (gén. $kWaveformProbeGeneration).',
      );
      return const WaveformProbe.unsupported();
    }

    var peak = 0.0;
    for (final s in samples) {
      final a = s.abs();
      if (a > peak) peak = a;
    }
    if (peak <= 0) {
      debugPrint(
        'extractWaveform: audio silencieux ($filePath) — marqué non extractible '
        '(gén. $kWaveformProbeGeneration).',
      );
      return const WaveformProbe.unsupported();
    }

    final out = Uint8List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      out[i] = ((samples[i].abs() / peak) * 255).round().clamp(0, 255);
    }
    return WaveformProbe.success(out);
  } catch (e) {
    debugPrint(
      'extractWaveform: le backend de lecture d\'échantillons a refusé '
      '"$filePath" (gén. $kWaveformProbeGeneration) — ${_describeSamplingError(e)}',
    );
    return const WaveformProbe.unsupported();
  }
}

/// Message lisible pour les échecs du backend de sampling. Le cas le plus
/// fréquent (`NoBackend`) n'est PAS un fichier cassé : la lecture normale
/// fonctionne, c'est le décodeur d'échantillons (séparé) qui refuse le format.
String _describeSamplingError(Object e) {
  final text = e.toString();
  if (text.contains('NoBackend')) {
    return 'format non géré par le décodeur d\'échantillons (MP3 VBR, en-tête '
        'exotique ou — avant flutter_soloud 4.x — nom de fichier accentué sous '
        'Windows). La lecture, elle, reste possible. Détail: $text';
  }
  return text;
}

/// Convertit l'enveloppe stockée (octets 0–255) en amplitudes 0.0–1.0 prêtes à
/// dessiner. Renvoie une liste vide si [bytes] est nul ou vide.
List<double> decodeWaveformBars(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return const [];
  return [for (final b in bytes) b / 255.0];
}
