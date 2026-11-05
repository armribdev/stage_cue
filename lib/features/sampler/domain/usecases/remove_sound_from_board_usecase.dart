import '../../data/repositories/sound_repository.dart';

class RemoveSoundFromBoardUseCase {
  final SoundRepository _repository;

  RemoveSoundFromBoardUseCase(this._repository);

  Future<void> call(int padId) async {
    await _repository.deletePad(padId);
  }
}
