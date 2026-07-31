import 'dart:async';

import 'package:drift/drift.dart' show TableUpdate;

import '../../features/sampler/data/models/indexing_progress.dart';
import '../../features/sampler/data/repositories/library_repository.dart';
import '../../features/sampler/domain/entities/library.dart';
import '../../features/sampler/presentation/providers/sync_controller.dart';
import '../database/database.dart' as db;
import '../settings/app_preferences.dart';
import 'drive_client.dart';
import 'sync_log.dart';

/// Intervalle de la veille : période entre deux sondes automatiques pendant que
/// l'app tourne au premier plan.
///
/// Une sonde coûte un `changes.list` plus les sondes de manifest groupées, soit
/// ~5 requêtes en régime établi ([0020](../../../docs/decisions/0020-sonde-de-pull-groupee-et-jeton-de-manifest.md),
/// [0021](../../../docs/decisions/0021-synchronisation-incrementale-par-changes-list.md)).
/// Assez léger pour tourner en fond, assez espacé pour rester invisible.
const Duration _watchInterval = Duration(minutes: 5);

/// Délai minimal entre deux sondes déclenchées par un retour au premier plan.
///
/// Sans lui, un alt-tab répété — exactement ce que fait quelqu'un qui dépose des
/// fichiers sur Drive depuis un navigateur — sonderait Drive à chaque
/// aller-retour.
const Duration _watchResumeThrottle = Duration(minutes: 1);

/// Ce qui a déclenché une passe de synchronisation. Détermine **jusqu'où elle
/// va**, pas ce qu'elle fait : la séquence (indexer → tirer → ré-élaguer) est la
/// même pour les trois ([0005](../../../docs/decisions/0005-ordre-de-synchronisation-au-lancement.md)).
enum SyncPassTrigger {
  /// Lancement de l'app : séquence complète, repli sur le scan complet autorisé.
  launch,

  /// Bouton « Actualiser depuis Drive » : idem, avec remontée de progression.
  manual,

  /// Veille périodique ou retour au premier plan : delta **seulement**.
  watch;

  /// Une passe de veille est *discrète* : elle ne rescanne pas et ne fait pas
  /// bouger la pastille pour dire qu'il n'y a rien à dire.
  bool get isWatch => this == SyncPassTrigger.watch;
}

/// Bilan d'une passe, pour l'UI qui l'a déclenchée à la main.
class SyncPassReport {
  /// Bibliothèques indexées **et** tirées jusqu'au bout.
  final int synced;

  /// Bibliothèques écartées : index incomplet, erreur réseau, ou delta
  /// inexploitable en veille. Leur état local est celui d'avant la passe.
  final int skipped;

  /// Une session Google expirée a été rencontrée : l'UI doit proposer la
  /// reconnexion plutôt qu'un message d'erreur générique.
  final bool authExpired;

  /// Aucune session Drive utilisable : rien n'a été tenté.
  final bool offline;

  /// Le mode réseau choisi interdit la synchro : rien n'a été tenté non plus,
  /// mais pour une raison que l'utilisateur a lui-même posée. Distinct
  /// d'[offline], qui est subi — le message à afficher n'est pas le même.
  final bool localMode;

  /// Panne globale de la passe (au-delà d'une bibliothèque en échec, comptée
  /// dans [skipped]). Distinct de `skipped` : une passe qui n'a même pas pu
  /// démarrer ne se raconte pas comme « une bibliothèque non actualisée ».
  final Object? error;

  const SyncPassReport({
    this.synced = 0,
    this.skipped = 0,
    this.authExpired = false,
    this.offline = false,
    this.localMode = false,
    this.error,
  });
}

