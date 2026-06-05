import 'dart:async';

import 'package:drift/drift.dart' show TableUpdate;

import '../../features/sampler/data/repositories/library_repository.dart';
import '../../features/sampler/domain/entities/library.dart';
import '../../features/sampler/presentation/providers/sync_controller.dart';
import '../database/database.dart' as db;

/// Coordonne la synchronisation automatique (mode semi-auto) :
/// - **pull au lancement** : reconnexion silencieuse + récupération du snapshot
///   distant le plus récent ;
/// - **push débouncé** : toute modification des données utilisateur planifie un
///   push (anti-rebond géré par [SyncController]).
///
/// S'appuie sur le flux Drift [db.AppDatabase.tableUpdates] : pas besoin de
/// disséminer des appels de synchro dans chaque mutation.
class AutoSyncCoordinator {
  final db.AppDatabase _database;
  final LibraryRepository _repository;
  final SyncController _syncController;

  StreamSubscription<Set<TableUpdate>>? _subscription;

  AutoSyncCoordinator(this._database, this._repository, this._syncController);

  /// Démarre l'écoute des modifications et lance un pull initial en arrière-plan.
  void start() {
    _subscription = _database.tableUpdates().listen(_onTablesUpdated);
    unawaited(_initialPull());
  }

  Future<void> _onTablesUpdated(Set<TableUpdate> updates) async {
    // Ignorer les écritures ne touchant QUE la table de bookkeeping `libraries`
    // (mise à jour de révision après un push) : sinon le push se relancerait en
    // boucle.
    final touchesUserData = updates.any((u) => u.table != 'libraries');
    if (!touchesUserData) return;

    final library = await _firstConnectedLibrary();
    if (library == null) return;
    _syncController.schedulePush(library);
  }

  Future<void> _initialPull() async {
    final reconnected = await _repository.reconnectSilently();
    if (!reconnected) return;
    final library = await _firstConnectedLibrary();
    if (library == null) return;
    await _syncController.pullForLaunch(library);
  }

  Future<Library?> _firstConnectedLibrary() async {
    final libraries = await _repository.getLibraries();
    for (final library in libraries) {
      if (library.isConnectedToDrive) return library;
    }
    return null;
  }

  void dispose() {
    _subscription?.cancel();
  }
}
