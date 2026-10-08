import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/audio/loudness_analyzer.dart';

void main() {
  group('rmsOfWindows', () {
    test('ignore les fenêtres de silence', () {
      final rms = rmsOfWindows(Float32List.fromList([0.0, 0.0, 0.2, 0.2]));
      expect(rms, closeTo(0.2, 1e-6));
    });

    test('renvoie null pour un audio entièrement silencieux', () {
      expect(rmsOfWindows(Float32List.fromList([0.0, 0.001])), isNull);
      expect(rmsOfWindows(Float32List(0)), isNull);
    });

    test('racine de la moyenne des carrés', () {
      final rms = rmsOfWindows(Float32List.fromList([0.1, 0.3]));
      expect(rms, closeTo(0.2236, 1e-3));
    });
  });

  group('autoVolumeForRms', () {
    test('atténue un son plus fort que la cible', () {
      expect(autoVolumeForRms(0.2), closeTo(0.5, 1e-9));
    });

    test('ne dépasse jamais 1.0 pour un son doux', () {
      expect(autoVolumeForRms(0.02), 1.0);
    });

    test('respecte le plancher', () {
      expect(autoVolumeForRms(5.0), kAutoVolumeMin);
    });
  });
}
