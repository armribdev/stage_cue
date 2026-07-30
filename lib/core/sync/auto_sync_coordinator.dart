import 'dart:async';

import 'package:drift/drift.dart' show TableUpdate;

import '../../features/sampler/data/repositories/library_repository.dart';
import '../../features/sampler/domain/entities/library.dart';
import '../../features/sampler/presentation/providers/sync_controller.dart';
import '../database/database.dart' as db;
import '../settings/app_preferences.dart';
import 'sync_log.dart';

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

  /// Appelé quand le pull de lancement a fini sa passe (quel que soit l'issue).
  /// Permet à l'UI de relancer un chargement des boards resté en attente le
  /// temps que la synchro décide s'il y a des boards distants à fusionner.
  void Function()? onInitialPullSettled;

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
    // Ménage des téléchargements interrompus (app tuée, coupure) : hors du pull
    // initial, qui ne tourne qu'en mode connecté — ces résidus occupent le
    // disque même en usage 100 % local.
    unawaited(_repository.cleanupPartialDownloads());
    unawaited(_initialPull());
  }

  void _onConnectivityModeChanged() {
    if (_appPreferences.allowsNetworkSync) {
      unawaited(_initialPull());
    }
  }

  Future<void> _onTablesUpdated(Set<TableUpdate> updates) async {
    if (_ignoreUpdates || !_appPreferences.allowsNetworkSync) return;
    // Ignorer les écritures ne touchant QUE des tables de bookkeeping de
    // synchro : sinon le push se relancerait en boucle.
    // - `libraries` : révision mise à jour après un push ;
    // - `library_folders` : révision et sonde de manifest par nœud, écrites par
    //   le pull lui-même. Ces deux tables ne voyagent dans aucun snapshot (les
    //   exports portent sur `sounds`, `sound_boards` et `pads`), donc une
    //   écriture qui ne touche qu'elles n'a par construction rien à pousser.
    const bookkeepingTables = {'libraries', 'library_folders'};
    final touchesUserData =
        updates.any((u) => !bookkeepingTables.contains(u.table));
    if (!touchesUserData) return;

    final libraries = await _connectedLibraries();
    for (final library in libraries) {
      _syncController.schedulePush(library);
    }
  }

  Future<void> _initialPull() async {
    try {
      await _runInitialPull();
    } finally {
      // Sur TOUS les chemins (retour anticipé, succès, erreur) : signaler que la
      // passe de lancement est terminée. Débloque un chargement de boards mis en
      // attente (cf. garde anti « Scène 1 » fantôme dans `loadBoards`).
      _repository.markInitialSyncSettled();
      onInitialPullSettled?.call();
    }
  }

  Future<void> _runInitialPull() async {
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
        //    L'indexation étant métadonnées-only (aucun téléchargement inline,
        //    cf. LibraryRepository), ce timeout ne borne que le listing Drive +
        //    les insertions : large de côté pour couvrir une arborescence
        //    profonde (des milliers de fichiers en de nombreux sous-dossiers).
        final fullyIndexed = <Library>[];
        // Ensemble « présent sur Drive » de chaque scan complet : source de
        // vérité pour l'existence, réutilisée en 3. après le pull. Une passe
        // INCRÉMENTALE n'y met rien — elle ne connaît pas cet ensemble, et
        // l'élagage par différence sur un delta supprimerait tout ce qui n'a
        // pas bougé.
        final presentByLibrary = <int, Set<String>>{};
        for (final library in libraries) {
          try {
            // Chemin rapide : n'appliquer que ce qui a changé depuis la
            // dernière passe. Il se déclare lui-même insuffisant dès qu'il y a
            // le moindre doute, et on retombe alors sur le scan complet.
            final outcome = await _repository
                .applyDriveChanges(library: library)
                .timeout(const Duration(seconds: 30));
            switch (outcome) {
              case DriveSyncApplied(:final upserted, :final removed):
                // Sans cette trace, impossible de répondre à la seule question
                // qui compte sur ce chemin : le delta sert-il vraiment, ou
                // rescanne-t-on en réalité à chaque lancement ?
                SyncLog.deltaApplied(
                  library: library.name,
                  upserted: upserted,
                  removed: removed,
                );
                fullyIndexed.add(library);
              case DriveSyncNeedsFullScan(:final reason):
                SyncLog.fullScanRequired(
                  library: library.name,
                  reason: reason,
                );
                final result = await _repository
                    .indexDriveFolder(library: library)
                    .timeout(const Duration(seconds: 120));
                fullyIndexed.add(library);
                presentByLibrary[library.id] = result.presentDriveFileIds;
            }
          } catch (e) {
            // Index incomplet : on saute son pull cette session. Non bloquant
            // (les autres bibliothèques continuent), mais plus muet — c'est la
            // conséquence la plus lourde de toute la passe de lancement.
            SyncLog.librarySkipped(library: library.name, error: e);
          }
        }

        // 2. Pull par-dossier (métadonnées) puis racine (boards) — uniquement
        //    pour les bibliothèques entièrement indexées : les nœuds et les sons
        //    référencés existent alors bien tous localement.
        for (final library in fullyIndexed) {
          await _syncController.pullForLaunch(library);

          // 3. Dernier mot au scan live : le merge de snapshot ci-dessus a pu
          //    réinsérer un son pointant vers un fichier déjà supprimé sur Drive
          //    (snapshot distant périmé, poussé par un appareil pas encore
          //    rescanné). On ré-élague donc d'après l'ensemble réellement présent
          //    lors de l'indexation. Sans effet si le pull n'a rien ressuscité.
          final present = presentByLibrary[library.id];
          if (present != null) {
            await _repository.pruneSoundsAbsentFromDrive(
              library: library,
              presentDriveFileIds: present,
            );
          }
        }
      } finally {
        _ignoreUpdates = false;
      }
    } catch (e, stackTrace) {
      // Erreur inattendue au démarrage : passer en hors-ligne plutôt que
      // de laisser la pastille bloquée sur « Synchro… ». La pastille ne peut pas
      // distinguer « pas de réseau » d'un bug : seul ce log le dit.
      SyncLog.initialPullFailed(e, stackTrace);
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
