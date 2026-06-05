import 'google_drive_client.dart';

/// Résout l'e-mail du propriétaire d'un dossier Drive sélectionné via SAF.
///
/// SAF ne fournit pas cette information : on passe par l'API Drive (lecture
/// seule) une fois l'utilisateur connecté au compte qui a accès au dossier.
class SafDriveOwnerResolver {
  final GoogleDriveAuthenticator _authenticator;

  SafDriveOwnerResolver(this._authenticator);

  Future<String?> resolveOwnerEmail({
    required String? driveFileId,
    required String folderName,
    GoogleDriveClient? existingClient,
  }) async {
    GoogleDriveClient? client = existingClient;
    if (client == null) {
      final connected = await _authenticator.connectSilently() ??
          await _authenticator.connect();
      if (connected is! GoogleDriveClient) {
        return null;
      }
      client = connected;
    }

    if (driveFileId != null && driveFileId.isNotEmpty) {
      final owner = await client.getFolderOwnerEmail(driveFileId);
      if (owner != null) {
        return owner;
      }
    }

    return client.findFolderOwnerByName(folderName);
  }
}
