import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/autotag/muq_analyzer.dart';
import 'package:stage_cue/core/autotag/onnx_session.dart';
import 'package:stage_cue/core/autotag/pcm_decoder.dart';

import 'native_libs.dart';

/// Ces tests exigent le modèle MuQ int8 (≈ 480 Mo, jamais versionné) et les
/// fichiers de référence produits par `tool/autotag/` :
///
///   STAGE_CUE_MUQ_DIR=<dossier contenant muq_audio_int8.onnx, ref_pcm.f32,
///                      ref_latent_int8.f32, val_plan.json>
///
/// `val_plan.json` (plan de validation, chemins de la bibliothèque de l'auteur)
/// est facultatif : sans lui, seul le test de parité sur un clip s'exécute.
final String? _dir = Platform.environment['STAGE_CUE_MUQ_DIR'];

Float32List _readF32(String path) {
  final b = File(path).readAsBytesSync();
  return Float32List.sublistView(b);
}

double _cosine(List<double> a, List<double> b) {
  var d = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    d += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return d / math.sqrt(na * nb);
}

void main() {
  final lib = onnxRuntimeLibraryPath();
  final String? skip = _dir == null
      ? 'STAGE_CUE_MUQ_DIR non défini (modèle MuQ absent)'
      : lib == null
      ? 'ONNX Runtime introuvable : lancer `flutter build windows --debug` une fois'
      : soloudNativeSkipReason();

  MuqAnalyzer? analyzer;
  setUpAll(() async {
    if (skip != null) return;
    analyzer = await MuqAnalyzer.start(
      p.join(_dir!, 'muq_audio_int8.onnx'),
      libraryPath: lib,
    );
  });
  tearDownAll(() async => analyzer?.dispose());

  test('parité avec la référence Python sur un même clip PCM', () async {
    final pcm = _readF32(p.join(_dir!, 'ref_pcm.f32'));
    final ref = _readF32(p.join(_dir!, 'ref_latent_int8.f32'));
    final sw = Stopwatch()..start();
    final latent = await analyzer!.embed([pcm]);
    // ignore: avoid_print
    print('un clip de 10 s : ${sw.elapsedMilliseconds} ms');
    expect(latent.length, kMuqLatentSize);
    expect(_cosine(latent, ref), greaterThan(0.9999));
  }, skip: skip);

  test('moyenne de plusieurs clips = moyenne des latents', () async {
    final pcm = _readF32(p.join(_dir!, 'ref_pcm.f32'));
    final one = await analyzer!.embed([pcm]);
    final three = await analyzer!.embed([pcm, pcm, pcm]);
    for (var i = 0; i < kMuqLatentSize; i++) {
      expect(three[i], closeTo(one[i], 1e-5));
    }
  }, skip: skip);

  test('l\'inférence ne gèle pas le thread Dart', () async {
    // Via le canal de plateforme de flutter_onnxruntime, le thread Dart était
    // gelé ~410 ms par clip : ici l'appel natif vit dans un isolate de travail.
    final pcm = _readF32(p.join(_dir!, 'ref_pcm.f32'));
    var last = DateTime.now().microsecondsSinceEpoch;
    var maxGap = 0;
    final ticker = Timer.periodic(const Duration(milliseconds: 8), (_) {
      final now = DateTime.now().microsecondsSinceEpoch;
      maxGap = math.max(maxGap, now - last);
      last = now;
    });
    await analyzer!.embed([pcm, pcm, pcm]);
    ticker.cancel();
    // ignore: avoid_print
    print(
      'écart max entre ticks de 8 ms pendant 3 clips : ${maxGap / 1000} ms',
    );
    expect(maxGap, lessThan(100000));
  }, skip: skip);

  test('un modèle absent lève OnnxRuntimeException', () async {
    await expectLater(
      MuqAnalyzer.start(p.join(_dir!, 'absent.onnx'), libraryPath: lib),
      throwsA(isA<OnnxRuntimeException>()),
    );
  }, skip: skip);

  // Validation de bout en bout (décodeur + rééchantillonneur + modèle) contre
  // la référence Python mono/soxr, sur la bibliothèque réelle de l'auteur.
  // Mesures du spike (ADR 0029) : cosinus latent 0,957 ; n°1 identique 92 % ;
  // n°1 dans le top-3 de la référence 100 % ; recouvrement du top-3 91 %.
  test(
    'validation sur la bibliothèque (plan Python)',
    () async {
      final planFile = File(p.join(_dir!, 'val_plan.json'));
      if (!planFile.existsSync()) {
        markTestSkipped('val_plan.json absent');
        return;
      }
      final plan = (jsonDecode(planFile.readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();
      final text = _readF32(_textLatentsPath());
      List<double> scores(List<double> latent) => [
        for (var m = 0; m < 15; m++)
          () {
            var s = 0.0;
            for (var i = 0; i < kMuqLatentSize; i++) {
              s += text[m * kMuqLatentSize + i] * latent[i];
            }
            return s;
          }(),
      ];

      final dart = <List<double>>[];
      final ref = <List<double>>[];
      final cos = <double>[];
      var decodeMs = 0;
      for (final t in plan) {
        final file = File(t['file'] as String);
        if (!file.existsSync()) continue;
        try {
          final sw = Stopwatch()..start();
          final clips = await decodeAnalysisClips(file);
          decodeMs += sw.elapsedMilliseconds;
          final latent = await analyzer!.embed(clips);
          final mono = (t['mono'] as List).cast<List>();
          final refMean = List<double>.filled(kMuqLatentSize, 0);
          for (final c in mono) {
            for (var i = 0; i < kMuqLatentSize; i++) {
              refMean[i] += (c[i] as num) / mono.length;
            }
          }
          dart.add(latent.toList());
          ref.add(refMean);
          cos.add(_cosine(latent, refMean));
        } on Object catch (e) {
          // ignore: avoid_print
          print('! ${p.basename(file.path)} : $e');
        }
      }
      expect(dart.length, greaterThan(10), reason: 'pistes comparées');

      List<List<double>> centred(List<List<double>> latents) {
        final s = [for (final l in latents) scores(l)];
        final mean = [
          for (var m = 0; m < 15; m++)
            s.map((r) => r[m]).reduce((a, b) => a + b) / s.length,
        ];
        return [
          for (final r in s) [for (var m = 0; m < 15; m++) r[m] - mean[m]],
        ];
      }

      List<int> top(List<double> v, int k) => (List<int>.generate(
        v.length,
        (i) => i,
      )..sort((a, b) => v[b].compareTo(v[a]))).take(k).toList();

      final sd = centred(dart), sr = centred(ref);
      var same1 = 0, in3 = 0;
      var overlap = 0.0;
      for (var i = 0; i < sd.length; i++) {
        final a = top(sd[i], 3), b = top(sr[i], 3);
        if (a.first == b.first) same1++;
        if (b.contains(a.first)) in3++;
        overlap += a.where(b.contains).length / 3;
      }
      final n = sd.length;
      final meanCos = cos.reduce((a, b) => a + b) / n;
      // ignore: avoid_print
      print(
        '$n pistes | cosinus moyen ${meanCos.toStringAsFixed(3)} '
        '(min ${cos.reduce(math.min).toStringAsFixed(3)}) | n°1 identique '
        '${(100 * same1 / n).round()} % | n°1 dans top-3 réf ${(100 * in3 / n).round()} % '
        '| recouvrement top-3 ${(100 * overlap / n).round()} % '
        '| décodage ${decodeMs ~/ n} ms/piste',
      );
      expect(meanCos, greaterThan(0.94));
      expect(same1 / n, greaterThan(0.8));
      expect(in3 / n, greaterThan(0.93));
      expect(overlap / n, greaterThan(0.8));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

String _textLatentsPath() => 'tool/autotag/text_latents.f32';
