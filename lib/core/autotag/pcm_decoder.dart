import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../audio/soloud_file_loader.dart' show enqueueSoLoudFileTask;
import 'audio_stream_info.dart';
import 'pcm_resampler.dart';

/// Fréquence d'entrée du modèle d'analyse.
const int kAnalysisSampleRate = 24000;

/// Durée d'un clip analysé, en secondes.
const int kClipSeconds = 10;

/// Positions des clips dans le morceau (fraction de la durée).
const List<double> kClipPositions = [0.15, 0.45, 0.75];

/// Marge de lecture au-delà de la fenêtre : garde `totalFrames` du décodeur
/// natif ≥ au nombre d'échantillons demandés (sinon il en renvoie moins), tout
/// en restant sous deux fois ce nombre (sinon il sous-échantillonne).
const double _windowMarginSeconds = 0.05;

/// Début (secondes entières) de chaque clip pour un morceau de [duration]
/// secondes. Les débuts sont entiers pour que les calculs flottants du
/// décodeur natif restent exacts ; les clips d'un morceau court se recouvrent
/// éventuellement mais ne sont jamais dupliqués.
List<int> clipStartSeconds(
  double duration, {
  int clipSeconds = kClipSeconds,
  List<double> positions = kClipPositions,
}) {
  final latest = (duration - clipSeconds - 1).floor();
  if (latest < 0) {
    throw AudioNotAnalyzable(
      'morceau trop court (${duration.toStringAsFixed(1)} s)',
    );
  }
  return {
    for (final p in positions) math.min((duration * p).floor(), latest),
  }.toList()..sort();
}

/// Un clip est inutilisable si sa dernière seconde est entièrement nulle :
/// silence numérique, ou fenêtre qui dépasse la fin du fichier (durée mp3
/// estimée trop longue) que le décodeur natif complète par des zéros.
bool isUsableClip(Float32List clip, int sampleRate) {
  final tail = math.min(sampleRate, clip.length);
  for (var i = clip.length - tail; i < clip.length; i++) {
    if (clip[i] != 0) return true;
  }
  return false;
}

/// Décode [file] en clips mono 24 kHz prêts pour le modèle.
///
/// Lève [AudioNotAnalyzable] quand le fichier ne peut pas (ou ne doit pas)
/// être analysé : format, durée ou fréquence illisibles, morceau trop court,
/// décodeur natif qui refuse, clips tous silencieux. Toute autre exception est
/// une erreur inattendue.
///
/// Le décodage natif est sérialisé sur la file unique de SoLoud
/// ([enqueueSoLoudFileTask], ADR 0001), un clip à la fois, et le travail lourd
/// (lecture, rééchantillonnage) s'exécute dans des isolates.
Future<List<Float32List>> decodeAnalysisClips(
  File file, {
  int clipSeconds = kClipSeconds,
}) async {
  final info = await probeAudioStreamInfo(file);
  final starts = clipStartSeconds(
    info.durationSeconds,
    clipSeconds: clipSeconds,
  );
  final frames = info.sampleRate * clipSeconds;
  final clips = <Float32List>[];
  for (final start in starts) {
    // La file de décodage natif n'est tenue que le temps de la lecture d'un
    // clip (≈ 100 ms) : un chargement de pad qui s'y glisse n'attend jamais
    // plus. Le rééchantillonnage, lui, tourne hors file.
    final raw = await enqueueSoLoudFileTask(
      () => Isolate.run(
        () => readLeftChannelWindow(
          file.path,
          startSeconds: start,
          frames: frames,
          endSeconds: start + clipSeconds + _windowMarginSeconds,
        ),
      ),
    );
    final clip = await Isolate.run(
      () => resamplePcm(raw, info.sampleRate, kAnalysisSampleRate),
    );
    if (isUsableClip(clip, kAnalysisSampleRate)) clips.add(clip);
  }
  if (clips.isEmpty) throw const AudioNotAnalyzable('clips silencieux');
  return clips;
}

// ── Lecture native ──────────────────────────────────────────────────────────

typedef _ReadSamplesNative =
    ffi.UnsignedInt Function(
      ffi.Pointer<Utf8>,
      ffi.Float,
      ffi.Float,
      ffi.UnsignedLong,
      ffi.Bool,
      ffi.Pointer<ffi.Float>,
    );
typedef _ReadSamples =
    int Function(
      ffi.Pointer<Utf8>,
      double,
      double,
      int,
      bool,
      ffi.Pointer<ffi.Float>,
    );

ffi.DynamicLibrary _openSoLoudLibrary() =>
    Platform.isLinux || Platform.isAndroid
    ? ffi.DynamicLibrary.open('libflutter_soloud_plugin.so')
    : Platform.isWindows
    ? ffi.DynamicLibrary.open('flutter_soloud_plugin.dll')
    : ffi.DynamicLibrary.process();

/// Lit [frames] trames PCM du canal **gauche** de [path], à partir de
/// [startSeconds], à la **fréquence native** du fichier.
///
/// Détourne `readSamplesFromFile` de flutter_soloud, qui n'est pas un
/// décodeur : avec `average: false` et un nombre d'échantillons égal au nombre
/// de trames de la fenêtre (pas de 1), il renvoie le premier canal de chaque
/// trame. Ce comportement n'est pas un contrat du paquet — `pcm_decoder_test`
/// échoue s'il change (ADR 0029).
///
/// On appelle le symbole natif directement plutôt que l'API Dart
/// (`SoLoud.readSamplesFromMem/File`) : cette dernière ne libère jamais ses
/// tampons natifs (mesuré : ≈ 10 Mo perdus par appel avec un mp3 de 3 Mo, soit
/// plusieurs Go sur une bibliothèque). Ici tout est libéré.
///
/// Doit s'exécuter derrière [enqueueSoLoudFileTask]. Lève [AudioNotAnalyzable]
/// si le décodeur natif refuse le fichier.
Float32List readLeftChannelWindow(
  String path, {
  required int startSeconds,
  required int frames,
  required double endSeconds,
}) {
  final read = _openSoLoudLibrary()
      .lookupFunction<_ReadSamplesNative, _ReadSamples>('readSamplesFromFile');
  final cPath = path.toNativeUtf8();
  final samples = calloc<ffi.Float>(frames);
  try {
    final error = read(
      cPath,
      startSeconds.toDouble(),
      endSeconds,
      frames,
      false,
      samples,
    );
    if (error != 0) {
      throw AudioNotAnalyzable('décodeur natif refusé (code $error)');
    }
    return Float32List.fromList(samples.asTypedList(frames));
  } finally {
    calloc.free(samples);
    calloc.free(cPath);
  }
}
