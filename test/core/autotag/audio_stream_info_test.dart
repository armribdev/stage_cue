import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/autotag/audio_stream_info.dart';

const _fixtures = 'test/fixtures/autotag';

/// WAV PCM 16 bits entrelacé, généré en mémoire : `left[i]` / `right[i]` en
/// échelle 16 bits (right = null → mono).
Uint8List wavBytes({
  required int sampleRate,
  required List<int> left,
  List<int>? right,
  int? declaredDataBytes,
}) {
  final channels = right == null ? 1 : 2;
  final dataBytes = left.length * channels * 2;
  final b = BytesBuilder();
  void u32(int v) =>
      b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u16(int v) =>
      b.add((ByteData(2)..setInt16(0, v, Endian.little)).buffer.asUint8List());
  b.add('RIFF'.codeUnits);
  u32(36 + dataBytes);
  b.add('WAVEfmt '.codeUnits);
  u32(16);
  u16(1);
  u16(channels);
  u32(sampleRate);
  u32(sampleRate * channels * 2);
  u16(channels * 2);
  u16(16);
  b.add('data'.codeUnits);
  u32(declaredDataBytes ?? dataBytes);
  for (var i = 0; i < left.length; i++) {
    u16(left[i]);
    if (right != null) u16(right[i]);
  }
  return b.toBytes();
}

void main() {
  late Directory tmp;
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('stream_info_'));
  tearDownAll(() => tmp.deleteSync(recursive: true));

  Future<AudioStreamInfo> probeFixture(String name) =>
      probeAudioStreamInfo(File(p.join(_fixtures, name)));

  group('probeAudioStreamInfo', () {
    test('mp3 stéréo 44,1 kHz (en-tête Xing/Info)', () async {
      final i = await probeFixture('stereo_44100.mp3');
      expect(i.sampleRate, 44100);
      expect(i.durationSeconds, closeTo(3, 0.1));
    });

    test('mp3 mono 32 kHz', () async {
      final i = await probeFixture('mono_32000.mp3');
      expect(i.sampleRate, 32000);
      expect(i.durationSeconds, closeTo(3, 0.1));
    });

    test('flac stéréo 48 kHz', () async {
      final i = await probeFixture('stereo_48000.flac');
      expect(i.sampleRate, 48000);
      expect(i.durationSeconds, closeTo(2, 0.01));
    });

    test('flac mono 16 kHz', () async {
      final i = await probeFixture('mono_16000.flac');
      expect(i.sampleRate, 16000);
      expect(i.durationSeconds, closeTo(2, 0.01));
    });

    test('ogg vorbis 22,05 kHz', () async {
      final i = await probeFixture('stereo_22050.ogg');
      expect(i.sampleRate, 22050);
      expect(i.durationSeconds, closeTo(3, 0.1));
    });

    test(
      'wav : fréquence et durée, y compris taille de données absurde',
      () async {
        final samples = List<int>.filled(8000, 0);
        final f = File(p.join(tmp.path, 'a.wav'))
          ..writeAsBytesSync(wavBytes(sampleRate: 8000, left: samples));
        final i = await probeAudioStreamInfo(f);
        expect(i.sampleRate, 8000);
        expect(i.durationSeconds, closeTo(1, 1e-9));

        final streamed = File(p.join(tmp.path, 'b.wav'))
          ..writeAsBytesSync(
            wavBytes(
              sampleRate: 8000,
              left: samples,
              declaredDataBytes: 0xFFFFFFFF,
            ),
          );
        expect(
          (await probeAudioStreamInfo(streamed)).durationSeconds,
          closeTo(1, 1e-9),
        );
      },
    );

    test('mp3 précédé d\'une étiquette ID3v2 volumineuse', () async {
      final mp3 = File(p.join(_fixtures, 'stereo_44100.mp3')).readAsBytesSync();
      const tagBody = 5000;
      final id3 = Uint8List(10 + tagBody)
        ..setAll(0, 'ID3'.codeUnits)
        ..[3] = 4
        ..[6] = (tagBody >> 21) & 0x7F
        ..[7] = (tagBody >> 14) & 0x7F
        ..[8] = (tagBody >> 7) & 0x7F
        ..[9] = tagBody & 0x7F;
      final f = File(p.join(tmp.path, 'tagged.mp3'))
        ..writeAsBytesSync([...id3, ...mp3]);
      final i = await probeAudioStreamInfo(f);
      expect(i.sampleRate, 44100);
      expect(i.durationSeconds, closeTo(3, 0.1));
    });

    test('opus : refusé avec une raison', () async {
      await expectLater(
        probeFixture('stereo_48000.opus'),
        throwsA(
          isA<AudioNotAnalyzable>().having(
            (e) => e.reason,
            'reason',
            contains('opus'),
          ),
        ),
      );
    });

    test('contenu inconnu ou tronqué : refusé', () async {
      final junk = File(p.join(tmp.path, 'junk.mp3'))
        ..writeAsBytesSync(Uint8List.fromList(List.filled(4096, 7)));
      await expectLater(
        probeAudioStreamInfo(junk),
        throwsA(isA<AudioNotAnalyzable>()),
      );
      final tiny = File(p.join(tmp.path, 'tiny.flac'))
        ..writeAsBytesSync('fLaC'.codeUnits);
      await expectLater(
        probeAudioStreamInfo(tiny),
        throwsA(isA<AudioNotAnalyzable>()),
      );
    });
  });
}