/// Coordonne la synchronisation automatique (mode semi-auto) :
/// - **pull au lancement** : reconnexion silencieuse + récupération du snapshot
///   distant le plus récent ;
/// - **veille** : sonde périodique du delta Drive pendant que l'app tourne, plus
///   une sonde au retour au premier plan — Drive ne pousse rien vers un client
///   sans endpoint public, c'est le seul moyen de voir un ajout distant sans
///   redémarrer ;
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

  /// Veille périodique. Créé par [start], donc absent en test tant que
  /// [start] n'est pas appelé.
  Timer? _watchTimer;

  /// App passée en arrière-plan : la veille se tait. Un `Timer` continue de
  /// tirer alors que personne ne regarde l'écran (et, sur mobile, alors que le
  /// système peut geler le process en plein appel réseau).
  bool _isBackgrounded = false;

  /// Horodatage de la dernière sonde de veille — pour l'anti-rebond de reprise.
  DateTime? _lastWatchPassAt;

  /// Passe en vol. Sert de **verrou** : deux passes concurrentes se marcheraient
  /// sur [_ignoreUpdates] (la première à finir le rabaisserait sous la seconde)
  /// et doubleraient le trafic Drive. Une demande manuelle rejoint la passe en
  /// cours plutôt que d'en ouvrir une seconde.
  Future<SyncPassReport>? _passInFlight;

  /// Bibliothèques pour lesquelles la veille a déjà signalé qu'elle renonçait au
  /// scan complet — cf. [SyncLog.watchFullScanDeferred].
  final Set<int> _fullScanDeferredReported = {};

  /// Appelé quand le pull de lancement a fini sa passe (quel que soit l'issue).
  /// Permet à l'UI de relancer un chargement des boards resté en attente le
  /// temps que la synchro décide s'il y a des boards distants à fusionner.
  void Function()? onInitialPullSettled;

  // Vrai pendant une passe : supprime les schedulePush déclenchés par le
  // merge en-place (le contenu vient du distant, pas d'une édition locale).
  bool _ignoreUpdates = false;

  AutoSyncCoordinator(
    this._database,
    this._repository,
    this._syncController,
    this._appPreferences,
  );

  /// Démarre l'écoute des modifications, la veille, et lance un pull initial en
  /// arrière-plan.
  void start() {
    _appPreferences.addListener(_onConnectivityModeChanged);
    _subscription = _database.tableUpdates().listen(_onTablesUpdated);
    // Ménage des téléchargements interrompus (app tuée, coupure) : hors du pull
    // initial, qui ne tourne qu'en mode connecté — ces résidus occupent le
    // disque même en usage 100 % local.
    unawaited(_repository.cleanupPartialDownloads());
    unawaited(_initialPull());
    _watchTimer = Timer.periodic(
      _watchInterval,
      (_) => unawaited(_runWatchPass()),
    );
  }

  /// Passe déclenchée à la main (bouton « Actualiser depuis Drive »).
  ///
  /// Passe par la **même** séquence que le lancement : delta d'abord, scan
  /// complet en repli, et indexation **avant** le pull. Un bouton qui rescanne
  /// systématiquement paie des secondes pour ce que le chemin incrémental
  /// rattrape en une requête, et tirer avant d'indexer recâble les boards sur
  /// des sons pas encore connus ([0005](../../../docs/decisions/0005-ordre-de-synchronisation-au-lancement.md)).
  Future<SyncPassReport> refreshNow({
    void Function(Library library, IndexingProgress progress)? onIndexProgress,
  }) {
    return _startPass(SyncPassTrigger.manual, onIndexProgress: onIndexProgress);
  }

  /// L'app revient au premier plan : sonde tout de suite plutôt que d'attendre
  /// le prochain tick. C'est le cas le plus courant du besoin — on vient
  /// d'ajouter des fichiers sur Drive depuis un navigateur ou un téléphone.
  void onAppResumed() {
    _isBackgrounded = false;
    final last = _lastWatchPassAt;
    if (last != null && DateTime.now().difference(last) < _watchResumeThrottle) {
      SyncLog.trace('veille : reprise trop rapprochée, sonde sautée');
      return;
    }
    unawaited(_runWatchPass());
  }

  /// L'app passe en arrière-plan : la veille se tait jusqu'au retour.
  void onAppBackgrounded() => _isBackgrounded = true;

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
      await _startPass(SyncPassTrigger.launch);
    } finally {
      // Sur TOUS les chemins (retour anticipé, succès, erreur) : signaler que la
      // passe de lancement est terminée. Débloque un chargement de boards mis en
      // attente (cf. garde anti « Scène 1 » fantôme dans `loadBoards`).
      _repository.markInitialSyncSettled();
      onInitialPullSettled?.call();
    }
  }

  /// Sonde de veille, sous conditions. Chaque renoncement est tracé : une veille
  /// qui ne fait rien doit rester distinguable d'une veille qui échoue.
  Future<void> _runWatchPass() async {
    if (_isBackgrounded) {
      SyncLog.trace('veille : app en arrière-plan, sonde sautée');
      return;
    }
    if (!_appPreferences.allowsNetworkSync) {
      SyncLog.trace('veille : mode local, sonde sautée');
      return;
    }
    if (_syncController.isAutoSyncPaused) {
      // Mode Spectacle : aucun trafic réseau ni écriture disque imprévus
      // pendant les déclenchements live — même raison que la suspension des
      // push.
      SyncLog.trace('veille : Mode Spectacle actif, sonde sautée');
      return;
    }
    if (_passInFlight != null) {
      SyncLog.trace('veille : une passe est déjà en cours, sonde sautée');
      return;
    }
    _lastWatchPassAt = DateTime.now();
    await _startPass(SyncPassTrigger.watch);
  }

  Future<SyncPassReport> _startPass(
    SyncPassTrigger trigger, {
    void Function(Library, IndexingProgress)? onIndexProgress,
  }) {
    final inFlight = _passInFlight;
    if (inFlight != null) {
      // La passe en vol fait déjà le travail demandé : la rejoindre. Une demande
      // manuelle arrivée pendant le pull de lancement n'affichera donc pas de
      // progression — elle n'a rien à relancer.
      SyncLog.trace('passe ${trigger.name} : rejoint la passe en cours');
      return inFlight;
    }
    final pass = _runPass(trigger, onIndexProgress: onIndexProgress)
        .whenComplete(() => _passInFlight = null);
    _passInFlight = pass;
    return pass;
  }

  /// Séquence canonique, partagée par les trois déclencheurs.
  ///
  /// Ne relance jamais d'exception : son appelant est soit un `unawaited`, soit
  /// un bouton qui attend un bilan.
  Future<SyncPassReport> _runPass(
    SyncPassTrigger trigger, {
    void Function(Library, IndexingProgress)? onIndexProgress,
  }) async {
    if (!_appPreferences.allowsNetworkSync) {
      return const SyncPassReport(localMode: true);
    }
    try {
      final reconnected = await _repository.reconnectSilently();

      final libraries = await _connectedLibraries();
      if (libraries.isEmpty) {
        return const SyncPassReport(); // Usage 100 % local : la synchro reste idle.
      }

      if (!reconnected) {
        // Bibliothèque Drive configurée mais pas de session (hors-ligne au
        // lancement) : on signale l'état local plutôt que de rester silencieux.
        _syncController.markOffline();
        return const SyncPassReport(offline: true);
      }

      // Modèle par-dossier : l'indexation doit précéder le pull. Elle crée les
      // nœuds dossier + les sons depuis le listing Drive ; sans eux, un appareil
      // vierge n'aurait aucun nœud à tirer (métadonnées) et le pull racine
      // recâblerait les boards sur des sons encore inexistants. On garde tout
      // sous `_ignoreUpdates` : un son fraîchement indexé n'a pas de métadonnée
      // synchronisable (chaque appareil le découvre via son propre index), donc
      // aucun push à déclencher.
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
        var skipped = 0;
        var authExpired = false;

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
                // rescanne-t-on en réalité à chaque lancement ? En veille, le
                // cas « rien n'a bougé » est la norme et descend en trace.
                if (trigger.isWatch && upserted == 0 && removed == 0) {
                  SyncLog.trace('${library.name} : veille — rien de neuf.');
                } else {
                  SyncLog.deltaApplied(
                    library: library.name,
                    upserted: upserted,
                    removed: removed,
                  );
                }
                _fullScanDeferredReported.remove(library.id);
                fullyIndexed.add(library);
              case DriveSyncNeedsFullScan(:final reason):
                if (trigger.isWatch) {
                  // La veille ne rescanne JAMAIS : un scan complet, c'est des
                  // secondes de listing Drive et des écritures en masse,
                  // déclenchées par une horloge et non par l'utilisateur — le
                  // contraire de ce qu'on veut sous une app posée sur une table
                  // de régie. La bibliothèque garde son état ; le prochain
                  // lancement ou le bouton « Actualiser » fera le scan.
                  _reportWatchFullScanDeferred(library, reason);
                  skipped++;
                  continue;
                }
                SyncLog.fullScanRequired(
                  library: library.name,
                  reason: reason,
                );
                final result = await _repository
                    .indexDriveFolder(
                      library: library,
                      onProgress: onIndexProgress == null
                          ? null
                          : (progress) => onIndexProgress(library, progress),
                    )
                    .timeout(const Duration(seconds: 120));
                fullyIndexed.add(library);
                presentByLibrary[library.id] = result.presentDriveFileIds;
            }
          } catch (e) {
            // Index incomplet : on saute son pull cette passe. Non bloquant
            // (les autres bibliothèques continuent), mais plus muet — c'est la
            // conséquence la plus lourde de toute la passe de lancement.
            if (e is DriveAuthException) authExpired = true;
            skipped++;
            SyncLog.librarySkipped(library: library.name, error: e);
          }
        }

        // 2. Pull par-dossier (métadonnées) puis racine (boards) — uniquement
        //    pour les bibliothèques entièrement indexées : les nœuds et les sons
        //    référencés existent alors bien tous localement.
        for (final library in fullyIndexed) {
          if (trigger.isWatch) {
            await _syncController.pullInBackground(library);
          } else {
            await _syncController.pullForLaunch(library);
          }

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

        // Une session expirée rencontrée pendant l'indexation ne remonte pas
        // par le pull (qui n'a pas eu lieu pour cette bibliothèque) : sans ça,
        // la pastille resterait sur un état sain alors qu'il faut un OAuth.
        if (authExpired) await _syncController.handleAuthFailure();

        return SyncPassReport(
          synced: fullyIndexed.length,
          skipped: skipped,
          authExpired: authExpired,
        );
      } finally {
        _ignoreUpdates = false;
      }
    } catch (e, stackTrace) {
      // Erreur inattendue : passer en hors-ligne plutôt que de laisser la
      // pastille bloquée sur « Synchro… ». La pastille ne peut pas distinguer
      // « pas de réseau » d'un bug : seul ce log le dit.
      SyncLog.syncPassFailed(
        trigger: trigger.name,
        error: e,
        stackTrace: stackTrace,
      );
      _syncController.markOffline();
      return SyncPassReport(error: e);
    }
  }

  /// Journalise le renoncement de la veille au scan complet — une seule fois par
  /// bibliothèque, la raison étant stable d'un tick à l'autre.
  void _reportWatchFullScanDeferred(Library library, String reason) {
    if (!_fullScanDeferredReported.add(library.id)) {
      SyncLog.trace('${library.name} : veille — scan complet toujours différé.');
      return;
    }
    SyncLog.watchFullScanDeferred(library: library.name, reason: reason);
  }

  Future<List<Library>> _connectedLibraries() async {
    final libraries = await _repository.getLibraries();
    return libraries.where((library) => library.isConnectedToDrive).toList();
  }

  void dispose() {
    _appPreferences.removeListener(_onConnectivityModeChanged);
    _watchTimer?.cancel();
    _watchTimer = null;
    _subscription?.cancel();
  }
}
