import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/autotag/pcm_resampler.dart';

Float32List sine(double freq, int rate, int frames) => Float32List.fromList([
  for (var i = 0; i < frames; i++)
    0.5 * math.sin(2 * math.pi * freq * i / rate),
]);

double rms(Float32List x, {int skip = 0}) {
  var s = 0.0;
  for (var i = skip; i < x.length - skip; i++) {
    s += x[i] * x[i];
  }
  return math.sqrt(s / (x.length - 2 * skip));
}

void main() {
  group('resamplePcm', () {
    for (final rate in [8000, 16000, 22050, 32000, 44100, 48000]) {
      test('sinus 1 kHz conservé à $rate → 24000 Hz', () {
        final input = sine(1000, rate, rate * 2);
        final out = resamplePcm(input, rate, 24000);
        expect(out.length, 48000);
        final ref = sine(1000, 24000, 48000);
        // Hors bords (filtre de 96 coefficients) : forme et amplitude idéales.
        var err = 0.0;
        for (var i = 200; i < out.length - 200; i++) {
          err = math.max(err, (out[i] - ref[i]).abs());
        }
        expect(err, lessThan(2e-3), reason: 'écart max à la sinusoïde idéale');
      });
    }

    test('même fréquence : copie', () {
      final input = sine(440, 24000, 1000);
      final out = resamplePcm(input, 24000, 24000);
      expect(out, orderedEquals(input));
      expect(identical(out, input), isFalse);
    });

    test('un son au-dessus de la bande de sortie est éliminé', () {
      // 18 kHz à 44,1 kHz : au-delà de 12 kHz (Nyquist de sortie). Un mauvais
      // filtre le replierait à 6 kHz.
      final out = resamplePcm(sine(18000, 44100, 44100), 44100, 24000);
      expect(rms(out, skip: 200), lessThan(0.5 * 0.7071 * 0.01));
    });

    test('fréquences invalides', () {
      expect(() => resamplePcm(Float32List(10), 0, 24000), throwsArgumentError);
    });
  });
}
