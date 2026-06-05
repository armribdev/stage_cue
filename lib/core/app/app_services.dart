import '../../features/sampler/data/datasources/local_library_datasource.dart';
import '../../features/sampler/data/repositories/library_repository.dart';
import '../../features/sampler/data/repositories/sound_repository.dart';
import '../../features/sampler/domain/usecases/load_sounds_usecase.dart';
import '../../features/sampler/domain/usecases/remove_sound_from_board_usecase.dart';
import '../../features/sampler/presentation/providers/sync_controller.dart';
import '../database/database.dart' as db;
import '../sync/audio_cache_manager.dart';
import '../sync/google_drive_client.dart';
import '../sync/library_sync_service.dart';
import '../sync/snapshot_store.dart';

/// Composition root des services partagés de l'application.
class AppServices {
  final db.AppDatabase database;
  final SoundRepository soundRepository;
  final LibraryRepository libraryRepository;
  final SyncController syncController;
  final LoadSoundsUseCase loadSoundsUseCase;
  final RemoveSoundFromBoardUseCase removeSoundFromBoardUseCase;

  AppServices._({
    required this.database,
    required this.soundRepository,
    required this.libraryRepository,
    required this.syncController,
    required this.loadSoundsUseCase,
    required this.removeSoundFromBoardUseCase,
  });

  factory AppServices.create() {
    final database = db.AppDatabase();
    final repository = SoundRepository.fromDatabase(database);
    final libraryRepository = LibraryRepository(
      LocalLibraryDataSource(database),
      GoogleDriveAuthenticator(),
      LibrarySyncService(DriftSnapshotStore(database)),
      AudioCacheManager(),
    );
    return AppServices._(
      database: database,
      soundRepository: repository,
      libraryRepository: libraryRepository,
      syncController: SyncController(libraryRepository),
      loadSoundsUseCase: LoadSoundsUseCase(repository),
      removeSoundFromBoardUseCase: RemoveSoundFromBoardUseCase(repository),
    );
  }

  void dispose() {
    syncController.dispose();
    database.close();
  }
}
