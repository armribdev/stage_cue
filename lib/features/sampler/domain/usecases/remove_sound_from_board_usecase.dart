import '../../data/repositories/sound_repository.dart';

/// Use case pour retirer un son de la board
class RemoveSoundFromBoardUseCase {
  final SoundRepository _repository;

  RemoveSoundFromBoardUseCase(this._repository);

  Future<void> call(int boardId, int soundId) async {
    await _repository.removeSoundFromBoard(boardId, soundId);
  }
}
