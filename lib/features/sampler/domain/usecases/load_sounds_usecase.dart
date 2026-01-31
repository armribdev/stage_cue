import '../entities/sound.dart';
import '../../data/repositories/sound_repository.dart';

/// Use case pour charger les sons de la board
class LoadSoundsUseCase {
  final SoundRepository _repository;

  LoadSoundsUseCase(this._repository);

  Future<List<Sound>> call(int boardId) async {
    return await _repository.getBoardSounds(boardId);
  }
}

