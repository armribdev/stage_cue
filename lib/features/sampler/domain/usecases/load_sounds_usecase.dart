import '../entities/sound.dart';
import '../../data/repositories/sound_repository.dart';

/// Use case pour charger tous les sons
class LoadSoundsUseCase {
  final SoundRepository _repository;

  LoadSoundsUseCase(this._repository);

  Future<List<Sound>> call() async {
    return await _repository.getAllSounds();
  }
}

