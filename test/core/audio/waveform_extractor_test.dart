import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/audio/waveform_extractor.dart';

void main() {
  group('WaveformProbe.generationValue', () {
    test('un succès porte la génération courante', () {
      final probe = WaveformProbe.success(Uint8List.fromList([1, 2, 3]));
      expect(probe.generationValue, kWaveformProbeGeneration);
    });

    test('un échec « format » porte la génération courante', () {
      expect(
        const WaveformProbe.unsupported().generationValue,
        kWaveformProbeGeneration,
      );
    });

    test('un échec transitoire ne marque rien (on retentera)', () {
      expect(const WaveformProbe.transient().generationValue, isNull);
    });
  });

  group('waveformNeedsProbe', () {
    test('jamais analysé ou enveloppe héritée (null) → à sonder', () {
      expect(waveformNeedsProbe(null), isTrue);
    });

    test('génération antérieure → à re-sonder', () {
      expect(waveformNeedsProbe(kWaveformProbeGeneration - 1), isTrue);
    });

    test('génération courante → rien à refaire', () {
      expect(waveformNeedsProbe(kWaveformProbeGeneration), isFalse);
    });
  });
}
