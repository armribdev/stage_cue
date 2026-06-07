import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/audio/audio_file_validation.dart';

void main() {
  group('isPlausibleAudioFile', () {
    test('rejette un stub ID3 de 4 octets', () async {
      final stub = File(
        '${Directory.systemTemp.path}/stub-id3-${DateTime.now().millisecondsSinceEpoch}.mp3',
      );
      await stub.writeAsBytes([0x49, 0x44, 0x33, 0x04]);

      try {
        expect(await isPlausibleAudioFile(stub), isFalse);
      } finally {
        if (await stub.exists()) await stub.delete();
      }
    });

    test('rejette un fichier HTML', () async {
      final fake = File(
        '${Directory.systemTemp.path}/fake-html-${DateTime.now().millisecondsSinceEpoch}.mp3',
      );
      final content = List<int>.filled(kMinimumValidAudioFileBytes + 8, 0x20);
      content.setAll(0, '<!DOCTYPE html>'.codeUnits);
      await fake.writeAsBytes(content);

      try {
        expect(await isPlausibleAudioFile(fake), isFalse);
      } finally {
        if (await fake.exists()) await fake.delete();
      }
    });
  });
}
