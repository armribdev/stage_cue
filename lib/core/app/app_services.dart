import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;

import '../../features/sampler/data/datasources/local_autotag_datasource.dart';
import '../../features/sampler/data/repositories/library_repository.dart';
import '../../features/sampler/data/repositories/sound_repository.dart';
import '../../features/sampler/domain/usecases/load_sounds_usecase.dart';
import '../../features/sampler/domain/usecases/remove_sound_from_board_usecase.dart';
import '../../features/sampler/presentation/providers/sync_controller.dart';
import '../autotag/auto_tag_pack.dart';
import '../autotag/auto_tag_pack_controller.dart';
import '../autotag/auto_tag_pack_installer.dart';
import '../autotag/auto_tag_service.dart';
import '../autotag/mood_tagging.dart';
import '../database/database.dart' as db;
import '../settings/app_preferences.dart';
import '../sync/auto_sync_coordinator.dart';
import '../utils/layout_utils.dart';

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

  /// Pack de modèles de l'analyse automatique ; `null` hors poste de bureau.
  final AutoTagPackController? autoTagPack;

  AppServices._({
    required this.database,
    required this.soundRepository,
    required this.libraryRepository,
    required this.syncController,
    required this.autoSyncCoordinator,
    required this.loadSoundsUseCase,
    required this.removeSoundFromBoardUseCase,
    required this.appPreferences,
    this.autoTagPack,
  });

  factory AppServices.create() {
    final database = db.AppDatabase();
    final repository = SoundRepository.fromDatabase(database);
    final libraryRepository = LibraryRepository.fromDatabase(database);
    final syncController = SyncController(libraryRepository);
    final appPreferences = AppPreferences();
    // Poste de bureau seulement : le modèle (≈ 480 Mo en mémoire) exclut le
    // mobile (décision 0029).
    final pack = isNativeDesktopPlatform()
        ? AutoTagPack.inSupportDirectory()
        : null;
    final autoSyncCoordinator = AutoSyncCoordinator(
      database,
      libraryRepository,
      syncController,
      appPreferences,
      autoTag: pack == null
          ? null
          : _createAutoTagService(database, libraryRepository, pack),
    );
    final autoTagPack = pack == null
        ? null
        : (AutoTagPackController(pack, AutoTagPackInstaller(pack))
            ..onInstalled = autoSyncCoordinator.requestAutoTag);
    unawaited(autoTagPack?.refresh());
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
      autoTagPack: autoTagPack,
    );
  }

  static AutoTagService _createAutoTagService(
    db.AppDatabase database,
    LibraryRepository libraryRepository,
    AutoTagPack pack,
  ) {
    MoodScorer? scorer;
    return AutoTagService(
      data: LocalAutoTagDataSource(database),
      pack: pack,
      libraryRoots: () async => {
        for (final library in await libraryRepository.getLibraries())
          library.id: library.localRootPath,
      },
      probeAvailable: libraryRepository.probeLocallyAvailableSoundIds,
      loadScorer: () async => scorer ??= MoodScorer.fromBytes(
        await rootBundle.load('assets/autotag/text_latents.f32'),
      ),
    );
  }

  /// Composition root des tests d'intégration UI : mêmes services réels que
  /// [AppServices.create], mais sur une base fournie par l'appelant (en mémoire)
  /// et sans réseau. Deux écarts assumés :
  ///
  /// - [AutoSyncCoordinator.start] n'est PAS appelé — un test ne doit ni toucher
  ///   Drive ni dépendre d'un pull de lancement ;
  /// - le pull initial est marqué réglé d'emblée, sinon `loadBoards` conserve
  ///   indéfiniment son skeleton en attendant une fusion distante qui ne viendra
  ///   jamais (garde anti « Scène 1 » fantôme, cf. `SamplerNotifier.loadBoards`).
  ///
  /// [AppPreferences] n'est volontairement pas chargé : `load()` passe par
  /// `path_provider`, indisponible sous `flutter_test`. Les valeurs par défaut
  /// en mémoire suffisent, tant qu'un test n'écrit pas de préférence.
  @visibleForTesting
  factory AppServices.forTesting(db.AppDatabase database) {
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
    libraryRepository.markInitialSyncSettled();
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
    autoTagPack?.dispose();
    autoSyncCoordinator.dispose();
    syncController.dispose();
    database.close();
  }
}
