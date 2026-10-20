import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/audio/audio_load_log.dart';
import 'package:stage_cue/core/logging/app_log.dart';
import 'package:stage_cue/core/logging/log_sink.dart';
import 'package:stage_cue/core/sync/download_queue.dart';
import 'package:stage_cue/core/sync/sync_log.dart';
import 'package:stage_cue/core/update/update_log.dart';

/// Vérifie que les classes de log alimentent bien le journal fichier, au bon
/// niveau et au bon canal, et que les événements ajoutés pour le diagnostic
/// post-incident (ADR 0025) se comportent comme documenté.
void main() {
  late Directory dir;

  Future<String> flushed() async {
    await LogSink.flush();
    return File(p.join(dir.path, LogSink.currentFileName)).readAsStringSync();
  }

  setUp(() async {
    await LogSink.resetForTest();
    dir = await Directory.systemTemp.createTemp('stage_cue_log_events');
    await LogSink.init(directory: dir, flushInterval: null);
    LogSink.writeSessionHeader(const ['test']);
  });

  tearDown(() async {
    await LogSink.resetForTest();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test(
    'les trois classes de log alimentent le fichier avec leur canal',
    () async {
      SyncLog.info('indexé');
      AudioLoadLog.warn('illisible');
      UpdateLog.info('à jour');
      AppLog.info('démarré');
      final out = await flushed();
      expect(out, contains(RegExp(r'INFO  Sync   indexé')));
      expect(out, contains(RegExp(r'WARN  Audio  illisible')));
      expect(out, contains(RegExp(r'INFO  Update à jour')));
      expect(out, contains(RegExp(r'INFO  App    démarré')));
    },
  );

  test(
    'les traces ne vont au fichier que si leur --dart-define est actif',
    () async {
      // Dans cette suite, STAGE_CUE_*_TRACE n'est pas défini.
      expect(SyncLog.traceEnabled, isFalse);
      expect(AudioLoadLog.traceEnabled, isFalse);
      SyncLog.trace('détail fichier');
      AudioLoadLog.trace('détail audio');
      final out = await flushed();
      expect(out, isNot(contains('détail fichier')));
      expect(out, isNot(contains('détail audio')));
    },
  );

  group('préchargement', () {
    test('bilan en info quand tout est disponible', () async {
      AudioLoadLog.preloadFinished(
        boardId: 3,
        padCount: 12,
        elapsed: const Duration(milliseconds: 840),
      );
      expect(
        await flushed(),
        contains(
          'INFO  Audio  Plateau #3 préchargé : 12 pad(s), 0 indisponible(s), 840 ms.',
        ),
      );
    });

    test('warn dès qu\'un pad est indisponible', () async {
      AudioLoadLog.preloadFinished(
        boardId: 3,
        padCount: 12,
        unavailableCount: 2,
      );
      expect(await flushed(), contains('WARN  Audio  Plateau #3'));
    });

    test('started et cancelled restent muets sans trace', () async {
      AudioLoadLog.preloadStarted(boardId: 1, padCount: 4);
      AudioLoadLog.preloadCancelled(boardId: 1);
      expect(await flushed(), isNot(contains('Plateau #1')));
    });
  });

  group('échec de déclenchement', () {
    test('warn avec pad, libellé et raison', () async {
      AudioLoadLog.padTriggerFailed(
        padId: 41,
        padLabel: 'Applaudissements',
        reason: 'fichier introuvable',
      );
      expect(
        await flushed(),
        contains(
          'WARN  Audio  Pad « Applaudissements » (id=41) n\'a rien joué : '
          'fichier introuvable',
        ),
      );
    });

    test(
      'un même échec répété dans la fenêtre n\'écrit qu\'une ligne',
      () async {
        for (var i = 0; i < 5; i++) {
          AudioLoadLog.padTriggerFailed(
            padId: 77,
            padLabel: 'Pluie',
            reason: 'pad sans son',
          );
        }
        AudioLoadLog.padTriggerFailed(
          padId: 77,
          padLabel: 'Pluie',
          reason: 'fichier introuvable',
        );
        final out = await flushed();
        expect('pad sans son'.allMatches(out).length, 1);
        expect(out, contains('fichier introuvable'));
      },
    );
  });

  group('éviction du cache', () {
    test('info quand le garde-fou est rétabli', () async {
      SyncLog.evictionPass(
        library: 'Lib',
        evicted: 12,
        freedBytes: 300 * 1024 * 1024,
        failed: 0,
        pinnedProtected: 40,
        freeBefore: 1800 * 1024 * 1024,
        freeAfter: 2100 * 1024 * 1024,
        minFreeBytes: 2000 * 1024 * 1024,
      );
      final out = await flushed();
      expect(
        out,
        contains('INFO  Sync   Lib : éviction du cache — 12 fichier(s)'),
      );
      expect(out, contains('40 épinglé(s) protégé(s)'));
    });

    test('warn quand le garde-fou disque n\'est pas atteint', () async {
      SyncLog.evictionPass(
        library: 'Lib',
        evicted: 0,
        freedBytes: 0,
        failed: 0,
        pinnedProtected: 200,
        freeBefore: 500 * 1024 * 1024,
        freeAfter: 500 * 1024 * 1024,
        minFreeBytes: 2000 * 1024 * 1024,
      );
      final out = await flushed();
      expect(out, contains('WARN  Sync   Lib : éviction'));
      expect(out, contains('Garde-fou disque'));
    });
  });

  group('file de téléchargement', () {
    test('un bilan à la vidange, avec réussis et échecs', () async {
      final summaries = <DownloadQueueSummary>[];
      final queue = DownloadQueue(maxConcurrent: 2, onDrained: summaries.add);

      final ok = queue.enqueue<int>(key: 'a', priority: 1, task: () async => 1);
      final ko = queue.enqueue<int>(
        key: 'b',
        priority: 1,
        task: () async => throw StateError('réseau'),
      );
      await ok;
      await expectLater(ko, throwsStateError);
      await Future<void>.delayed(Duration.zero);

      expect(summaries, hasLength(1));
      expect(summaries.single.succeeded, 1);
      expect(summaries.single.failed, 1);
      expect(summaries.single.cancelled, 0);
    });

    test(
      'un second lot produit un second bilan, compteurs remis à zéro',
      () async {
        final summaries = <DownloadQueueSummary>[];
        final queue = DownloadQueue(onDrained: summaries.add);
        await queue.enqueue<int>(key: 'a', priority: 1, task: () async => 1);
        await Future<void>.delayed(Duration.zero);
        await queue.enqueue<int>(key: 'b', priority: 1, task: () async => 2);
        await Future<void>.delayed(Duration.zero);
        expect(summaries, hasLength(2));
        expect(summaries.last.succeeded, 1);
      },
    );

    test('les tâches annulées en attente sont comptées', () async {
      final summaries = <DownloadQueueSummary>[];
      final queue = DownloadQueue(maxConcurrent: 1, onDrained: summaries.add);
      final gate = Completer<void>();
      final running = queue.enqueue<void>(
        key: 'run',
        priority: 1,
        task: () => gate.future,
      );
      final waiting = queue.enqueue<void>(
        key: 'wait',
        priority: 1,
        task: () async {},
      );
      unawaited(waiting.catchError((_) {}));
      queue.cancelQueued((key, priority) => key == 'wait');
      gate.complete();
      await running;
      await Future<void>.delayed(Duration.zero);
      expect(summaries.single.cancelled, 1);
      expect(summaries.single.succeeded, 1);
    });

    test('un callback qui lève ne perturbe pas la file', () async {
      final queue = DownloadQueue(onDrained: (_) => throw StateError('log'));
      expect(
        await queue.enqueue<int>(key: 'a', priority: 1, task: () async => 7),
        7,
      );
    });
  });

  group('authentification Drive', () {
    test('aucune ligne ne porte jeton ou e-mail', () async {
      SyncLog.driveSignedIn();
      SyncLog.driveSignedOut();
      SyncLog.driveSignInFailed(
        Exception('invalid_grant pour moi@example.com ya29.a0AfH6SMBsecret'),
      );
      final out = await flushed();
      expect(out, contains('Drive : connexion réussie.'));
      expect(out, contains('Drive : déconnexion.'));
      expect(out, isNot(contains('moi@example.com')));
      expect(out, isNot(contains('a0AfH6SMBsecret')));
    });

    test('un jeton rejeté en rafale n\'écrit qu\'une ligne', () async {
      for (var i = 0; i < 10; i++) {
        SyncLog.driveAuthRejected();
      }
      final out = await flushed();
      expect('jeton rejeté'.allMatches(out).length, lessThanOrEqualTo(1));
    });
  });
}
