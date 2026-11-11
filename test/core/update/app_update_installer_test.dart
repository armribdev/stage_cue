import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/logging/log_sink.dart';
import 'package:stage_cue/core/update/app_update_info.dart';
import 'package:stage_cue/core/update/app_update_installer.dart';

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('stagecue_update_test_');
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  // L'empreinte attendue dérive de la charge utile servie par le faux client.
  AppUpdateInfo infoFor(List<int> payload) => AppUpdateInfo(
    version: '0.2.0',
    downloadUrl: 'https://example.com/StageCue-Setup.exe',
    assetName: 'StageCue-Setup.exe',
    sha256: sha256.convert(payload).toString(),
  );

  test('écrit le fichier final via rename atomique depuis .part', () async {
    final payload = List<int>.filled(64, 0xAB);
    final info = infoFor(payload);
    final client = MockClient((request) async {
      expect(request.url.toString(), info.downloadUrl);
      expect(request.method, 'GET');
      return http.Response.bytes(
        payload,
        200,
        headers: {'content-length': '${payload.length}'},
      );
    });

    final installer = AppUpdateInstaller(
      httpClient: client,
      getTemporaryDirectoryFn: () async => tempRoot,
    );

    final path = await installer.downloadInstaller(info);
    expect(path, p.join(tempRoot.path, 'stagecue_update', info.assetName));

    final file = File(path);
    expect(await file.exists(), isTrue);
    expect(await file.readAsBytes(), payload);
    expect(await File('$path.part').exists(), isFalse);
  });

  test('rapporte la progression reçue / totale', () async {
    final payload = List<int>.filled(40, 1);
    final info = infoFor(payload);
    final client = MockClient(
      (_) async => http.Response.bytes(
        payload,
        200,
        headers: {'content-length': '${payload.length}'},
      ),
    );

    final progress = <(int, int?)>[];
    final installer = AppUpdateInstaller(
      httpClient: client,
      getTemporaryDirectoryFn: () async => tempRoot,
    );

    await installer.downloadInstaller(
      info,
      onProgress: (received, total) => progress.add((received, total)),
    );

    expect(progress, isNotEmpty);
    expect(progress.last.$1, payload.length);
    expect(progress.last.$2, payload.length);
  });

  test('status HTTP non 200 → exception', () async {
    final client = MockClient((_) async => http.Response('erreur', 404));
    final installer = AppUpdateInstaller(
      httpClient: client,
      getTemporaryDirectoryFn: () async => tempRoot,
    );

    await expectLater(
      installer.downloadInstaller(infoFor(const [1, 2, 3])),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'empreinte SHA-256 différente → exception, ni .part ni exe laissés',
    () async {
      // Le serveur sert un contenu autre que celui annoncé par l'API.
      final served = List<int>.filled(64, 0xAB);
      final announced = infoFor(List<int>.filled(64, 0xCD));
      final client = MockClient(
        (_) async => http.Response.bytes(
          served,
          200,
          headers: {'content-length': '${served.length}'},
        ),
      );
      final installer = AppUpdateInstaller(
        httpClient: client,
        getTemporaryDirectoryFn: () async => tempRoot,
      );

      await expectLater(
        installer.downloadInstaller(announced),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Empreinte SHA-256'),
          ),
        ),
      );

      final updateDir = Directory(
        p.join(tempRoot.path, AppUpdateInstaller.updateDirName),
      );
      if (await updateDir.exists()) {
        expect(await updateDir.list().toList(), isEmpty);
      }
    },
  );

  test('empreinte attendue en majuscules → acceptée', () async {
    final payload = List<int>.filled(32, 7);
    final upper = AppUpdateInfo(
      version: '0.2.0',
      downloadUrl: 'https://example.com/StageCue-Setup.exe',
      assetName: 'StageCue-Setup.exe',
      sha256: sha256.convert(payload).toString().toUpperCase(),
    );
    final client = MockClient(
      (_) async => http.Response.bytes(
        payload,
        200,
        headers: {'content-length': '${payload.length}'},
      ),
    );
    final installer = AppUpdateInstaller(
      httpClient: client,
      getTemporaryDirectoryFn: () async => tempRoot,
    );

    expect(await installer.downloadInstaller(upper), isNotEmpty);
  });

  test(
    'taille reçue ≠ Content-Length → exception et pas de .part orphelin',
    () async {
      final body = List<int>.filled(10, 0);
      final info = infoFor(body);
      final client = _MismatchLengthClient(body: body, claimedLength: 99);
      final installer = AppUpdateInstaller(
        httpClient: client,
        getTemporaryDirectoryFn: () async => tempRoot,
      );

      await expectLater(
        installer.downloadInstaller(info),
        throwsA(isA<Exception>()),
      );

      final updateDir = Directory(
        p.join(tempRoot.path, AppUpdateInstaller.updateDirName),
      );
      if (await updateDir.exists()) {
        final leftovers = await updateDir.list().toList();
        expect(leftovers.where((e) => e.path.endsWith('.part')), isEmpty);
        expect(leftovers.where((e) => e.path.endsWith('.exe')), isEmpty);
      }
    },
  );

  group('reportPreviousInstall', () {
    late Directory logDir;
    late Directory updateDir;
    late AppUpdateInstaller installer;

    Future<String> sessionLog() async {
      await LogSink.flush();
      return File(
        p.join(logDir.path, LogSink.currentFileName),
      ).readAsStringSync();
    }

    Future<void> writeInstallLog(List<String> lines) => File(
      p.join(updateDir.path, AppUpdateInstaller.installLogName),
    ).writeAsString(lines.join('\n'));

    setUp(() async {
      await LogSink.resetForTest();
      logDir = await Directory.systemTemp.createTemp('stagecue_update_log_');
      await LogSink.init(directory: logDir, flushInterval: null);
      LogSink.writeSessionHeader(const ['test']);
      updateDir = Directory(
        p.join(tempRoot.path, AppUpdateInstaller.updateDirName),
      )..createSync(recursive: true);
      File(p.join(updateDir.path, 'StageCue-Setup.exe')).writeAsStringSync('x');
      installer = AppUpdateInstaller(
        getTemporaryDirectoryFn: () async => tempRoot,
      );
    });

    tearDown(() async {
      await LogSink.resetForTest();
      if (logDir.existsSync()) await logDir.delete(recursive: true);
    });

    test('installation réussie → journalisée, dossier effacé', () async {
      await writeInstallLog(const [
        '2026-11-11 23:17:55.827   Installation process succeeded.',
        '2026-11-11 23:17:55.829   Deinitializing Setup.',
        '2026-11-11 23:17:55.830   Log closed.',
      ]);

      await installer.reportPreviousInstall();

      expect(await sessionLog(), contains('Installation précédente terminée'));
      expect(updateDir.existsSync(), isFalse);
    });

    test('installation abandonnée → cause journalisée en WARN', () async {
      await writeInstallLog(const [
        '2026-11-11 23:18:12.071   Defaulting to Cancel for suppressed message box (OK/Cancel):',
        '2026-11-11 23:18:12.071   Got EAbort exception.',
        '2026-11-11 23:18:12.072   Log closed.',
      ]);

      await installer.reportPreviousInstall();

      final out = await sessionLog();
      expect(out, contains('WARN  Update Installation précédente non aboutie'));
      expect(out, contains('Got EAbort exception.'));
      expect(updateDir.existsSync(), isFalse);
    });

    test(
      'journal non clos (installeur en cours) → rien, dossier gardé',
      () async {
        await writeInstallLog(const [
          '2026-11-11 23:17:54.358   Starting the installation process.',
        ]);

        await installer.reportPreviousInstall();

        expect(await sessionLog(), isNot(contains('Installation précédente')));
        expect(updateDir.existsSync(), isTrue);
      },
    );

    test('pas de journal → sans effet', () async {
      await installer.reportPreviousInstall();

      expect(await sessionLog(), isNot(contains('Installation précédente')));
      expect(updateDir.existsSync(), isTrue);
    });
  });
}

/// `MockClient` aligne toujours `contentLength` sur le corps ; on force un
/// décalage pour exercer le garde-fou de taille.
class _MismatchLengthClient extends http.BaseClient {
  _MismatchLengthClient({required this.body, required this.claimedLength});

  final List<int> body;
  final int claimedLength;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.value(body),
      200,
      contentLength: claimedLength,
    );
  }
}
