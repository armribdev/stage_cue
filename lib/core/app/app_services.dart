import '../../features/sampler/data/repositories/sound_repository.dart';
import '../../features/sampler/domain/usecases/load_sounds_usecase.dart';
import '../../features/sampler/domain/usecases/remove_sound_from_board_usecase.dart';
import '../database/database.dart' as db;

/// Composition root des services partagés de l'application.
class AppServices {
  final db.AppDatabase database;
  final SoundRepository soundRepository;
  final LoadSoundsUseCase loadSoundsUseCase;
  final RemoveSoundFromBoardUseCase removeSoundFromBoardUseCase;

  AppServices._({
    required this.database,
    required this.soundRepository,
    required this.loadSoundsUseCase,
    required this.removeSoundFromBoardUseCase,
  });

  factory AppServices.create() {
    final database = db.AppDatabase();
    final repository = SoundRepository.fromDatabase(database);
    return AppServices._(
      database: database,
      soundRepository: repository,
      loadSoundsUseCase: LoadSoundsUseCase(repository),
      removeSoundFromBoardUseCase: RemoveSoundFromBoardUseCase(repository),
    );
  }

  void dispose() {
    database.close();
  }
}
