import '../../data/repositories/sound_repository.dart';

/// Use case pour ajouter un son à une board (crée un nouveau pad)
class AddSoundToBoardUseCase {
  final SoundRepository _repository;

  AddSoundToBoardUseCase(this._repository);

  Future<void> call(int boardId, int soundId) async {
    await _repository.createPad(boardId, soundId);
  }
}
