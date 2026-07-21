import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/sync/download_queue.dart';

/// Tâche contrôlable : se résout quand on appelle [release].
class _Gate {
  final completer = Completer<int>();
  var started = false;
  Future<int> run() {
    started = true;
    return completer.future;
  }

  void release([int value = 0]) => completer.complete(value);
}

void main() {
  group('DownloadQueue', () {
    test('borne la concurrence à maxConcurrent', () async {
      final queue = DownloadQueue(maxConcurrent: 2);
      final gates = List.generate(4, (_) => _Gate());

      for (var i = 0; i < gates.length; i++) {
        queue.enqueue(key: i, priority: 0, task: gates[i].run);
      }
      await Future<void>.delayed(Duration.zero);

      expect(queue.runningCount, 2);
      expect(gates[0].started && gates[1].started, isTrue);
      expect(gates[2].started || gates[3].started, isFalse);

      gates[0].release();
      await Future<void>.delayed(Duration.zero);
      expect(gates[2].started, isTrue); // le slot libéré démarre la suivante
    });

    test('exécute la plus haute priorité d\'abord', () async {
      final queue = DownloadQueue(maxConcurrent: 1);
      final order = <String>[];
      final blocker = _Gate();

      // Occupe l'unique worker.
      queue.enqueue(key: 'blocker', priority: 0, task: blocker.run);
      await Future<void>.delayed(Duration.zero);

      final fLow = queue.enqueue<String>(key: 'low', priority: 1, task: () async {
        order.add('low');
        return 'low';
      });
      queue.enqueue<String>(key: 'high', priority: 100, task: () async {
        order.add('high');
        return 'high';
      });

      blocker.release();
      await fLow; // 'low' est la dernière à tourner

      expect(order, ['high', 'low']);
    });

    test('déduplique par clé et relève la priorité (tap double un prefetch)',
        () async {
      final queue = DownloadQueue(maxConcurrent: 1);
      final order = <String>[];
      final blocker = _Gate();
      queue.enqueue(key: 'blocker', priority: 0, task: blocker.run);
      await Future<void>.delayed(Duration.zero);

      final fa = queue.enqueue<String>(key: 'a', priority: 1, task: () async {
        order.add('a');
        return 'a';
      });
      final fb1 = queue.enqueue<String>(key: 'b', priority: 1, task: () async {
        order.add('b');
        return 'b';
      });
      // Même clé 'b' relevée en priorité haute : passe avant 'a', une seule fois.
      final fb2 = queue.enqueue<String>(key: 'b', priority: 100, task: () async {
        order.add('B!');
        return 'B!';
      });

      blocker.release();
      await fa; // 'a' tourne en dernier

      expect(order, ['b', 'a']); // 'b' exécutée une fois, avant 'a'
      expect(await fb1, 'b');
      expect(await fb2, 'b'); // même future que fb1 (dédup) → 'b', pas 'B!'
    });

    test('partage le même future pour une clé en cours', () async {
      final queue = DownloadQueue(maxConcurrent: 1);
      final gate = _Gate();
      final f1 = queue.enqueue<int>(key: 'x', priority: 0, task: gate.run);
      await Future<void>.delayed(Duration.zero); // démarre
      final f2 = queue.enqueue<int>(key: 'x', priority: 0, task: () async => 999);

      gate.release(42);
      expect(await f1, 42);
      expect(await f2, 42); // dédup : la 2e tâche n'a pas tourné
    });

    test('inFlight : null si aucune tâche pour la clé', () {
      final queue = DownloadQueue();
      expect(queue.inFlight('absente'), isNull);
    });

    test('inFlight : suit une tâche en cours jusqu\'à son achèvement', () async {
      final queue = DownloadQueue();
      final gate = _Gate();
      unawaited(queue.enqueue(key: 'pad-1', priority: 0, task: gate.run));

      final pending = queue.inFlight('pad-1');
      expect(pending, isNotNull);

      var done = false;
      unawaited(pending!.then((_) => done = true));
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);

      gate.release();
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
      // Achevée : la clé est libérée, une portée plus large peut enfiler.
      expect(queue.inFlight('pad-1'), isNull);
    });

    test('inFlight : une tâche annulée libère quand même l\'attente', () async {
      final queue = DownloadQueue(maxConcurrent: 1);
      final blocking = _Gate();
      unawaited(queue.enqueue(key: 'autre', priority: 0, task: blocking.run));
      // Reste EN ATTENTE derrière la précédente, donc annulable.
      unawaited(
        queue.enqueue(key: 'pad-1', priority: 0, task: () async => 1)
            .catchError((_) => 0),
      );

      final pending = queue.inFlight('pad-1');
      expect(pending, isNotNull);

      Object? error;
      unawaited(pending!.catchError((Object e) => error = e));
      queue.cancelQueued((key, _) => key == 'pad-1');
      await Future<void>.delayed(Duration.zero);

      // L'attente se dénoue par une erreur, que l'appelant neutralise pour
      // reprendre : elle ne doit jamais rester pendante.
      expect(error, isA<DownloadCancelledException>());
      blocking.release();
    });

    test('cancelQueued retire les tâches en attente selon (clé, priorité)',
        () async {
      final queue = DownloadQueue(maxConcurrent: 1);
      final ran = <String>[];
      final blocker = _Gate();
      queue.enqueue(key: 'blocker', priority: 0, task: blocker.run);
      await Future<void>.delayed(Duration.zero);

      final fLow = queue.enqueue<String>(key: 'low', priority: 10, task: () async {
        ran.add('low');
        return 'low';
      });
      final fHigh =
          queue.enqueue<String>(key: 'high', priority: 100, task: () async {
        ran.add('high');
        return 'high';
      });

      // Annule le prefetch (priorité basse), garde le tap.
      queue.cancelQueued((key, priority) => priority <= 10);
      await expectLater(
          fLow, throwsA(isA<DownloadCancelledException>()));

      blocker.release();
      await fHigh;

      expect(ran, ['high']); // 'low' annulée, jamais exécutée
    });

    test('cancelQueued ne touche pas une tâche déjà démarrée', () async {
      final queue = DownloadQueue(maxConcurrent: 1);
      final gate = _Gate();
      final future = queue.enqueue<int>(key: 'running', priority: 0, task: gate.run);
      await Future<void>.delayed(Duration.zero); // démarrée

      queue.cancelQueued((key, priority) => true);
      gate.release(7);

      expect(await future, 7); // non interrompue
    });

    test('dispose annule la file en attente', () async {
      final queue = DownloadQueue(maxConcurrent: 1);
      final blocker = _Gate();
      queue.enqueue(key: 'blocker', priority: 0, task: blocker.run);
      await Future<void>.delayed(Duration.zero);
      final pendingFuture =
          queue.enqueue<int>(key: 'pending', priority: 0, task: () async => 1);

      queue.dispose();

      await expectLater(
          pendingFuture, throwsA(isA<DownloadCancelledException>()));
    });
  });
}
