import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/audio/loudness_analyzer.dart';

import '../autotag/audio_stream_info_test.dart' show wavBytes;
import '../autotag/native_libs.dart';

/// Sinusoïde de [seconds] secondes à [freq] Hz, amplitude [amp].
Float32List sine(
  double freq,
  double amp,
  int rate,
  double seconds, {
  double offset = 0,
}) {
  final n = (seconds * rate).round();
  return Float32List.fromList([
    for (var i = 0; i < n; i++)
      amp * math.sin(2 * math.pi * freq * (i + offset) / rate),
  ]);
}

double integratedLufs(Float32List pcm, int rate) =>
    loudnessLufs(kWeightedBlockEnergies(pcm, rate), momentaryMax: false)!;

void main() {
  group('pondération K (BS.1770)', () {
    // Une sinusoïde de 1 kHz d'amplitude a, mono, mesure
    // 10·log10(a²/2) + 0,69 LUFS (le −0,691 du standard compense le gain de la
    // pondération K vers 1 kHz).
    for (final rate in [44100, 48000, 22050]) {
      test('1 kHz à $rate Hz : sonie attendue à 0,15 LU près', () {
        final lufs = integratedLufs(sine(1000, 0.5, rate, 5), rate);
        expect(lufs, closeTo(-9.03 + 0.0, 0.15));
      });
    }

    test('les aigus pèsent plus que les médiums à énergie égale', () {
      final mid = integratedLufs(sine(1000, 0.3, 48000, 5), 48000);
      final high = integratedLufs(sine(10000, 0.3, 48000, 5), 48000);
      expect(high - mid, inInclusiveRange(2.5, 4.0));
    });

    test('les infra-graves sont presque sans poids', () {
      final mid = integratedLufs(sine(1000, 0.3, 48000, 5), 48000);
      final low = integratedLufs(sine(20, 0.3, 48000, 5), 48000);
      expect(mid - low, greaterThan(6));
    });
  });

  group('loudnessLufs', () {
    test('audio silencieux : null', () {
      final silent = Float32List(48000 * 3);
      final energies = kWeightedBlockEnergies(silent, 48000);
      expect(loudnessLufs(energies, momentaryMax: false), isNull);
      expect(loudnessLufs(energies, momentaryMax: true), isNull);
      expect(loudnessLufs(const [], momentaryMax: false), isNull);
    });

    test('un fichier plus court qu\'un bloc donne un bloc unique', () {
      final energies = kWeightedBlockEnergies(
        sine(1000, 0.5, 48000, 0.15),
        48000,
      );
      expect(energies, hasLength(1));
      expect(loudnessLufs(energies, momentaryMax: true), closeTo(-9.0, 0.5));
    });

    test('la porte relative ignore un passage très doux', () {
      final loud = sine(1000, 0.5, 48000, 6);
      final soft = sine(1000, 0.5 * 0.05, 48000, 6, offset: 6 * 48000);
      final both = Float32List.fromList([...loud, ...soft]);
      // Sans porte relative la moyenne tomberait de ≈ 3 LU ; avec, le passage à
      // −26 dB est écarté et la mesure reste celle du passage fort.
      expect(
        integratedLufs(both, 48000),
        closeTo(integratedLufs(loud, 48000), 0.5),
      );
    });

    test('un bruitage : le pic court terme, pas la moyenne sur la queue', () {
      // Impact de 200 ms suivi de 4 s de queue plus douce (≈ −9 dB) mais dans la
      // porte relative : la sonie intégrée dilue l'attaque dans la queue.
      final hit = sine(1000, 0.7, 48000, 0.2);
      final tail = sine(500, 0.25, 48000, 4, offset: 0.2 * 48000);
      final energies = kWeightedBlockEnergies(
        Float32List.fromList([...hit, ...tail]),
        48000,
      );
      final momentary = loudnessLufs(energies, momentaryMax: true)!;
      final integrated = loudnessLufs(energies, momentaryMax: false)!;
      expect(momentary, greaterThan(integrated + 4));
    });
  });

  group('autoVolumeForLoudness', () {
    test('atténue un son plus fort que la cible', () {
      expect(
        autoVolumeForLoudness(-14, LoudnessProfile.music),
        closeTo(math.pow(10, -6 / 20), 1e-9),
      );
    });

    test('ne dépasse jamais 1.0 pour un son doux', () {
      expect(autoVolumeForLoudness(-40, LoudnessProfile.music), 1.0);
    });

    test('respecte le plancher', () {
      expect(autoVolumeForLoudness(10, LoudnessProfile.music), kAutoVolumeMin);
    });

    test('l\'ambiance reste sous la musique, le bruitage au-dessus', () {
      const lufs = -12.0;
      final music = autoVolumeForLoudness(lufs, LoudnessProfile.music);
      expect(
        autoVolumeForLoudness(lufs, LoudnessProfile.ambiance),
        lessThan(music),
      );
      expect(
        autoVolumeForLoudness(lufs, LoudnessProfile.effect),
        greaterThan(music),
      );
    });
  });

  group('loudnessChunkStarts', () {
    test('fichier court : tout est lu, morceau par morceau', () {
      expect(loudnessChunkStarts(0.4), [0]);
      expect(loudnessChunkStarts(25), [0, 10, 20]);
    });

    test('fichier long : morceaux répartis de bout en bout', () {
      final starts = loudnessChunkStarts(600);
      expect(starts, hasLength(6));
      expect(starts.first, 0);
      expect(starts.last, 590);
      expect(starts, orderedEquals([...starts]..sort()));
    });
  });

  group('measureAutoVolume (décodeur natif)', () {
    final skip = soloudNativeSkipReason();
    late Directory tmp;
    setUpAll(() => tmp = Directory.systemTemp.createTempSync('loudness_'));
    tearDownAll(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    File wav(String name, Float32List pcm, int rate) {
      final samples = [for (final v in pcm) (v * 32767).round()];
      return File(p.join(tmp.path, name))
        ..writeAsBytesSync(wavBytes(sampleRate: rate, left: samples));
    }

    test(
      'mesure un fichier lu pour de vrai, et applique la cible du type',
      () async {
        // 1 kHz à 0,5 : ≈ −9 LUFS, donc 11 LU au-dessus de la cible musique.
        final file = wav('tone.wav', sine(1000, 0.5, 44100, 12), 44100);
        final volume = await measureAutoVolume(file, LoudnessProfile.music);
        expect(volume, isNotNull);
        expect(volume!, closeTo(math.pow(10, (-20 + 9.03) / 20), 0.02));

        final ambiance = await measureAutoVolume(
          file,
          LoudnessProfile.ambiance,
        );
        expect(ambiance!, lessThan(volume));
      },
      skip: skip,
    );

    test('un clic de 60 ms est mesurable', () async {
      final file = wav('click.wav', sine(1000, 0.8, 44100, 0.06), 44100);
      final volume = await measureAutoVolume(file, LoudnessProfile.effect);
      expect(volume, isNotNull);
      expect(volume!, lessThan(1.0));
    }, skip: skip);

    test('un fichier silencieux ou illisible donne null', () async {
      final silent = wav('silent.wav', Float32List(44100 * 2), 44100);
      expect(await measureAutoVolume(silent, LoudnessProfile.music), isNull);
      final junk = File(p.join(tmp.path, 'junk.wav'))
        ..writeAsBytesSync(List.filled(64, 7));
      expect(await measureAutoVolume(junk, LoudnessProfile.music), isNull);
    }, skip: skip);
  });
}
