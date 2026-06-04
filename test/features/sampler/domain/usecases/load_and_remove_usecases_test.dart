import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stage_cue/features/sampler/data/repositories/sound_repository.dart';
import 'package:stage_cue/features/sampler/domain/entities/pad.dart';
import 'package:stage_cue/features/sampler/domain/usecases/load_sounds_usecase.dart';
import 'package:stage_cue/features/sampler/domain/usecases/remove_sound_from_board_usecase.dart';

class MockSoundRepository extends Mock implements SoundRepository {}

void main() {
  group('LoadSoundsUseCase', () {
    test('retourne les pads de la board demandee', () async {
      final repository = MockSoundRepository();
      final pads = [
        Pad(
          id: 1,
          boardId: 42,
          sortOrder: 0,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];
      when(() => repository.getBoardPads(42)).thenAnswer((_) async => pads);
      final useCase = LoadSoundsUseCase(repository);

      final result = await useCase(42);

      expect(result, hasLength(1));
      expect(result.first.id, 1);
      verify(() => repository.getBoardPads(42)).called(1);
    });
  });

  group('RemoveSoundFromBoardUseCase', () {
    test('appelle le repository avec le padId', () async {
      final repository = MockSoundRepository();
      when(() => repository.deletePad(99)).thenAnswer((_) async {});
      final useCase = RemoveSoundFromBoardUseCase(repository);

      await useCase(99);

      verify(() => repository.deletePad(99)).called(1);
    });
  });
}
