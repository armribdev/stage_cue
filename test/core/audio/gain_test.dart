// Conversion dB ↔ facteur du gain d'un son (décision 0045) et son affichage.

import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/audio/gain.dart';
import 'package:stage_cue/features/sampler/presentation/widgets/sound_gain_field.dart';

void main() {
  test(
    '0 dB est le fichier tel quel, +12 dB environ ×4, −24 dB environ ×1/16',
    () {
      expect(dbToGain(0), 1.0);
      expect(dbToGain(kGainMaxDb), closeTo(3.981, 0.001));
      expect(dbToGain(kGainMinDb), closeTo(0.0631, 0.0001));
    },
  );

  test('gainToDb est l\'inverse de dbToGain dans la plage du curseur', () {
    for (final db in [-24.0, -6.0, 0.0, 3.5, 12.0]) {
      expect(gainToDb(dbToGain(db)), closeTo(db, 1e-9));
    }
  });

  test('un gain hors plage ou muet s\'affiche à la borne la plus proche', () {
    expect(gainToDb(0), kGainMinDb, reason: 'son muet');
    expect(gainToDb(0.001), kGainMinDb);
    expect(gainToDb(100), kGainMaxDb);
  });

  test('formatGainDb : signe explicite, virgule, 0 dB sans décimale', () {
    expect(formatGainDb(0), '0 dB');
    expect(formatGainDb(0.04), '0 dB');
    expect(formatGainDb(3.5), '+3,5 dB');
    expect(formatGainDb(-6), '−6,0 dB');
    expect(formatGainDb(12), '+12,0 dB');
  });
}
