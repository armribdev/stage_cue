import '../entities/pad.dart';
import '../../data/repositories/sound_repository.dart';

/// Use case pour charger les pads d'une board
class LoadSoundsUseCase {
  final SoundRepository _repository;

  LoadSoundsUseCase(this._repository);

  Future<List<Pad>> call(int boardId) async {
    return await _repository.getBoardPads(boardId);
  }
}
