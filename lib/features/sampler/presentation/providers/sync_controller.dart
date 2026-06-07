import 'dart:async';

import 'package:flutter/foundation.dart';

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

  final String? message;

  const SyncState({
    this.status = SyncStatus.idle,
    this.lastSyncedAt,
    this.conflictRemoteRevision,
    this.message,
  });

  SyncState copyWith({
    SyncStatus? status,
    DateTime? lastSyncedAt,
    int? conflictRemoteRevision,
    bool clearConflict = false,
    String? message,
    bool clearMessage = false,
  }) {
    return SyncState(
      status: status ?? this.status,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      conflictRemoteRevision: clearConflict
          ? null
          : (conflictRemoteRevision ?? this.conflictRemoteRevision),
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

/// Orchestre la synchronisation d'une bibliothèque : push débouncé après
/// modification, pull au lancement, et résolution de conflit. S'appuie sur
/// [LibraryRepository] (aucune dépendance directe au SDK Google).
class SyncController extends ChangeNotifier {
  final LibraryRepository _repository;
  final Duration _debounce;

  final Map<int, Timer> _debounceTimers = {};
  SyncState _state = const SyncState();

  SyncController(
    this._repository, {
    Duration debounce = const Duration(seconds: 5),
  }) : _debounce = debounce;

  SyncState get state => _state;

  void _set(SyncState next) {
    _state = next;
    notifyListeners();
  }

  /// Planifie un push après une période d'inactivité (anti-rebond). Appelé à
  /// chaque modification de la bibliothèque (tags, pads, settings…).
  void schedulePush(Library library) {
    _debounceTimers[library.id]?.cancel();
    _debounceTimers[library.id] = Timer(_debounce, () {
      _debounceTimers.remove(library.id);
      unawaited(syncNow(library));
    });
  }

  /// Pousse immédiatement l'état local vers Drive.
  Future<void> syncNow(Library library) async {
    // Un push immédiat supersède un push débouncé éventuellement en attente.
    _debounceTimers[library.id]?.cancel();
    _debounceTimers.remove(library.id);
    if (!await _ensureConnected()) {
      _set(_state.copyWith(status: SyncStatus.offline));
      return;
    }

    _set(_state.copyWith(status: SyncStatus.syncing, clearMessage: true));
    try {
      final outcome = await _repository.pushLibrary(library);
      _applyPushOutcome(outcome);
    } catch (e) {
      _set(_state.copyWith(status: SyncStatus.error, message: e.toString()));
    }
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
        case PullUpToDate():
          _set(_state.copyWith(
            status: SyncStatus.synced,
            lastSyncedAt: DateTime.now(),
          ));
      }
    } catch (e) {
      _set(_state.copyWith(status: SyncStatus.error, message: e.toString()));
    }
  }

  /// Résolution de conflit — garder la version locale (écrase le distant).
  Future<void> keepLocal(Library library) async {
    final remoteRevision = _state.conflictRemoteRevision;
    if (remoteRevision == null) return;

    _set(_state.copyWith(status: SyncStatus.syncing, clearMessage: true));
    try {
      final outcome = await _repository.pushLibrary(
        library,
        overrideKnownRevision: remoteRevision,
      );
      _applyPushOutcome(outcome);
    } catch (e) {
      _set(_state.copyWith(status: SyncStatus.error, message: e.toString()));
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
        case PullUpToDate():
          _set(_state.copyWith(
            status: SyncStatus.synced,
            lastSyncedAt: DateTime.now(),
            clearConflict: true,
          ));
      }
    } catch (e) {
      _set(_state.copyWith(status: SyncStatus.error, message: e.toString()));
    }
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
        ));
    }
  }

  Future<bool> _ensureConnected() async {
    if (_repository.isConnected) return true;
    return _repository.reconnectSilently();
  }

  @override
  void dispose() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    super.dispose();
  }
}
