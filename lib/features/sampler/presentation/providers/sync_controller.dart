import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/sync/drive_client.dart';
import '../../../../core/sync/library_sync_service.dart';
import '../../data/repositories/library_repository.dart';
import '../../domain/entities/library.dart';

/// Statut de synchronisation présenté à l'utilisateur.
enum SyncStatus {
  /// Aucune synchro en cours, pas encore d'action.
  idle,

  /// Push/pull en cours.
  syncing,

  /// Tout est synchronisé.
  synced,

  /// Pas de session Drive : on travaille en local.
  offline,

  /// La révision distante a divergé : choix utilisateur requis.
  conflict,

  /// Une erreur est survenue lors de la dernière synchro.
  error,
}

/// État immuable de synchronisation (pattern `copyWith` du projet).
class SyncState {
  final SyncStatus status;
  final DateTime? lastSyncedAt;

  /// Révision distante en cas de conflit (pour la résolution).
  final int? conflictRemoteRevision;

  /// Bibliothèque concernée par le dernier conflit de push.
  final int? conflictLibraryId;

  final String? message;

  /// Session Google expirée/révoquée : un OAuth interactif est requis. Flag
  /// dédié plutôt qu'une détection fragile sur le texte de [message]. Il n'est
  /// pas propagé par [copyWith] : toute nouvelle transition d'état le remet à
  /// false, seul [SyncController._onAuthError] le lève.
  final bool authExpired;

  const SyncState({
    this.status = SyncStatus.idle,
    this.lastSyncedAt,
    this.conflictRemoteRevision,
    this.conflictLibraryId,
    this.message,
    this.authExpired = false,
  });

  SyncState copyWith({
    SyncStatus? status,
    DateTime? lastSyncedAt,
    int? conflictRemoteRevision,
    int? conflictLibraryId,
    bool clearConflict = false,
    String? message,
    bool clearMessage = false,
    bool? authExpired,
  }) {
    return SyncState(
      status: status ?? this.status,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      conflictRemoteRevision: clearConflict
          ? null
          : (conflictRemoteRevision ?? this.conflictRemoteRevision),
      conflictLibraryId: clearConflict
          ? null
          : (conflictLibraryId ?? this.conflictLibraryId),
      message: clearMessage ? null : (message ?? this.message),
      authExpired: authExpired ?? false,
    );
  }
}

/// Orchestre la synchronisation d'une bibliothèque : push débouncé après
/// modification, pull au lancement, et résolution de conflit. S'appuie sur
/// [LibraryRepository] (aucune dépendance directe au SDK Google).
class SyncController extends ChangeNotifier {
  final LibraryRepository _repository;
  final Duration _debounce;

  /// Timers de push débouncé, avec la [Library] associée (pour pouvoir différer
  /// un push en attente quand on entre en Mode Spectacle).
  final Map<int, (Timer, Library)> _debounceTimers = {};
  SyncState _state = const SyncState();

  /// Timer de masquage de la pastille : après un push/pull réussi, revient à
  /// [SyncStatus.idle] (pastille masquée) après quelques secondes.
  Timer? _syncedDisplayTimer;

  /// Mode Spectacle : suspend les push automatiques pour éviter tout jank audio
  /// (export `VACUUM INTO` + upload) pendant les déclenchements live.
  bool _autoSyncPaused = false;

  /// Bibliothèques dont un push a été supprimé pendant la pause, à rejouer à la
  /// reprise. Indexé par `library.id` : un slot unique perdait tous les push
  /// sauf le dernier dès qu'il y avait plus d'une bibliothèque connectée, et
  /// les autres attendaient une prochaine mutation qui pouvait ne jamais venir.
  final Map<int, Library> _deferredPushLibraries = {};

  /// Bibliothèque en cours de push (pour mémoriser l'origine d'un conflit).
  Library? _pushInFlightLibrary;

  /// Vrai après [dispose]. Un push/pull dure plusieurs secondes (export
  /// `VACUUM INTO` + upload) et n'est pas annulable : sans cette garde, son
  /// retour notifie un ChangeNotifier déjà détruit (fermeture de l'écran ou de
  /// l'app en pleine synchro).
  bool _disposed = false;

  /// Appelé après chaque merge de snapshot Drive réussi (PullStaged).
  /// Permet au sampler de recharger ses boards sans redémarrage.
  VoidCallback? onLibraryMerged;

  SyncController(
    this._repository, {
    Duration debounce = const Duration(seconds: 5),
  }) : _debounce = debounce;

  SyncState get state => _state;

