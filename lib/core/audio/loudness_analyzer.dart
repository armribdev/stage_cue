import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../features/sampler/domain/entities/sound.dart' show SoundType;
import '../autotag/audio_stream_info.dart';
import '../autotag/pcm_decoder.dart' show readLeftChannelWindow;
import 'audio_load_log.dart';
import 'gain.dart';
import 'soloud_file_loader.dart' show enqueueSoLoudFileTask;

/// Gain plancher du mode auto : évite qu'un fichier masterisé très fort ne
/// devienne quasi inaudible, ce qui trahirait plutôt une mesure aberrante. C'est
/// le bas de la plage du curseur de gain ([kGainMinDb]) : « Auto » ne pose
/// jamais un gain que la fiche ne saurait afficher.
final double kAutoVolumeMin = dbToGain(kGainMinDb);

/// Pic d'échantillon maximal visé après relèvement, en dBFS. Franchement sous
/// 0 dBFS : le mixage de SoLoud écrête net la somme des voix (arrondi doux
/// désactivé), donc un son relevé jusqu'à 0 dBFS saturerait dès qu'il joue par
/// dessus une musique ([décision 0044]).
const double kPeakCeilingDb = -3;

/// Marge de pic supplémentaire, en dB, quand le fichier n'a été mesuré que par
/// morceaux (> 60 s) : le vrai pic a pu passer entre deux morceaux.
const double kSampledPeakMarginDb = 3;

/// Relèvement maximal du gain auto, en dB : borne une cible aberrante (fichier
/// quasi silencieux). Haut de la plage du curseur de gain ([kGainMaxDb]), donc
/// de ce que le lecteur du casque sait rendre.
const double kMaxBoostDb = kGainMaxDb;

/// Génération de la mesure du gain « auto » (cibles de [LoudnessProfile] et
/// formule d'[autoLoudnessGain]), persistée dans `sounds.gainMeasureGeneration`
/// avec chaque gain mesuré. À incrémenter quand une cible ou la formule change
/// au point que les gains déjà écrits seraient à refaire : « Recalculer » (les
/// non mesurés, ou tous) rattrape alors les sons de génération antérieure.
const int kGainMeasureGeneration = 1;

/// Ce que le volume « auto » cherche à égaliser selon le type de son
/// ([décision 0036], amendée par [décision 0044]).
///
/// Le gain de sonie peut relever un son jusqu'à [kMaxBoostDb], sans jamais
/// dépasser le plafond de pic [kPeakCeilingDb] : un fichier plus doux que sa
/// cible est relevé, un fichier plus fort est atténué. Ce sont des valeurs de
/// départ, à ajuster à l'oreille.
enum LoudnessProfile {
  /// Morceau : sonie intégrée (BS.1770, sur la durée).
  music(targetLufs: -20, momentaryMax: false),

  /// Fond sonore en boucle : intégrée aussi, mais 6 LU sous la musique pour
  /// rester en retrait.
  ambiance(targetLufs: -26, momentaryMax: false),

  /// Bruitage : la force perçue est celle de l'attaque, pas la moyenne sur un
  /// fichier fait surtout de queue ou de silence — on mesure le maximum
  /// court terme (400 ms).
  effect(targetLufs: -16, momentaryMax: true);

  const LoudnessProfile({required this.targetLufs, required this.momentaryMax});

  final double targetLufs;
  final bool momentaryMax;
}

/// Profil de mesure d'un son d'après son type ; un type inconnu est traité
/// comme de la musique.
LoudnessProfile loudnessProfileOf(SoundType? type) => switch (type) {
  SoundType.soundEffect => LoudnessProfile.effect,
  SoundType.ambiance => LoudnessProfile.ambiance,
  SoundType.music || null => LoudnessProfile.music,
};

/// Durée d'un morceau lu en une fois, en secondes.
const int _chunkSeconds = 10;

/// Nombre maximal de morceaux lus : au-delà, on échantillonne le fichier à
/// intervalles réguliers plutôt que de le décoder en entier (≈ 100 ms par
/// morceau de 10 s sur la file de décodage native).
const int _maxChunks = 6;

/// Marge de lecture au-delà de la fenêtre demandée (voir `pcm_decoder.dart`).
const double _windowMarginSeconds = 0.05;

/// En dessous, le morceau n'est pas mesurable (fichier réduit à un clic).
const int _minChunkFrames = 32;

/// Blocs de 400 ms recouverts à 75 % (ITU-R BS.1770-4).
const double _blockSeconds = 0.4;
const double _hopSeconds = 0.1;

/// Début de morceau écarté : le temps que les filtres se stabilisent.
const double _warmupSeconds = 0.1;

const double _absoluteGateLufs = -70;
const double _relativeGateLu = 10;

/// Débuts (secondes entières) des morceaux à lire pour un fichier de
/// [duration] secondes : tout le fichier s'il est court, sinon [_maxChunks]
/// morceaux répartis de bout en bout.
@visibleForTesting
List<int> loudnessChunkStarts(double duration) {
  final count = (duration / _chunkSeconds).ceil();
  if (count <= _maxChunks) {
    return [for (var i = 0; i < count; i++) i * _chunkSeconds];
  }
  final span = duration - _chunkSeconds;
  return [
    for (var i = 0; i < _maxChunks; i++) (span * i / (_maxChunks - 1)).floor(),
  ];
}

