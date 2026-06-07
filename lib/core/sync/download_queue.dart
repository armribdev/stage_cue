import 'dart:async';

/// Levée dans le future d'une tâche retirée de la file avant son démarrage
/// (annulation coopérative, ex. changement de plateau).
class DownloadCancelledException implements Exception {
  const DownloadCancelledException();
  @override
  String toString() => 'DownloadCancelledException';
}

/// File d'exécution à **priorité** et **concurrence bornée**, avec
/// **déduplication par clé**. Générique et sans dépendance (audio, Drift,
/// réseau) → entièrement testable isolément.
///
/// Conçue pour orchestrer les téléchargements de pads (refonte UX P2) :
/// - un tap utilisateur double un prefetch en attente (priorité plus haute) ;
/// - au plus [maxConcurrent] tâches tournent en parallèle (ne pas marteler
///   l'API Drive) ;
/// - changer de plateau annule la file en attente sans couper les tâches déjà
///   démarrées (qui finissent en cache, donc sans gâchis).
///
/// FIFO à priorité égale (l'ordre d'`enqueue` est préservé).
class DownloadQueue {
  final int maxConcurrent;

  DownloadQueue({this.maxConcurrent = 2})
      : assert(maxConcurrent >= 1, 'maxConcurrent doit être ≥ 1');

  final List<_QueuedTask> _pending = [];
  final Map<Object, _QueuedTask> _byKey = {};
  int _running = 0;
  int _seq = 0;
  bool _disposed = false;

  /// Tâches en attente (pas encore démarrées).
  int get pendingCount => _pending.length;

  /// Tâches en cours d'exécution.
  int get runningCount => _running;

  /// Met une tâche en file. Si une tâche de même [key] est déjà en file ou en
  /// cours, retourne son future existant (déduplication) et **relève** sa
  /// priorité si [priority] est plus haute et qu'elle n'a pas encore démarré.
  Future<T> enqueue<T>({
    required Object key,
    required int priority,
    required Future<T> Function() task,
  }) {
    if (_disposed) {
      return Future<T>.error(StateError('DownloadQueue déjà disposée'));
    }

    final existing = _byKey[key];
    if (existing != null) {
      if (!existing.started && priority > existing.priority) {
        existing.priority = priority;
        _sortPending();
      }
      return existing.completer.future.then((value) => value as T);
    }

    final queued = _QueuedTask(
      key: key,
      priority: priority,
      seq: _seq++,
      run: task,
    );
    _byKey[key] = queued;
    _pending.add(queued);
    _sortPending();
    _pump();
    return queued.completer.future.then((value) => value as T);
  }

  /// Annule les tâches **en attente** dont (clé, priorité) satisfont [test].
  /// Les tâches déjà démarrées ne sont pas interrompues. Les futures annulés
  /// échouent avec [DownloadCancelledException].
  void cancelQueued(bool Function(Object key, int priority) test) {
    final cancelled = <_QueuedTask>[];
    _pending.removeWhere((t) {
      if (test(t.key, t.priority)) {
        cancelled.add(t);
        return true;
      }
      return false;
    });
    for (final t in cancelled) {
      _byKey.remove(t.key);
      if (!t.completer.isCompleted) {
        t.completer.completeError(const DownloadCancelledException());
      }
    }
  }

  void _sortPending() {
    // Priorité décroissante, puis FIFO (seq croissant) à priorité égale.
    _pending.sort((a, b) {
      final byPriority = b.priority.compareTo(a.priority);
      return byPriority != 0 ? byPriority : a.seq.compareTo(b.seq);
    });
  }

  void _pump() {
    while (_running < maxConcurrent && _pending.isNotEmpty) {
      final task = _pending.removeAt(0);
      task.started = true;
      _running++;
      unawaited(_run(task));
    }
  }

  Future<void> _run(_QueuedTask task) async {
    try {
      final result = await task.run();
      if (!task.completer.isCompleted) task.completer.complete(result);
    } catch (e, st) {
      if (!task.completer.isCompleted) task.completer.completeError(e, st);
    } finally {
      _running--;
      _byKey.remove(task.key);
      if (!_disposed) _pump();
    }
  }

  /// Annule toutes les tâches en attente et empêche tout nouvel enqueue. Les
  /// tâches déjà démarrées finissent normalement.
  void dispose() {
    _disposed = true;
    final pending = List<_QueuedTask>.from(_pending);
    _pending.clear();
    for (final t in pending) {
      _byKey.remove(t.key);
      if (!t.completer.isCompleted) {
        t.completer.completeError(const DownloadCancelledException());
      }
    }
  }
}

class _QueuedTask {
  final Object key;
  int priority;
  final int seq;
  final Future<dynamic> Function() run;
  final Completer<dynamic> completer = Completer<dynamic>();
  bool started = false;

  _QueuedTask({
    required this.key,
    required this.priority,
    required this.seq,
    required this.run,
  });
}