  void _set(SyncState next) {
    if (_disposed) return;
    _syncedDisplayTimer?.cancel();
    _syncedDisplayTimer = null;
    _state = next;
    notifyListeners();
    // Après un push/pull réussi : masquer la pastille au bout de 8 s.
    // Le statut error/conflict/offline reste affiché jusqu'à résolution.
    if (next.status == SyncStatus.synced) {
      _syncedDisplayTimer = Timer(const Duration(seconds: 8), () {
        _syncedDisplayTimer = null;
        if (_state.status == SyncStatus.synced) {
          _state = _state.copyWith(status: SyncStatus.idle);
          notifyListeners();
        }
      });
    }
  }

  /// Suspend les push automatiques (entrée en Mode Spectacle). Annule les push
  /// débouncés en attente ; ils seront rejoués à la reprise.
  void pauseAutoSync() {
    if (_autoSyncPaused) return;
    _autoSyncPaused = true;
    for (final entry in _debounceTimers.values) {
      entry.$1.cancel();
      _deferredPushLibraries[entry.$2.id] = entry.$2; // à rejouer à la reprise
    }
    _debounceTimers.clear();
  }

  /// Reprend les push automatiques (sortie du Mode Spectacle) et rejoue le push
  /// éventuellement supprimé pendant la pause.
  void resumeAutoSync() {
    if (!_autoSyncPaused) return;
    _autoSyncPaused = false;
    final deferred = List<Library>.from(_deferredPushLibraries.values);
    _deferredPushLibraries.clear();
    for (final library in deferred) {
      schedulePush(library);
    }
  }

  /// Planifie un push après une période d'inactivité (anti-rebond). Appelé à
  /// chaque modification de la bibliothèque (tags, pads, settings…).
  void schedulePush(Library library) {
    // En Mode Spectacle : on mémorise le besoin de push sans rien lancer.
    if (_autoSyncPaused) {
      _deferredPushLibraries[library.id] = library;
      return;
    }
    _debounceTimers[library.id]?.$1.cancel();
    _debounceTimers[library.id] = (
      Timer(_debounce, () {
        _debounceTimers.remove(library.id);
        unawaited(syncNow(library));
      }),
      library,
    );
  }

  /// Pousse immédiatement l'état local vers Drive.
  Future<void> syncNow(Library library) async {
    // Un push immédiat supersède un push débouncé éventuellement en attente.
    _debounceTimers[library.id]?.$1.cancel();
    _debounceTimers.remove(library.id);
    if (!await _ensureConnected()) {
      _set(_state.copyWith(status: SyncStatus.offline));
      return;
    }

    _pushInFlightLibrary = library;
    _set(_state.copyWith(status: SyncStatus.syncing, clearMessage: true));
    try {
      final outcome = await _repository.pushLibrary(library);
      if (outcome is PushConflict) {
        // Fusion intelligente : un autre appareil a poussé entre-temps. Plutôt
        // que d'écraser (ou de bloquer l'utilisateur sur un dialogue), on tire
        // et fusionne le distant (fusion board-par-board non destructive) puis
        // on repousse l'union. Les deux jeux de modifications sont préservés.
        await _mergeAndRepush(library);
      } else {
        _applyPushOutcome(outcome);
      }
    } on DriveAuthException {
      await _onAuthError();
    } catch (e) {
      _set(_state.copyWith(status: SyncStatus.error, message: e.toString()));
    } finally {
      _pushInFlightLibrary = null;
    }
  }

  /// Résout un conflit de push automatiquement : pull-fusion du distant puis
  /// repush de l'union. Si un nouveau conflit surgit (course rare : un 3e push
  /// distant pendant la fusion), on retombe sur la résolution manuelle (UI).
  Future<void> _mergeAndRepush(Library library) async {
    await _repository.pullLibrary(library);
    onLibraryMerged?.call();
    final fresh = await _repository.getLibraryById(library.id) ?? library;
    final outcome = await _repository.pushLibrary(fresh);
    _applyPushOutcome(outcome);
  }

  /// Signale l'état hors-ligne : une bibliothèque Drive est configurée mais
  /// aucune session n'a pu être restaurée. Permet à la pastille ambiante
  /// d'indiquer le travail local au lieu de rester muette (statut `idle`).
  void markOffline() {
    if (_state.status == SyncStatus.offline) return;
    _set(_state.copyWith(status: SyncStatus.offline));
  }

  /// Au lancement : reconnexion silencieuse puis pull/fusion du snapshot distant.
  Future<void> pullForLaunch(Library library) async {
    if (!await _ensureConnected()) {
      _set(_state.copyWith(status: SyncStatus.offline));
      return;
    }

    _set(_state.copyWith(status: SyncStatus.syncing, clearMessage: true));
    try {
      final outcome = await _repository.pullLibrary(library);
      switch (outcome) {
        case PullStaged():
          _set(_state.copyWith(
            status: SyncStatus.synced,
            lastSyncedAt: DateTime.now(),
          ));
          onLibraryMerged?.call();
        case PullUpToDate():
          _set(_state.copyWith(
            status: SyncStatus.synced,
            lastSyncedAt: DateTime.now(),
          ));
        case PullNoRemoteSnapshot():
          _applyNoRemoteSnapshot(library);
      }
    } on DriveAuthException {
      await _onAuthError();
    } catch (e) {
      _set(_state.copyWith(status: SyncStatus.error, message: e.toString()));
    }
  }

