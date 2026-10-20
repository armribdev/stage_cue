import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/logging/log_export.dart';
import 'package:stage_cue/core/logging/log_redactor.dart';
import 'package:stage_cue/core/logging/log_session.dart';
import 'package:stage_cue/core/logging/log_sink.dart';

void main() {
  late Directory dir;
  late DateTime now;

  Future<void> start({
    LogFileWriter? writer,
    int maxFileBytes = LogSink.defaultMaxFileBytes,
    bool withHeader = true,
  }) async {
    await LogSink.init(
      directory: dir,
      clock: () => now,
      writer: writer,
      maxFileBytes: maxFileBytes,
      flushInterval: null,
    );
    if (withHeader) LogSink.writeSessionHeader(const ['Version : test']);
  }

  String readCurrent() =>
      File(p.join(dir.path, LogSink.currentFileName)).readAsStringSync();

  setUp(() async {
    await LogSink.resetForTest();
    dir = await Directory.systemTemp.createTemp('stage_cue_log_test');
    now = DateTime(2026, 10, 19, 21, 4, 11, 482);
  });

  tearDown(() async {
    await LogSink.resetForTest();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  group('format', () {
    test(
      'une ligne par événement, horodatage local avec millisecondes',
      () async {
        await start();
        LogSink.log('Audio', LogLevel.warn, 'message');
        await LogSink.flush();
        expect(
          readCurrent(),
          contains('2026-10-19T21:04:11.482 WARN  Audio  message\n'),
        );
      },
    );

    test('la stack trace est indentée sous la ligne', () async {
      await start();
      LogSink.log(
        'App',
        LogLevel.severe,
        'boum',
        error: StateError('x'),
        stackTrace: StackTrace.fromString('#0 a\n#1 b'),
      );
      await LogSink.flush();
      expect(
        readCurrent(),
        contains('ERROR App    boum | Bad state: x\n    #0 a\n    #1 b'),
      );
    });

    test('l\'en-tête de session est la première chose écrite', () async {
      LogSink.log('App', LogLevel.info, 'avant init');
      await start(withHeader: false);
      LogSink.log('App', LogLevel.info, 'après init');
      LogSink.writeSessionHeader(const ['Version : 1.2.3']);
      await LogSink.flush();
      final lines = readCurrent().trim().split('\n');
      expect(lines[0], contains('Session Version : 1.2.3'));
      expect(lines[1], contains('avant init'));
      expect(lines[2], contains('après init'));
    });

    test('rien n\'est écrit tant que l\'en-tête n\'est pas posé', () async {
      await start(withHeader: false);
      LogSink.log('App', LogLevel.info, 'en attente');
      await LogSink.flush();
      expect(
        File(p.join(dir.path, LogSink.currentFileName)).existsSync(),
        isFalse,
      );
    });

    test(
      'un severe précoce force l\'écriture sans attendre l\'en-tête',
      () async {
        await start(withHeader: false);
        LogSink.log('App', LogLevel.severe, 'crash précoce');
        await LogSink.flush();
        expect(readCurrent(), contains('crash précoce'));
        expect(readCurrent(), contains('en-tête non encore disponible'));
      },
    );
  });

  group('flush', () {
    test('un severe est écrit sans appel explicite à flush', () async {
      await start();
      LogSink.log('App', LogLevel.severe, 'incident');
      // Aucun appel à flush() : c'est log() lui-même qui lance l'écriture.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(readCurrent(), contains('incident'));
    });

    test('un info reste en buffer jusqu\'au flush', () async {
      await start();
      await LogSink.flush();
      LogSink.log('App', LogLevel.info, 'tamponné');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(readCurrent(), isNot(contains('tamponné')));
      await LogSink.flush();
      expect(readCurrent(), contains('tamponné'));
    });
  });

  group('rotation', () {
    test(
      'au démarrage : courant → .1 → .2, la plus ancienne disparaît',
      () async {
        for (final marker in ['A', 'B', 'C', 'D']) {
          File(
            p.join(dir.path, 'stage-cue.log'),
          ).writeAsStringSync('$marker\n');
          await start();
          await LogSink.flush();
          await LogSink.resetForTest();
        }
        final names = dir.listSync().map((e) => p.basename(e.path)).toSet();
        expect(
          names,
          containsAll(['stage-cue.log', 'stage-cue.1.log', 'stage-cue.2.log']),
        );
        expect(names, isNot(contains('stage-cue.3.log')));
      },
    );

    test(
      'au dépassement de taille, le fichier tourne et reste borné',
      () async {
        await start(maxFileBytes: 400);
        for (var i = 0; i < 30; i++) {
          LogSink.log('Audio', LogLevel.info, 'ligne numéro $i ${'x' * 40}');
          await LogSink.flush();
        }
        final files = LogSink.logFiles();
        expect(files.length, lessThanOrEqualTo(3));
        for (final f in files) {
          expect(f.lengthSync(), lessThan(400 + 200));
        }
        expect(readCurrent(), contains('ligne numéro 29'));
      },
    );
  });

  group('erreurs d\'écriture', () {
    test(
      'un disque en échec ne lève jamais et compte les lignes perdues',
      () async {
        await start(
          writer: (file, text) async =>
              throw const FileSystemException('disque plein'),
        );
        LogSink.log('App', LogLevel.info, 'a');
        LogSink.log('App', LogLevel.info, 'b');
        await expectLater(LogSink.flush(), completes);
        // En-tête (1) + 2 lignes.
        expect(LogSink.lostLines, 3);
      },
    );

    test('la perte est signalée à la prochaine écriture réussie', () async {
      var fail = true;
      await start(
        writer: (file, text) async {
          if (fail) throw const FileSystemException('disque plein');
          await file.writeAsString(text, mode: FileMode.append);
        },
      );
      LogSink.log('App', LogLevel.info, 'perdue');
      await LogSink.flush();
      fail = false;
      LogSink.log('App', LogLevel.info, 'sauvée');
      await LogSink.flush();
      final out = readCurrent();
      expect(out, contains('2 ligne(s) de journal perdue(s)'));
      expect(out, contains('sauvée'));
    });

    test('log() avant init ne lève pas', () {
      expect(
        () => LogSink.log('App', LogLevel.info, 'trop tôt'),
        returnsNormally,
      );
    });
  });

  group('confidentialité', () {
    test(
      'masque jetons OAuth et e-mails dans message, erreur et stack',
      () async {
        await start();
        LogSink.log(
          'Sync',
          LogLevel.severe,
          'échec avec ya29.a0AfH6SMBxyz_123-abc pour moi@example.com',
          error: Exception('Authorization: Bearer abc.def-ghi'),
          stackTrace: StackTrace.fromString(
            '#0 f (refresh_token=1//0gAbCdEfGhIjKlMnOpQrStUv)',
          ),
        );
        await LogSink.flush();
        final out = readCurrent();
        expect(out, isNot(contains('a0AfH6SMBxyz')));
        expect(out, isNot(contains('moi@example.com')));
        expect(out, isNot(contains('abc.def-ghi')));
        expect(out, isNot(contains('0gAbCdEfGhIjKlMnOpQrStUv')));
        expect(out, contains('ya29.[masqué]'));
        expect(out, contains('[e-mail masqué]'));
      },
    );

    test('masque client_secret, access_token et ID token JWT', () {
      expect(
        LogRedactor.redact('{"client_secret": "GOCSPX-abcdef", "x": 1}'),
        isNot(contains('GOCSPX-abcdef')),
      );
      expect(
        LogRedactor.redact('access_token=zzz123&scope=drive'),
        'access_token=[masqué]&scope=drive',
      );
      expect(
        LogRedactor.redact(
          'id eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3.sigAbCdEf',
        ),
        isNot(contains('eyJzdWIi')),
      );
    });

    test('laisse intact un message sans secret', () {
      const msg =
          'Pad « Applaudissements » (id=12) n\'a rien joué : fichier absent';
      expect(LogRedactor.redact(msg), msg);
    });
  });

  group('export', () {
    test('l\'en-tête est recopié en tête s\'il a disparu du fichier', () async {
      await start();
      await LogSink.flush();
      // Simule une rotation qui a emporté l'en-tête : on vide le fichier.
      File(p.join(dir.path, LogSink.currentFileName)).writeAsStringSync('');
      LogSink.log('App', LogLevel.info, 'apres rotation');
      final full = await LogExport.buildFullExport();
      expect(full, startsWith('Version : test'));
      expect(full, contains('apres rotation'));
    });

    test('nom de fichier daté', () {
      expect(
        LogExport.suggestedFileName(DateTime(2026, 10, 19, 9, 5)),
        'stage-cue-logs-2026-10-19-0905.txt',
      );
    });

    test(
      'l\'export commence par l\'en-tête, le tail borne les lignes',
      () async {
        await start();
        for (var i = 0; i < 10; i++) {
          LogSink.log('App', LogLevel.info, 'evt $i');
        }
        final full = await LogExport.buildFullExport();
        // L'en-tête est déjà dans le fichier : une seule occurrence, en tête.
        expect('Version : test'.allMatches(full).length, 1);
        expect(full.split('\n').first, contains('Version : test'));
        expect(full, contains('evt 9'));

        final tail = await LogExport.tail(lineCount: 3);
        expect(tail.split('\n').length, 3);
        expect(tail, contains('evt 9'));
        expect(tail, isNot(contains('evt 0')));
      },
    );
  });

  group('session', () {
    test('marqueur d\'arrêt propre', () async {
      expect(await LogSession.markStarted(dir), isFalse);
      // Pas de markCleanExit : la session suivante voit une fin non propre.
      expect(await LogSession.markStarted(dir), isTrue);
      LogSession.markCleanExit();
      expect(await LogSession.markStarted(dir), isFalse);
    });

    test('en-tête de session', () {
      final lines = buildSessionHeader(
        startedAt: DateTime(2026, 10, 19, 21),
        appVersion: '0.1.0',
        buildNumber: '1',
        operatingSystem: 'windows',
        operatingSystemVersion: 'Windows 11',
        locale: 'fr_FR',
        schemaVersion: 40,
        cueConfigured: false,
        freeDiskBytes: 5 * 1024 * 1024 * 1024,
        previousSessionUnclean: true,
      );
      expect(lines.join('\n'), contains('Schéma base : v40'));
      expect(lines.join('\n'), contains('5.0 Go'));
      expect(lines.last, 'Session précédente sans arrêt propre.');
    });
  });
}