typedef _Biquad = ({double b0, double b1, double b2, double a1, double a2});

/// Étage 1 de la pondération K : étagère aiguë (+4 dB vers 1,7 kHz), qui
/// modélise l'acoustique de la tête. Coefficients valables pour toute fréquence
/// d'échantillonnage (transformée bilinéaire des paramètres de BS.1770).
_Biquad _highShelf(int fs) {
  const f0 = 1681.974450955533;
  const gain = 3.999843853973347;
  const q = 0.7071752369554196;
  final k = math.tan(math.pi * f0 / fs);
  final vh = math.pow(10, gain / 20).toDouble();
  final vb = math.pow(vh, 0.4996667741545416).toDouble();
  final a0 = 1 + k / q + k * k;
  return (
    b0: (vh + vb * k / q + k * k) / a0,
    b1: 2 * (k * k - vh) / a0,
    b2: (vh - vb * k / q + k * k) / a0,
    a1: 2 * (k * k - 1) / a0,
    a2: (1 - k / q + k * k) / a0,
  );
}

/// Étage 2 de la pondération K : passe-haut à 38 Hz (RLB).
_Biquad _highPass(int fs) {
  const f0 = 38.13547087602444;
  const q = 0.5003270373238773;
  final k = math.tan(math.pi * f0 / fs);
  final a0 = 1 + k / q + k * k;
  return (
    b0: 1,
    b1: -2,
    b2: 1,
    a1: 2 * (k * k - 1) / a0,
    a2: (1 - k / q + k * k) / a0,
  );
}

/// Filtre [x] avec [c] (forme transposée directe II).
Float64List _filter(Float64List x, _Biquad c) {
  final y = Float64List(x.length);
  var z1 = 0.0, z2 = 0.0;
  for (var i = 0; i < x.length; i++) {
    final v = x[i];
    final out = c.b0 * v + z1;
    z1 = c.b1 * v - c.a1 * out + z2;
    z2 = c.b2 * v - c.a2 * out;
    y[i] = out;
  }
  return y;
}

/// Énergie moyenne (carré moyen du signal pondéré K) de chaque bloc de 400 ms
/// de [pcm] (mono, à [sampleRate]).
///
/// Un morceau plus court qu'un bloc (clic, bruitage bref) donne un bloc unique
/// sur ce qui existe, au lieu d'être dilué par du silence artificiel.
@visibleForTesting
List<double> kWeightedBlockEnergies(Float32List pcm, int sampleRate) {
  final n = pcm.length;
  if (n == 0) return const [];
  var y = Float64List(n);
  for (var i = 0; i < n; i++) {
    y[i] = pcm[i];
  }
  y = _filter(_filter(y, _highShelf(sampleRate)), _highPass(sampleRate));

  final skip = math.min((_warmupSeconds * sampleRate).round(), n ~/ 4);
  // Sommes cumulées des carrés : l'énergie d'un bloc se lit en deux accès.
  final cumulative = Float64List(n - skip + 1);
  for (var i = skip; i < n; i++) {
    cumulative[i - skip + 1] = cumulative[i - skip] + y[i] * y[i];
  }
  final length = n - skip;
  final block = (_blockSeconds * sampleRate).round();
  if (length < block) return [cumulative[length] / length];
  final hop = math.max(1, (_hopSeconds * sampleRate).round());
  return [
    for (var s = 0; s + block <= length; s += hop)
      (cumulative[s + block] - cumulative[s]) / block,
  ];
}

double _lufs(double energy) => energy <= 0
    ? double.negativeInfinity
    : -0.691 + 10 * math.log(energy) / math.ln10;

double _mean(Iterable<double> values) =>
    values.fold(0.0, (a, b) => a + b) / values.length;

/// Sonie (LUFS) d'un fichier d'après les énergies de ses blocs, ou `null` si
/// rien n'est audible (sous −70 LUFS).
///
/// [momentaryMax] : maximum court terme (bruitages). Sinon sonie intégrée de
/// BS.1770 : blocs sous −70 LUFS écartés, puis blocs sous la moyenne − 10 LU
/// (les passages très doux ne tirent pas la mesure vers le bas).
@visibleForTesting
double? loudnessLufs(List<double> energies, {required bool momentaryMax}) {
  if (momentaryMax) {
    final peak = energies.fold(0.0, math.max);
    final lufs = _lufs(peak);
    return lufs > _absoluteGateLufs ? lufs : null;
  }
  final audible = energies.where((e) => _lufs(e) > _absoluteGateLufs).toList();
  if (audible.isEmpty) return null;
  final relativeGate = _lufs(_mean(audible)) - _relativeGateLu;
  final kept = audible.where((e) => _lufs(e) > relativeGate).toList();
  return _lufs(_mean(kept));
}

/// Ce qu'une mesure du fichier a relevé : sonie et pic, et si le pic vaut pour
/// tout le fichier.
class LoudnessMeasurement {
  const LoudnessMeasurement({
    required this.lufs,
    required this.peak,
    required this.wholeFile,
  });

