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

  // Vrai pendant _initialPull : supprime les schedulePush déclenchés par le
  // merge en-place (le contenu vient du distant, pas d'une édition locale).
  bool _ignoreUpdates = false;

  AutoSyncCoordinator(this._database, this._repository, this._syncController);

  /// Démarre l'écoute des modifications et lance un pull initial en arrière-plan.
  void start() {
    _subscription = _database.tableUpdates().listen(_onTablesUpdated);
    unawaited(_initialPull());
  }

  Future<void> _onTablesUpdated(Set<TableUpdate> updates) async {
    if (_ignoreUpdates) return;
    // Ignorer les écritures ne touchant QUE la table de bookkeeping `libraries`
    // (mise à jour de révision après un push) : sinon le push se relancerait en
    // boucle.
    final touchesUserData = updates.any((u) => u.table != 'libraries');
    if (!touchesUserData) return;

    final libraries = await _connectedLibraries();
    for (final library in libraries) {
      _syncController.schedulePush(library);
    }
  }

  Future<void> _initialPull() async {
    try {
      final reconnected = await _repository.reconnectSilently();

      final libraries = await _connectedLibraries();
      if (libraries.isEmpty) return; // Usage 100 % local : la synchro reste idle.

      if (!reconnected) {
        // Bibliothèque Drive configurée mais pas de session (hors-ligne au
        // lancement) : on signale l'état local plutôt que de rester silencieux.
        _syncController.markOffline();
        return;
      }

      _ignoreUpdates = true;
      try {
        for (final library in libraries) {
          await _syncController.pullForLaunch(library);
        }
      } finally {
        _ignoreUpdates = false;
      }

      // Indexe les fichiers ajoutés manuellement sur Drive (absents de la BDD).
      for (final library in libraries) {
        try {
          await _repository.indexDriveFolder(library: library);
        } catch (_) {
          // Continue avec les autres dossiers si l'indexation échoue.
        }
      }
    } catch (_) {
      // Erreur inattendue au démarrage : passer en hors-ligne plutôt que
      // de laisser la pastille bloquée sur « Synchro… ».
      _syncController.markOffline();
    }
  }

  Future<List<Library>> _connectedLibraries() async {
    final libraries = await _repository.getLibraries();
    return libraries.where((library) => library.isConnectedToDrive).toList();
  }

  void dispose() {
    _subscription?.cancel();
  }
}