  /// Résolution de conflit — garder la version locale (écrase le distant).
  Future<void> keepLocal(Library library) async {
    final remoteRevision = _state.conflictRemoteRevision;
    if (remoteRevision == null) return;

    _pushInFlightLibrary = library;
    _set(_state.copyWith(status: SyncStatus.syncing, clearMessage: true));
    try {
      final outcome = await _repository.pushLibrary(
        library,
        overrideKnownRevision: remoteRevision,
      );
      _applyPushOutcome(outcome);
    } on DriveAuthException {
      await _onAuthError();
    } catch (e) {
      _set(_state.copyWith(status: SyncStatus.error, message: e.toString()));
    } finally {
      _pushInFlightLibrary = null;
    }
  }

  /// Résolution de conflit — prendre la version distante (tirée et fusionnée en direct).
  Future<void> takeRemote(Library library) async {
    _set(_state.copyWith(status: SyncStatus.syncing, clearMessage: true));
    try {
      final outcome = await _repository.pullLibrary(library);
      switch (outcome) {
        case PullStaged():
          _set(_state.copyWith(
            status: SyncStatus.synced,
            lastSyncedAt: DateTime.now(),
            clearConflict: true,
          ));
          onLibraryMerged?.call();
        case PullUpToDate():
          _set(_state.copyWith(
            status: SyncStatus.synced,
            lastSyncedAt: DateTime.now(),
            clearConflict: true,
          ));
        case PullNoRemoteSnapshot():
          // Résolution de conflit « prendre le distant » alors qu'il n'y a rien
          // à prendre : incohérent, on le signale au lieu de clore le conflit.
          _set(_state.copyWith(
            status: SyncStatus.error,
            message: 'Sauvegarde distante introuvable : impossible de prendre '
                'la version distante.',
          ));
      }
    } on DriveAuthException {
      await _onAuthError();
    } catch (e) {
      _set(_state.copyWith(status: SyncStatus.error, message: e.toString()));
    }
  }

  /// Aucun snapshot distant à comparer.
  ///
  /// Jamais « Synchronisé » : ce statut ferait croire à une sauvegarde distante.
  /// Une bibliothèque encore jamais poussée n'a simplement rien à tirer (idle) ;
  /// une bibliothèque qui porte déjà une révision a vu son `.stagecue` vidé ou
  /// supprimé — l'utilisateur doit le savoir, ses scènes ne vivent plus qu'en
  /// local.
  void _applyNoRemoteSnapshot(Library library) {
    if (library.lastSyncedRevision <= 0) {
      _set(_state.copyWith(status: SyncStatus.idle, clearMessage: true));
      return;
    }
    _set(_state.copyWith(
      status: SyncStatus.error,
      message: 'Sauvegarde distante introuvable — vos scènes ne sont plus '
          'que locales. Lancez une synchro pour la recréer.',
    ));
  }

  void _applyPushOutcome(PushOutcome outcome) {
    switch (outcome) {
      case PushSuccess():
        _set(_state.copyWith(
          status: SyncStatus.synced,
          lastSyncedAt: DateTime.now(),
          clearConflict: true,
        ));
      case PushConflict(:final remote):
        _set(_state.copyWith(
          status: SyncStatus.conflict,
          conflictRemoteRevision: remote.revision,
          conflictLibraryId: _pushInFlightLibrary?.id,
        ));
    }
  }

  Future<bool> _ensureConnected() async {
    if (_repository.requiresInteractiveReconnect) {
      return false;
    }
    return _repository.reconnectSilently();
  }

  /// Session Google expirée ou révoquée : libère le client et signale l'état.
  Future<void> handleAuthFailure() => _onAuthError();

  /// Efface l'état hors-ligne après une reconnexion OAuth réussie.
  void clearAuthOfflineState() {
    if (_state.status != SyncStatus.offline && !_state.authExpired) {
      return;
    }
    _set(_state.copyWith(status: SyncStatus.idle, clearMessage: true));
  }

  /// Libère la session HTTP et passe en offline sans effacer les tokens Google.
  Future<void> _onAuthError() async {
    await _repository.invalidateAuthSession();
    _set(_state.copyWith(
      status: SyncStatus.offline,
      clearConflict: true,
      message: 'Session Google expirée — reconnectez-vous dans les réglages.',
      authExpired: true,
    ));
  }

  @override
  void dispose() {
    _disposed = true;
    _syncedDisplayTimer?.cancel();
    for (final entry in _debounceTimers.values) {
      entry.$1.cancel();
    }
    _debounceTimers.clear();
    onLibraryMerged = null;
    super.dispose();
  }
}
