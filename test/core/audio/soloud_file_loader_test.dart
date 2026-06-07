import 'dart:io';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/audio/soloud_file_loader.dart';

void main() {
  group('isBenignSoLoudLoadSideEffect', () {
    test('identifie les erreurs de chargement SoLoud', () {
      expect(
        isBenignSoLoudLoadSideEffect(const SoLoudFileNotFoundException()),
        isTrue,
      );
      expect(
        isBenignSoLoudLoadSideEffect(const SoLoudFileLoadFailedException()),
        isTrue,
      );
      expect(isBenignSoLoudLoadSideEffect(StateError('autre')), isFalse);
    });
  });

  group('loadAudioSourceFromFile', () {
    test('rejette un fichier absent', () async {
      final missing = File('${Directory.systemTemp.path}/missing-audio-test.mp3');
      if (await missing.exists()) {
        await missing.delete();
      }

      expect(
        () => loadAudioSourceFromFile(missing),
        throwsA(isA<StateError>()),
      );
    });

    test('rejette un fichier vide', () async {
      final empty = File(
        '${Directory.systemTemp.path}/empty-audio-test-${DateTime.now().millisecondsSinceEpoch}.mp3',
      );
      await empty.writeAsBytes(const <int>[]);

      try {
        expect(
          () => loadAudioSourceFromFile(empty),
          throwsA(isA<StateError>()),
        );
      } finally {
        if (await empty.exists()) {
          await empty.delete();
        }
      }
    });
  });
}
