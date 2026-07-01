import '../../features/sampler/data/repositories/library_repository.dart';
import '../../features/sampler/data/repositories/sound_repository.dart';
import '../../features/sampler/domain/usecases/load_sounds_usecase.dart';
import '../../features/sampler/domain/usecases/remove_sound_from_board_usecase.dart';
import '../../features/sampler/presentation/providers/sync_controller.dart';
import '../database/database.dart' as db;
import '../settings/app_preferences.dart';
import '../sync/auto_sync_coordinator.dart';

/// Composition root des services partagés de l'application.
class AppServices {
  final db.AppDatabase database;
  final SoundRepository soundRepository;
  final LibraryRepository libraryRepository;
  final SyncController syncController;
  final AutoSyncCoordinator autoSyncCoordinator;
  final LoadSoundsUseCase loadSoundsUseCase;
  final RemoveSoundFromBoardUseCase removeSoundFromBoardUseCase;
  final AppPreferences appPreferences;

  AppServices._({
    required this.database,
    required this.soundRepository,
    required this.libraryRepository,
    required this.syncController,
    required this.autoSyncCoordinator,
    required this.loadSoundsUseCase,
    required this.removeSoundFromBoardUseCase,
    required this.appPreferences,
  });

  factory AppServices.create() {
    final database = db.AppDatabase();
    final repository = SoundRepository.fromDatabase(database);
    final libraryRepository = LibraryRepository.fromDatabase(database);
    final syncController = SyncController(libraryRepository);
    final appPreferences = AppPreferences();
    final autoSyncCoordinator = AutoSyncCoordinator(
      database,
      libraryRepository,
      syncController,
      appPreferences,
    );
    // Démarre l'écoute des modifications + le pull initial au lancement.
    autoSyncCoordinator.start();
    return AppServices._(
      database: database,
      soundRepository: repository,
      libraryRepository: libraryRepository,
      syncController: syncController,
      autoSyncCoordinator: autoSyncCoordinator,
      loadSoundsUseCase: LoadSoundsUseCase(repository),
      removeSoundFromBoardUseCase: RemoveSoundFromBoardUseCase(repository),
      appPreferences: appPreferences,
    );
  }

  void dispose() {
    autoSyncCoordinator.dispose();
    syncController.dispose();
    database.close();
  }
}