  /// Sonie (LUFS) selon le profil de mesure (intégrée ou maximum court terme).
  final double lufs;

  /// Pic d'échantillon, en valeur absolue (1.0 = 0 dBFS), **du canal gauche
  /// seul** : le décodeur d'analyse ne lit pas l'autre (voir
  /// `readLeftChannelWindow`). Le plafond de [kPeakCeilingDb] sert de marge.
  final double peak;

  /// Vrai si tout le fichier a été lu ; faux s'il n'a été lu que par morceaux,
  /// auquel cas le vrai pic peut être plus haut que [peak].
  final bool wholeFile;
}

/// Gain linéaire (celui de `sounds.gain`) qui ramène [m] à la cible de
/// [profile] ([décision 0044]).
///
/// Vers le bas (son plus fort que la cible) : le gain de la cible, jamais sous
/// [kAutoVolumeMin] — le pic n'intervient pas, il ne force jamais une
/// atténuation. Vers le haut : le gain de la cible, borné par le plafond de pic
/// ([kPeakCeilingDb], plus [kSampledPeakMarginDb] si le fichier est échantillonné)
/// et par [kMaxBoostDb] ; un pic déjà au-dessus du plafond laisse le son à 1.0
/// plutôt que de l'atténuer.
double autoLoudnessGain(LoudnessMeasurement m, LoudnessProfile profile) {
  final wanted = math.pow(10, (profile.targetLufs - m.lufs) / 20).toDouble();
  if (wanted <= 1.0) return wanted.clamp(kAutoVolumeMin, 1.0);
  final peakDb = 20 * math.log(m.peak) / math.ln10;
  final margin = m.wholeFile ? 0.0 : kSampledPeakMarginDb;
  final headroom = math.pow(10, (kPeakCeilingDb - margin - peakDb) / 20);
  final ceiling = math.pow(10, kMaxBoostDb / 20);
  return math
      .max(1.0, math.min(wanted, math.min(headroom, ceiling)))
      .toDouble();
}

/// Plus grand écart à zéro de [pcm] (pic d'échantillon, 0 si vide).
@visibleForTesting
double samplePeak(Float32List pcm) {
  var peak = 0.0;
  for (final v in pcm) {
    final a = v.abs();
    if (a > peak) peak = a;
  }
  return peak;
}

/// Mesure de [file] (sonie selon [profile], pic), ou `null` si elle ne peut pas
/// être faite (format non décodable, audio silencieux) : l'appelant garde alors
/// le réglage par défaut. [autoLoudnessGain] en tire le gain à stocker.
///
/// Mesure le canal gauche, par morceaux de 10 s lus avec le décodeur d'analyse
/// ([readLeftChannelWindow] : tampons libérés, contrairement à l'API Dart de
/// flutter_soloud, [décision 0029]) et sérialisés sur la file de décodage
/// natif ([décision 0001]).
Future<LoudnessMeasurement?> measureAutoVolume(
  File file,
  LoudnessProfile profile,
) async {
  try {
    final info = await probeAudioStreamInfo(file);
    final path = file.path;
    final rate = info.sampleRate;
    final duration = info.durationSeconds;
    final energies = <double>[];
    var peak = 0.0;
    for (final start in loudnessChunkStarts(duration)) {
      final length = math.min(_chunkSeconds.toDouble(), duration - start);
      final frames = (length * rate).floor();
      if (frames < _minChunkFrames) continue;
      final raw = await enqueueSoLoudFileTask(
        () => Isolate.run(
          () => readLeftChannelWindow(
            path,
            startSeconds: start,
            frames: frames,
            endSeconds: start + length + _windowMarginSeconds,
          ),
        ),
      );
      final chunk = await Isolate.run(
        () => (kWeightedBlockEnergies(raw, rate), samplePeak(raw)),
      );
      energies.addAll(chunk.$1);
      peak = math.max(peak, chunk.$2);
    }
    final lufs = loudnessLufs(energies, momentaryMax: profile.momentaryMax);
    if (lufs == null) {
      AudioLoadLog.trace('measureAutoVolume: audio silencieux ($path).');
      return null;
    }
    final wholeFile = (duration / _chunkSeconds).ceil() <= _maxChunks;
    AudioLoadLog.trace(
      'measureAutoVolume: ${lufs.toStringAsFixed(1)} LUFS, pic '
      '${peak.toStringAsFixed(3)}, ${wholeFile ? 'fichier entier' : 'échantillonné'} '
      '($path).',
    );
    return LoudnessMeasurement(lufs: lufs, peak: peak, wholeFile: wholeFile);
  } on AudioNotAnalyzable catch (e) {
    AudioLoadLog.warnOnce(
      'loudness:${e.reason}',
      'Gain auto : mesure impossible (${e.reason}) — gain '
          'conservé.',
    );
    return null;
  } catch (e) {
    AudioLoadLog.warnOnce(
      'loudness:${e.runtimeType}',
      'Gain auto : mesure en échec ($e) — gain conservé.',
    );
    return null;
  }
}
