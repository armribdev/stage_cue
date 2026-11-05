import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stage_cue/core/sync/drive_client.dart';
import 'package:stage_cue/core/sync/google_drive_client.dart';

void main() {
  group('client HTTP fermé pendant un appel', () {
    test('n\'est ni rejoué ni présenté comme une panne réseau', () async {
      var calls = 0;
      final http.Client httpClient = MockClient((_) async {
        calls++;
        throw http.ClientException(
          'HTTP request failed. Client is already closed.',
        );
      });
      final client = GoogleDriveClient(drive.DriveApi(httpClient), httpClient);

      await expectLater(
        client.getStartPageToken(),
        throwsA(
          isA<DriveRequestException>().having(
            (e) => e.message,
            'message',
            allOf(contains('renouvelée'), isNot(contains('Pas de connexion'))),
          ),
        ),
      );
      expect(calls, 1, reason: 'un client fermé le reste : aucun réessai');
    });
  });
}
