import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stage_cue/features/sampler/domain/entities/pad.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';
import 'package:stage_cue/features/sampler/domain/usecases/load_sounds_usecase.dart';
import 'package:stage_cue/features/sampler/data/repositories/sound_repository.dart';
import 'package:stage_cue/features/sampler/presentation/providers/sampler_provider.dart';

// ignore: subtype_of_sealed_class
class MockSoundRepository extends Mock implements SoundRepository {}

class MockLoadSoundsUseCase extends Mock implements LoadSoundsUseCase {}

Pad _pad(int id) => Pad(
      id: id,
      boardId: 1,
      sortOrder: id,
      createdAt: DateTime(2026),
    );

Sound _sound(int id, {SoundType type = SoundType.ambiance}) => Sound(
      id: id,
      title: 'Son $id',
      filePath: '/tmp/son_$id.mp3',
      type: type,
      volume: 1.0,
      createdAt: DateTime(2026),
    );

SamplerNotifier _notifier({Map<int, Sound> soundsById = const {}}) {
  final repo = MockSoundRepository();
  final useCase = MockLoadSoundsUseCase();
  when(() => repo.getSoundById(any())).thenAnswer(
    (invocation) async => soundsById[invocation.positionalArguments[0]],
  );
  when(() => useCase.call(any())).thenAnswer((_) async => []);
  return SamplerNotifier(repo, useCase);
}

void main() {
  setUpAll(() {
    registerFallbackValue(_pad(0));
    registerFallbackValue(_sound(0));
  });

  // ── Volume de voie ────────────────────────────────────────────────────────

  group('setAmbianceVolume', () {
    test('met à jour ambianceVolume sans toucher au volume musique', () async {
      final n = _notifier();
      expect(n.ambianceVolume, 1.0);

      await n.setAmbianceVolume(0.4);
      expect(n.ambianceVolume, 0.4);
      expect(n.musicVolume, 1.0);
    });

    test('clamp à [0, 1]', () async {
      final n = _notifier();

      await n.setAmbianceVolume(1.5);
      expect(n.ambianceVolume, 1.0);

      await n.setAmbianceVolume(-0.2);
      expect(n.ambianceVolume, 0.0);
    });

    test('émet une notification, idempotent si valeur identique', () async {
      final n = _notifier();
      var count = 0;
      n.addListener(() => count++);

      await n.setAmbianceVolume(0.5);
      expect(count, 1);

      await n.setAmbianceVolume(0.5);
      expect(count, 1);
    });
  });

  group('toggleAmbianceMute', () {
    test('coupe puis restaure le volume', () async {
      final n = _notifier();
      await n.setAmbianceVolume(0.6);

      await n.toggleAmbianceMute();
      expect(n.ambianceVolume, 0.0);

      await n.toggleAmbianceMute();
      expect(n.ambianceVolume, 0.6);
    });
  });

  // ── Antenne ───────────────────────────────────────────────────────────────

  group('stopCurrentAmbiance', () {
    test('sans ambiance à l\'antenne : no-op silencieux', () async {
      final n = _notifier();
      var count = 0;
      n.addListener(() => count++);

      await n.stopCurrentAmbiance();

      expect(n.state.currentAmbiancePad, isNull);
      expect(count, 0);
    });
  });

  group('playAmbianceBySoundId', () {
    test('son inconnu : échec signalé, rien à l\'antenne', () async {
      final n = _notifier();

      final padItem = await n.playAmbianceBySoundId(99);

      expect(padItem, isNull);
      expect(n.state.currentAmbiancePad, isNull);
      expect(n.consumeLastMusicPlaybackError(), isNotNull);
    });

    test('son musique : refusé, la voie ambiance reste vide', () async {
      final n = _notifier(
        soundsById: {1: _sound(1, type: SoundType.music)},
      );

      final padItem = await n.playAmbianceBySoundId(1);

      expect(padItem, isNull);
      expect(n.state.currentAmbiancePad, isNull);
      expect(n.state.currentMusicPad, isNull);
      expect(n.consumeLastMusicPlaybackError(), contains('ambiance'));
    });
  });

  group('stopAllSounds', () {
    test('sans rien à l\'antenne : laisse la voie ambiance vide', () async {
      final n = _notifier();
      await n.stopAllSounds();
      expect(n.state.currentAmbiancePad, isNull);
    });
  });

  // ── État ──────────────────────────────────────────────────────────────────

  group('SamplerState.copyWith — currentAmbiancePad', () {
    test('conservé par défaut, effacé par clearCurrentAmbiancePad', () {
      final item = PadItem(pad: _pad(5));
      final state = SamplerState(pads: const [], currentAmbiancePad: item);

      expect(state.copyWith(isLoading: true).currentAmbiancePad, same(item));
      expect(
        state.copyWith(clearCurrentAmbiancePad: true).currentAmbiancePad,
        isNull,
      );
    });

    test('indépendant de la musique à l\'antenne', () {
      final ambiance = PadItem(pad: _pad(5));
      final music = PadItem(pad: _pad(6));
      final state = SamplerState(
        pads: const [],
        currentAmbiancePad: ambiance,
        currentMusicPad: music,
      );

      final cleared = state.copyWith(clearCurrentMusicPad: true);
      expect(cleared.currentMusicPad, isNull);
      expect(cleared.currentAmbiancePad, same(ambiance));
    });
  });
}
