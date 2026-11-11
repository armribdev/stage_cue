import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../features/sampler/domain/entities/sound.dart' show SoundType;
import '../autotag/audio_stream_info.dart';
import '../autotag/pcm_decoder.dart' show readLeftChannelWindow;
import 'audio_load_log.dart';
import 'soloud_file_loader.dart' show enqueueSoLoudFileTask;

/// Volume plancher du mode auto : évite qu'un fichier masterisé très fort ne
/// devienne quasi inaudible, ce qui trahirait plutôt une mesure aberrante.
const double kAutoVolumeMin = 0.05;

/// Ce que le volume « auto » cherche à égaliser selon le type de son
/// ([décision 0036]).
///
/// Le volume par son est plafonné à 1.0 : on ne peut qu'atténuer. Les cibles
/// sont donc posées assez bas pour que la plupart des fichiers soient au-dessus
/// (donc ramenés à la cible) ; un fichier plus doux garde 1.0 et reste en
/// dessous. Ce sont des valeurs de départ, à ajuster à l'oreille.
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

/// Volume (0–1) qui ramène une sonie de [lufs] à la cible de [profile].
double autoVolumeForLoudness(double lufs, LoudnessProfile profile) {
  final gain = math.pow(10, (profile.targetLufs - lufs) / 20).toDouble();
  return gain.clamp(kAutoVolumeMin, 1.0);
}

/// Volume « auto » de [file] selon [profile], ou `null` s'il ne peut pas être
/// mesuré (format non décodable, audio silencieux) : l'appelant garde alors le
/// volume par défaut.
///
/// Mesure le canal gauche, par morceaux de 10 s lus avec le décodeur d'analyse
/// ([readLeftChannelWindow] : tampons libérés, contrairement à l'API Dart de
/// flutter_soloud, [décision 0029]) et sérialisés sur la file de décodage
/// natif ([décision 0001]).
Future<double?> measureAutoVolume(File file, LoudnessProfile profile) async {
  try {
    final info = await probeAudioStreamInfo(file);
    final path = file.path;
    final rate = info.sampleRate;
    final duration = info.durationSeconds;
    final energies = <double>[];
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
      energies.addAll(
        await Isolate.run(() => kWeightedBlockEnergies(raw, rate)),
      );
    }
    final lufs = loudnessLufs(energies, momentaryMax: profile.momentaryMax);
    if (lufs == null) {
      AudioLoadLog.trace('measureAutoVolume: audio silencieux ($path).');
      return null;
    }
    return autoVolumeForLoudness(lufs, profile);
  } on AudioNotAnalyzable catch (e) {
    AudioLoadLog.warnOnce(
      'loudness:${e.reason}',
      'Volume auto : mesure impossible (${e.reason}) — volume par défaut '
          'conservé.',
    );
    return null;
  } catch (e) {
    AudioLoadLog.warnOnce(
      'loudness:${e.runtimeType}',
      'Volume auto : mesure en échec ($e) — volume par défaut conservé.',
    );
    return null;
  }
}
