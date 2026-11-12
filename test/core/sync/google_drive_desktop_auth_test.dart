import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/sync/google_drive_desktop_auth.dart';

/// Un port loopback libre (lié puis relâché), pour ne pas dépendre du 8000.
Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// Simule le navigateur : Google redirige vers `redirect_uri` avec une erreur
/// (refus de l'utilisateur), ce qui fait aboutir le flux sans réseau.
Future<void> _denyConsent(Uri consentUrl) async {
  final redirect = Uri.parse(consentUrl.queryParameters['redirect_uri']!);
  final state = consentUrl.queryParameters['state']!;
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      redirect.replace(
        queryParameters: {'error': 'access_denied', 'state': state},
      ),
    );
    await (await request.close()).drain<void>();
  } finally {
    client.close(force: true);
  }
}

void main() {
  group('GoogleDriveDesktopAuthenticator.connect', () {
    test('libère le port de redirection après un délai dépassé', () async {
      final port = await _freePort();
      final opened = <Uri>[];
      final authenticator = GoogleDriveDesktopAuthenticator(
        consentPort: port,
        consentTimeout: const Duration(milliseconds: 300),
        openBrowser: (url) async => opened.add(url),
      );

      expect(await authenticator.connect(), isNull);

      // Preuve directe : le port est de nouveau liable (avant le correctif,
      // le serveur du flux OAuth restait suspendu dessus).
      final server = await HttpServer.bind('localhost', port);
      await server.close();

      // Et une nouvelle tentative repart normalement, sans SocketException.
      expect(await authenticator.connect(), isNull);
      expect(opened, hasLength(2));
    });

    test(
      'un second appel en attente rouvre la page sans relier le port',
      () async {
        final port = await _freePort();
        final opened = <Uri>[];
        final firstOpened = Completer<void>();
        final authenticator = GoogleDriveDesktopAuthenticator(
          consentPort: port,
          consentTimeout: const Duration(seconds: 30),
          openBrowser: (url) async {
            opened.add(url);
            if (!firstOpened.isCompleted) {
              firstOpened.complete();
            }
          },
        );

        final first = authenticator.connect();
        await firstOpened.future.timeout(const Duration(seconds: 5));
        final second = authenticator.connect();

        expect(opened, hasLength(2));
        expect(opened[1], opened[0], reason: 'même état OAuth, même page');

        await _denyConsent(opened[0]);

        expect(await first, isNull);
        expect(await second, isNull);

        // Le verrou est levé : un nouvel appel relance un vrai consentement.
        final third = authenticator.connect();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(opened, hasLength(3));
        await _denyConsent(opened[2]);
        expect(await third, isNull);
      },
    );
  });
}
