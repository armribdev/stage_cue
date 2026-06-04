import '../../data/repositories/sound_repository.dart';

/// Use case pour supprimer un pad
class RemoveSoundFromBoardUseCase {
  final SoundRepository _repository;

  RemoveSoundFromBoardUseCase(this._repository);

  Future<void> call(int padId) async {
    await _repository.deletePad(padId);
  }
}
