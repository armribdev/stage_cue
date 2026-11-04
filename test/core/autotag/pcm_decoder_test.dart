import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/autotag/audio_stream_info.dart';
import 'package:stage_cue/core/autotag/pcm_decoder.dart';

import 'audio_stream_info_test.dart' show wavBytes;
import 'native_soloud.dart';

const _fixtures = 'test/fixtures/autotag';

/// Corrélation de [x] avec une sinusoïde de fréquence [freq] (rendue à [rate]),
/// maximisée sur la phase et normalisée entre 0 et 1.
double toneCorrelation(Float32List x, double freq, int rate) {
  var c = 0.0, s = 0.0, e = 0.0;
  for (var i = 0; i < x.length; i++) {
    final a = 2 * math.pi * freq * i / rate;
    c += x[i] * math.cos(a);
    s += x[i] * math.sin(a);
    e += x[i] * x[i];
  }
  if (e == 0) return 0;
  return math.sqrt(c * c + s * s) * math.sqrt(2 / x.length) / math.sqrt(e);
}

void main() {
  final skip = soloudNativeSkipReason();
  late Directory tmp;
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('pcm_decoder_'));
  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ── Garde-fou ADR 0029 ────────────────────────────────────────────────────
  // `readSamplesFromFile` n'est pas un décodeur PCM : on le détourne. Si une
  // mise à jour de flutter_soloud change l'un de ces comportements, ces tests
  // doivent échouer AVANT que l'analyse ne produise des tags sur du bruit.
  group('contrat natif de readSamplesFromFile (détourné)', () {
    test('canal gauche seul, exact, à la fréquence native', () {
      // Gauche = rampe i, droite = autre rampe : toute confusion de canal, de
      // fréquence, de décalage ou de moyenne se voit au bit près.
      const rate = 8000;
      final left = [for (var i = 0; i < 2 * rate; i++) i];
      final right = [for (var i = 0; i < 2 * rate; i++) 30000 - (i % 20000)];
      final f = File(
        p.join(tmp.path, 'ramp.wav'),
      )..writeAsBytesSync(wavBytes(sampleRate: rate, left: left, right: right));

      final out = readLeftChannelWindow(
        f.path,
        startSeconds: 1,
        frames: rate,
        endSeconds: 2.05,
      );

      expect(out.length, rate);
      for (var i = 0; i < rate; i++) {
        expect(out[i], (rate + i) / 32768.0, reason: 'trame $i');
      }
    }, skip: skip);

    test('pistes mono : le seul canal', () {
      const rate = 16000;
      final left = [for (var i = 0; i < 2 * rate; i++) (i * 7) % 20000];
      final f = File(p.join(tmp.path, 'mono.wav'))
        ..writeAsBytesSync(wavBytes(sampleRate: rate, left: left));
      final out = readLeftChannelWindow(
        f.path,
        startSeconds: 0,
        frames: rate,
        endSeconds: 1.05,
      );
      for (var i = 0; i < rate; i += 97) {
        expect(out[i], left[i] / 32768.0, reason: 'trame $i');
      }
    }, skip: skip);

    // Formats compressés : on compare au contenu (gauche = 440 Hz, droite =
    // 880 Hz) et à la fréquence native (la corrélation n'est maximale qu'à la
    // bonne fréquence d'échantillonnage).
    for (final c in [
      ('stereo_44100.mp3', 44100),
      ('stereo_48000.flac', 48000),
      ('stereo_22050.ogg', 22050),
    ]) {
      test('${c.$1} : gauche 440 Hz à ${c.$2} Hz', () {
        final out = readLeftChannelWindow(
          p.join(_fixtures, c.$1),
          startSeconds: 0,
          frames: c.$2,
          endSeconds: 1.05,
        );
        expect(out.length, c.$2);
        expect(toneCorrelation(out, 440, c.$2), greaterThan(0.99));
        expect(toneCorrelation(out, 880, c.$2), lessThan(0.05));
      }, skip: skip);
    }

    for (final c in [('mono_32000.mp3', 32000), ('mono_16000.flac', 16000)]) {
      test('${c.$1} (mono) : 440 Hz à ${c.$2} Hz', () {
        final out = readLeftChannelWindow(
          p.join(_fixtures, c.$1),
          startSeconds: 0,
          frames: c.$2,
          endSeconds: 1.05,
        );
        expect(toneCorrelation(out, 440, c.$2), greaterThan(0.99));
      }, skip: skip);
    }

    test('fichier non audio : AudioNotAnalyzable', () {
      final f = File(p.join(tmp.path, 'junk.mp3'))
        ..writeAsBytesSync(Uint8List.fromList(List.filled(4096, 1)));
      expect(
        () => readLeftChannelWindow(
          f.path,
          startSeconds: 0,
          frames: 1000,
          endSeconds: 1,
        ),
        throwsA(isA<AudioNotAnalyzable>()),
      );
    }, skip: skip);
  });

  group('decodeAnalysisClips', () {
    for (final c in [
      'stereo_44100.mp3',
      'stereo_48000.flac',
      'stereo_22050.ogg',
      'mono_32000.mp3',
      'mono_16000.flac',
    ]) {
      test('$c → clips mono 24 kHz du canal gauche', () async {
        final clips = await decodeAnalysisClips(
          File(p.join(_fixtures, c)),
          clipSeconds: 1,
        );
        expect(clips, isNotEmpty);
        for (final clip in clips) {
          expect(clip.length, kAnalysisSampleRate);
          expect(
            toneCorrelation(clip, 440, kAnalysisSampleRate),
            greaterThan(0.99),
          );
          expect(
            toneCorrelation(clip, 880, kAnalysisSampleRate),
            lessThan(0.05),
          );
        }
      }, skip: skip);
    }

    test('wav 44,1 kHz : ton conservé après rééchantillonnage', () async {
      const rate = 44100;
      final left = [
        for (var i = 0; i < 4 * rate; i++)
          (10000 * math.sin(2 * math.pi * 1000 * i / rate)).round(),
      ];
      final f = File(p.join(tmp.path, 'tone.wav'))
        ..writeAsBytesSync(wavBytes(sampleRate: rate, left: left, right: left));
      final clips = await decodeAnalysisClips(f, clipSeconds: 1);
      expect(clips.length, greaterThanOrEqualTo(2));
      for (final c in clips) {
        expect(
          toneCorrelation(c, 1000, kAnalysisSampleRate),
          greaterThan(0.999),
        );
      }
    }, skip: skip);

    test('morceau trop court : refusé avec une raison', () async {
      await expectLater(
        decodeAnalysisClips(File(p.join(_fixtures, 'stereo_44100.mp3'))),
        throwsA(
          isA<AudioNotAnalyzable>().having(
            (e) => e.reason,
            'reason',
            contains('court'),
          ),
        ),
      );
    });

    test('silence numérique : refusé', () async {
      final f = File(p.join(tmp.path, 'silence.wav'))
        ..writeAsBytesSync(
          wavBytes(sampleRate: 8000, left: List.filled(8000 * 4, 0)),
        );
      await expectLater(
        decodeAnalysisClips(f, clipSeconds: 1),
        throwsA(isA<AudioNotAnalyzable>()),
      );
    }, skip: skip);
  });

  group('clipStartSeconds', () {
    test('15 / 45 / 75 % d\'un morceau de 4 minutes', () {
      expect(clipStartSeconds(240), [36, 108, 180]);
    });

    test('les clips restent dans le morceau et ne sont pas dupliqués', () {
      final s = clipStartSeconds(14);
      expect(s, [2, 3]);
      expect(s.last + kClipSeconds, lessThanOrEqualTo(14));
    });

    test('morceau trop court', () {
      expect(() => clipStartSeconds(10.5), throwsA(isA<AudioNotAnalyzable>()));
    });
  });

  group('isUsableClip', () {
    test('dernière seconde nulle → inutilisable', () {
      final clip = Float32List(48000)..[100] = 0.5;
      expect(isUsableClip(clip, 24000), isFalse);
      clip[47999] = 0.01;
      expect(isUsableClip(clip, 24000), isTrue);
    });
  });
}
