import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stage_cue/core/update/app_update_checker.dart';
import 'package:stage_cue/core/update/app_update_info.dart';

void main() {
  group('AppUpdateChecker.isNewerVersion', () {
    test('détecte une major / minor / patch plus récente', () {
      expect(AppUpdateChecker.isNewerVersion('1.0.0', '0.9.9'), isTrue);
      expect(AppUpdateChecker.isNewerVersion('0.2.0', '0.1.9'), isTrue);
      expect(AppUpdateChecker.isNewerVersion('0.1.1', '0.1.0'), isTrue);
    });

    test('égal ou plus ancien → false', () {
      expect(AppUpdateChecker.isNewerVersion('0.1.0', '0.1.0'), isFalse);
      expect(AppUpdateChecker.isNewerVersion('0.1.0', '0.2.0'), isFalse);
      expect(AppUpdateChecker.isNewerVersion('0.0.9', '0.1.0'), isFalse);
    });

    test('normalise les versions partielles et non numériques', () {
      expect(AppUpdateChecker.isNewerVersion('1.2', '1.1.9'), isTrue);
      expect(AppUpdateChecker.isNewerVersion('1.2.0', '1.2'), isFalse);
      expect(AppUpdateChecker.isNewerVersion('1.0.0-beta', '0.9.0'), isTrue);
      // composant non numérique → 0
      expect(AppUpdateChecker.isNewerVersion('1.beta.0', '1.0.0'), isFalse);
    });
  });

  group('AppUpdateChecker.checkForUpdate', () {
    Map<String, dynamic> releaseBody({
      required String tag,
      List<Map<String, dynamic>> assets = const [],
    }) => {'tag_name': tag, 'assets': assets};

    const hex =
        '168993d4dc06bca17fda7408ae50f0867a1010d561ac4aa8fe88d8597f1f6f81';

    Map<String, dynamic> exeAsset({
      String name = 'StageCue-Setup-0.2.0.exe',
      String url = 'https://example.com/StageCue-Setup-0.2.0.exe',
      Object? digest = 'sha256:$hex',
    }) => {'name': name, 'browser_download_url': url, 'digest': ?digest};

    Future<AppUpdateInfo?> checkWith(Map<String, dynamic> asset) {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode(releaseBody(tag: 'v0.2.0', assets: [asset])),
          200,
        ),
      );
      return AppUpdateChecker(
        httpClient: client,
      ).checkForUpdate(currentVersion: '0.1.0');
    }

    test('expose l\'empreinte SHA-256 du digest GitHub', () async {
      final info = await checkWith(exeAsset());
      expect(info!.sha256, hex);
    });

    test('digest en majuscules → normalisé en minuscules', () async {
      final info = await checkWith(
        exeAsset(digest: 'sha256:${hex.toUpperCase()}'),
      );
      expect(info!.sha256, hex);
    });

    test('digest absent → null (mise à jour non proposée)', () async {
      expect(await checkWith(exeAsset(digest: null)), isNull);
    });

    test('digest mal formé ou d\'un autre algorithme → null', () async {
      expect(await checkWith(exeAsset(digest: 'sha256:abc')), isNull);
      expect(await checkWith(exeAsset(digest: 'sha512:$hex')), isNull);
      expect(await checkWith(exeAsset(digest: hex)), isNull);
      expect(await checkWith(exeAsset(digest: 42)), isNull);
    });

    test(
      'retourne AppUpdateInfo si remote plus récent avec asset .exe',
      () async {
        final client = MockClient((request) async {
          expect(request.url.path, contains('/releases/latest'));
          expect(request.headers['Accept'], 'application/vnd.github+json');
          return http.Response(
            jsonEncode(releaseBody(tag: 'v0.2.0', assets: [exeAsset()])),
            200,
          );
        });

        final info = await AppUpdateChecker(
          httpClient: client,
        ).checkForUpdate(currentVersion: '0.1.0');

        expect(info, isNotNull);
        expect(info!.version, '0.2.0');
        expect(info.assetName, 'StageCue-Setup-0.2.0.exe');
        expect(
          info.downloadUrl,
          'https://example.com/StageCue-Setup-0.2.0.exe',
        );
      },
    );

    test('strip le préfixe v du tag', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode(
            releaseBody(
              tag: 'v1.0.0',
              assets: [exeAsset(name: 'a.exe', url: 'https://x/a.exe')],
            ),
          ),
          200,
        );
      });

      final info = await AppUpdateChecker(
        httpClient: client,
      ).checkForUpdate(currentVersion: '0.9.0');
      expect(info!.version, '1.0.0');
    });

    test('déjà à jour → null', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode(releaseBody(tag: 'v0.1.0', assets: [exeAsset()])),
          200,
        );
      });

      final info = await AppUpdateChecker(
        httpClient: client,
      ).checkForUpdate(currentVersion: '0.1.0');
      expect(info, isNull);
    });

    test('version plus récente sans .exe → null', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode(
            releaseBody(
              tag: 'v0.2.0',
              assets: [
                {
                  'name': 'notes.md',
                  'browser_download_url': 'https://example.com/notes.md',
                },
              ],
            ),
          ),
          200,
        );
      });

      final info = await AppUpdateChecker(
        httpClient: client,
      ).checkForUpdate(currentVersion: '0.1.0');
      expect(info, isNull);
    });

    test('status HTTP non 200 → exception', () async {
      final client = MockClient((_) async => http.Response('Nope', 503));

      expect(
        () => AppUpdateChecker(
          httpClient: client,
        ).checkForUpdate(currentVersion: '0.1.0'),
        throwsA(isA<Exception>()),
      );
    });

    test('tag_name manquant → exception', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'assets': []}), 200),
      );

      expect(
        () => AppUpdateChecker(
          httpClient: client,
        ).checkForUpdate(currentVersion: '0.1.0'),
        throwsA(isA<Exception>()),
      );
    });

    test('choisit le premier asset .exe (insensible à la casse)', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode(
            releaseBody(
              tag: '0.3.0',
              assets: [
                {
                  'name': 'README.txt',
                  'browser_download_url': 'https://example.com/README.txt',
                },
                exeAsset(
                  name: 'StageCue.EXE',
                  url: 'https://example.com/StageCue.EXE',
                ),
                exeAsset(
                  name: 'other.exe',
                  url: 'https://example.com/other.exe',
                ),
              ],
            ),
          ),
          200,
        );
      });

      final info = await AppUpdateChecker(
        httpClient: client,
      ).checkForUpdate(currentVersion: '0.1.0');
      expect(info!.assetName, 'StageCue.EXE');
      expect(info.downloadUrl, 'https://example.com/StageCue.EXE');
    });
  });
}
