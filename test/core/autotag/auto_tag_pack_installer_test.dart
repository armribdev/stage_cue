import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/autotag/auto_tag_pack.dart';
import 'package:stage_cue/core/autotag/auto_tag_pack_controller.dart';
import 'package:stage_cue/core/autotag/auto_tag_pack_installer.dart';

void main() {
  late Directory dir;
  late AutoTagPack pack;
  final payload = utf8.encode('x' * 5000);
  final release = AutoTagPackRelease(
    url: 'https://example.test/pack.onnx',
    sha256: sha256.convert(payload).toString(),
    sizeBytes: payload.length,
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pack_');
    pack = AutoTagPack(Directory(p.join(dir.path, 'pack')));
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// Client qui sert [bytes] en morceaux de 1000 octets.
  http.Client serving(List<int> bytes, {int status = 200}) =>
      MockClient.streaming((request, _) async {
        Stream<List<int>> chunks() async* {
          for (var i = 0; i < bytes.length; i += 1000) {
            yield bytes.sublist(
              i,
              i + 1000 > bytes.length ? bytes.length : i + 1000,
            );
            await Future<void>.delayed(Duration.zero);
          }
        }

        return http.StreamedResponse(chunks(), status);
      });

  AutoTagPackInstaller installer(http.Client client) =>
      AutoTagPackInstaller(pack, release: release, httpClient: client);

  Future<List<String>> files() async => [
    for (final f in (await pack.root()).listSync()) p.basename(f.path),
  ];

  test('installe : taille et SHA-256 vérifiés, `.part` renommé', () async {
    final progress = <int>[];
    await installer(
      serving(payload),
    ).install(onProgress: (received, total) => progress.add(received));

    expect(await pack.isInstalled(), isTrue);
    expect(await files(), [AutoTagPack.modelFileName]);
    expect(await (await pack.modelFile()).readAsBytes(), payload);
    expect(progress.last, payload.length);
  });

  test('contenu altéré : refusé, rien d\'installé', () async {
    final tampered = List<int>.from(payload)..[100] = 0;
    await expectLater(
      installer(serving(tampered)).install(),
      throwsA(predicate((e) => e.toString().contains('SHA-256'))),
    );
    expect(await pack.isInstalled(), isFalse);
    expect(await files(), isEmpty, reason: '`.part` supprimé');
  });

  test('fichier tronqué ou trop long : refusé', () async {
    await expectLater(
      installer(serving(payload.sublist(0, 3000))).install(),
      throwsA(predicate((e) => e.toString().contains('Taille'))),
    );
    await expectLater(
      installer(serving([...payload, 1, 2, 3])).install(),
      throwsA(predicate((e) => e.toString().contains('dépasse'))),
    );
    expect(await pack.isInstalled(), isFalse);
    expect(await files(), isEmpty);
  });

  test('réponse HTTP en erreur : refusée', () async {
    await expectLater(
      installer(serving(const [], status: 404)).install(),
      throwsA(predicate((e) => e.toString().contains('404'))),
    );
    expect(await pack.isInstalled(), isFalse);
  });

  test('annulation : `.part` supprimé, pack déjà installé intact', () async {
    await installer(serving(payload)).install();
    final cancel = AutoTagPackCancelToken();
    await expectLater(
      installer(serving(payload)).install(
        cancel: cancel,
        onProgress: (received, _) {
          if (received >= 2000) cancel.cancel();
        },
      ),
      throwsA(isA<AutoTagPackCancelled>()),
    );
    expect(await files(), [AutoTagPack.modelFileName]);
    expect(await (await pack.modelFile()).readAsBytes(), payload);
  });

  test('un échec ne détruit pas un pack déjà installé', () async {
    await installer(serving(payload)).install();
    final tampered = List<int>.from(payload)..[0] = 9;
    await expectLater(
      installer(serving(tampered)).install(),
      throwsA(isA<Exception>()),
    );
    expect(await (await pack.modelFile()).readAsBytes(), payload);
  });

  test('remove supprime le modèle', () async {
    final i = installer(serving(payload));
    await i.install();
    await i.remove();
    expect(await pack.isInstalled(), isFalse);
  });

  group('AutoTagPackController', () {
    test('installe, notifie, prévient l\'analyse', () async {
      final controller = AutoTagPackController(
        pack,
        installer(serving(payload)),
      );
      addTearDown(controller.dispose);
      var installedCalls = 0;
      controller.onInstalled = () => installedCalls++;

      await controller.refresh();
      expect(controller.status, AutoTagPackStatus.notInstalled);
      await controller.install();
      expect(controller.status, AutoTagPackStatus.installed);
      expect(installedCalls, 1);
      expect(controller.lastError, isNull);
    });

    test(
      'échec : l\'erreur est exposée, l\'état revient à « non installé »',
      () async {
        final controller = AutoTagPackController(
          pack,
          installer(serving(const [], status: 500)),
        );
        addTearDown(controller.dispose);
        var installedCalls = 0;
        controller.onInstalled = () => installedCalls++;

        await controller.install();
        expect(controller.status, AutoTagPackStatus.notInstalled);
        expect(controller.lastError, isNotNull);
        expect(installedCalls, 0);
      },
    );

    test('annulation : pas d\'erreur, pas d\'installation', () async {
      final controller = AutoTagPackController(
        pack,
        installer(serving(payload)),
      );
      addTearDown(controller.dispose);
      final future = controller.install();
      controller.cancel();
      await future;
      expect(controller.status, AutoTagPackStatus.notInstalled);
      expect(controller.lastError, isNull);
    });
  });
}
