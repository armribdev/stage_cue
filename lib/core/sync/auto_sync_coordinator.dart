import 'dart:async';

import 'package:drift/drift.dart' show TableUpdate;

import '../../features/sampler/data/repositories/library_repository.dart';
import '../../features/sampler/domain/entities/library.dart';
import '../../features/sampler/presentation/providers/sync_controller.dart';
import '../database/database.dart' as db;
import '../settings/app_preferences.dart';

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
  final AppPreferences _appPreferences;

  StreamSubscription<Set<TableUpdate>>? _subscription;

  // Vrai pendant _initialPull : supprime les schedulePush déclenchés par le
  // merge en-place (le contenu vient du distant, pas d'une édition locale).
  bool _ignoreUpdates = false;

  AutoSyncCoordinator(
    this._database,
    this._repository,
    this._syncController,
    this._appPreferences,
  );

  /// Démarre l'écoute des modifications et lance un pull initial en arrière-plan.
  void start() {
    _appPreferences.addListener(_onConnectivityModeChanged);
    _subscription = _database.tableUpdates().listen(_onTablesUpdated);
    unawaited(_initialPull());
  }

  void _onConnectivityModeChanged() {
    if (_appPreferences.allowsNetworkSync) {
      unawaited(_initialPull());
    }
  }

  Future<void> _onTablesUpdated(Set<TableUpdate> updates) async {
    if (_ignoreUpdates || !_appPreferences.allowsNetworkSync) return;
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
    if (!_appPreferences.allowsNetworkSync) return;
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

      // Modèle par-dossier : l'indexation doit précéder le pull. Elle crée les
      // nœuds dossier + les sons depuis le listing Drive ; sans eux, un appareil
      // vierge n'aurait aucun nœud à tirer (métadonnées) et le pull racine
      // recâblerait les boards sur des sons encore inexistants. On garde tout
      // sous `_ignoreUpdates` : un son fraîchement indexé n'a pas de métadonnée
      // synchronisable (chaque appareil le découvre via son propre index), donc
      // aucun push à déclencher au lancement.
      _ignoreUpdates = true;
      try {
        // 1. Indexe (crée nœuds + sons). Timeout : évite de bloquer le lancement
        //    sur un dossier Drive volumineux ou une connexion lente. On ne
        //    retient que les bibliothèques ENTIÈREMENT indexées : un index
        //    partiel (timeout, réseau lent) suivi d'un pull racine purgerait les
        //    boards et les recâblerait sur des sons encore absents → pads perdus
        //    pour la session. Mieux vaut garder l'état local et réessayer au
        //    prochain lancement (l'index sera plus rapide, cache chaud).
        final fullyIndexed = <Library>[];
        for (final library in libraries) {
          try {
            await _repository
                .indexDriveFolder(library: library)
                .timeout(const Duration(seconds: 30));
            fullyIndexed.add(library);
          } catch (_) {
            // Index incomplet : on saute son pull cette session.
          }
        }

        // 2. Pull par-dossier (métadonnées) puis racine (boards) — uniquement
        //    pour les bibliothèques entièrement indexées : les nœuds et les sons
        //    référencés existent alors bien tous localement.
        for (final library in fullyIndexed) {
          await _syncController.pullForLaunch(library);
        }
      } finally {
        _ignoreUpdates = false;
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
    _appPreferences.removeListener(_onConnectivityModeChanged);
    _subscription?.cancel();
  }
}
