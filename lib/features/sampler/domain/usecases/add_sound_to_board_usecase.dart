import '../../data/repositories/sound_repository.dart';

/// Use case pour ajouter un son à la board
class AddSoundToBoardUseCase {
  final SoundRepository _repository;

  AddSoundToBoardUseCase(this._repository);

  Future<void> call(int soundId) async {
    await _repository.addSoundToBoard(soundId);
  }
}
