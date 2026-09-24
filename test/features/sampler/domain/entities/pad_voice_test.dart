import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/features/sampler/domain/entities/pad.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';

Sound _sound(int id, SoundType? type) => Sound(
      id: id,
      title: 'Son $id',
      filePath: '/tmp/son_$id.mp3',
      type: type,
      volume: 1.0,
      createdAt: DateTime(2026),
    );

Pad _pad(List<Sound> sounds) => Pad(
      id: 1,
      boardId: 1,
      sortOrder: 0,
      createdAt: DateTime(2026),
      sounds: sounds,
    );

void main() {
  group('Pad — voies exclusives', () {
    test('pad vide : ni musique ni ambiance', () {
      final pad = _pad(const []);
      expect(pad.isMusicPad, isFalse);
      expect(pad.isAmbiancePad, isFalse);
      expect(pad.isExclusiveVoicePad, isFalse);
    });

    test('pad 100 % ambiance : voie ambiance', () {
      final pad = _pad([
        _sound(1, SoundType.ambiance),
        _sound(2, SoundType.ambiance),
      ]);
      expect(pad.isAmbiancePad, isTrue);
      expect(pad.isMusicPad, isFalse);
      expect(pad.isExclusiveVoicePad, isTrue);
    });

    test('pad mixte ambiance + bruitage : pad normal (polyphonie)', () {
      final pad = _pad([
        _sound(1, SoundType.ambiance),
        _sound(2, SoundType.soundEffect),
      ]);
      expect(pad.isAmbiancePad, isFalse);
      expect(pad.isExclusiveVoicePad, isFalse);
    });

    test('pad mixte ambiance + musique : pad normal', () {
      final pad = _pad([
        _sound(1, SoundType.ambiance),
        _sound(2, SoundType.music),
      ]);
      expect(pad.isAmbiancePad, isFalse);
      expect(pad.isMusicPad, isFalse);
      expect(pad.isExclusiveVoicePad, isFalse);
    });

    test('son non classé (type null) : pad normal', () {
      final pad = _pad([_sound(1, null)]);
      expect(pad.isAmbiancePad, isFalse);
      expect(pad.isExclusiveVoicePad, isFalse);
    });
  });
}
