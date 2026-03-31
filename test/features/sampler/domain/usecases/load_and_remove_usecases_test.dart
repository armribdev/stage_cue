import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stage_cue/features/sampler/data/repositories/sound_repository.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';
import 'package:stage_cue/features/sampler/domain/usecases/load_sounds_usecase.dart';
import 'package:stage_cue/features/sampler/domain/usecases/remove_sound_from_board_usecase.dart';

class MockSoundRepository extends Mock implements SoundRepository {}

void main() {
  group('LoadSoundsUseCase', () {
    test('retourne les sons de la board demandee', () async {
      final repository = MockSoundRepository();
      final sounds = [
        Sound(
          id: 1,
          title: 'boom',
          filePath: '/tmp/boom.wav',
          type: SoundType.soundEffect,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];
      when(() => repository.getBoardSounds(42)).thenAnswer((_) async => sounds);
      final useCase = LoadSoundsUseCase(repository);

      final result = await useCase(42);

      expect(result, hasLength(1));
      expect(result.first.title, 'boom');
      verify(() => repository.getBoardSounds(42)).called(1);
    });
  });

  group('RemoveSoundFromBoardUseCase', () {
    test('appelle le repository avec boardId et soundId', () async {
      final repository = MockSoundRepository();
      when(() => repository.removeSoundFromBoard(10, 99))
          .thenAnswer((_) async {});
      final useCase = RemoveSoundFromBoardUseCase(repository);

      await useCase(10, 99);

      verify(() => repository.removeSoundFromBoard(10, 99)).called(1);
    });
  });
}

