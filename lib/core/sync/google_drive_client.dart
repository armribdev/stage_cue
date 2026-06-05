import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'drive_client.dart';
import 'drive_models.dart';

/// Champs Drive demandés pour décrire un fichier (révision, hash, taille…).
const String _fileFields =
    'id, name, mimeType, modifiedTime, size, md5Checksum';

/// Implémentation [DriveClient] adossée à l'API Google Drive v3.
///
/// Avec le scope `drive.file`, l'app ne voit que les fichiers qu'elle a créés
/// ou ouverts elle-même : la bibliothèque est donc un dossier créé par l'app,
/// dont elle gère le contenu. Un dossier audio préexistant ne serait pas
/// visible sans un sélecteur (Drive Picker) ou un scope plus large.
class GoogleDriveClient implements DriveClient {
  final drive.DriveApi _api;
  final http.Client _httpClient;

  GoogleDriveClient(this._api, this._httpClient);

  DriveFile _toDriveFile(drive.File f) {
    final sizeStr = f.size;
    return DriveFile(
      id: f.id!,
      name: f.name ?? '',
      mimeType: f.mimeType,
      modifiedTime: f.modifiedTime,
      size: sizeStr != null ? int.tryParse(sizeStr) : null,
      md5Checksum: f.md5Checksum,
    );
  }

  /// Échappe les apostrophes pour les requêtes `q` de l'API Drive.
  String _escape(String value) => value.replaceAll("'", r"\'");

  @override
  Future<List<DriveFile>> listFolder(String folderId) async {
    final results = <DriveFile>[];
    String? pageToken;
    do {
      final fileList = await _api.files.list(
        q: "'${_escape(folderId)}' in parents and trashed = false",
        spaces: 'drive',
        $fields: 'nextPageToken, files($_fileFields)',
        pageSize: 200,
        pageToken: pageToken,
      );
      for (final f in fileList.files ?? const <drive.File>[]) {
        results.add(_toDriveFile(f));
      }
      pageToken = fileList.nextPageToken;
    } while (pageToken != null);
    return results;
  }

  @override
  Future<DriveFile?> findInFolder({
    required String parentId,
    required String name,
  }) async {
    final fileList = await _api.files.list(
      q: "'${_escape(parentId)}' in parents and "
          "name = '${_escape(name)}' and trashed = false",
      spaces: 'drive',
      $fields: 'files($_fileFields)',
      pageSize: 1,
    );
    final files = fileList.files;
    if (files == null || files.isEmpty) return null;
    return _toDriveFile(files.first);
  }

  @override
  Future<DriveFile> createFolder({
    required String name,
    String? parentId,
  }) async {
    final metadata = drive.File()
      ..name = name
      ..mimeType = driveFolderMimeType
      ..parents = parentId != null ? [parentId] : null;
    final created = await _api.files.create(metadata, $fields: _fileFields);
    return _toDriveFile(created);
  }

  @override
  Future<DriveFile> uploadFile({
    required String name,
    required String parentId,
    required Stream<List<int>> data,
    required int length,
    String? mimeType,
  }) async {
    final metadata = drive.File()
      ..name = name
      ..parents = [parentId];
    final media = drive.Media(
      data,
      length,
      contentType: mimeType ?? 'application/octet-stream',
    );
    final created = await _api.files.create(
      metadata,
      uploadMedia: media,
      $fields: _fileFields,
    );
    return _toDriveFile(created);
  }

  @override
  Future<DriveFile> updateFileContent({
    required String fileId,
    required Stream<List<int>> data,
    required int length,
    String? mimeType,
  }) async {
    final media = drive.Media(
      data,
      length,
      contentType: mimeType ?? 'application/octet-stream',
    );
    final updated = await _api.files.update(
      drive.File(),
      fileId,
      uploadMedia: media,
      $fields: _fileFields,
    );
    return _toDriveFile(updated);
  }

  @override
  Future<DriveFile?> getFile(String fileId) async {
    try {
      final f = await _api.files.get(fileId, $fields: _fileFields) as drive.File;
      return _toDriveFile(f);
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  @override
  Future<List<int>> downloadBytes(String fileId) async {
    final media = await _api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  @override
  Future<void> downloadToFile({
    required String fileId,
    required String destinationPath,
  }) async {
    final media = await _api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final destination = File(destinationPath);
    await destination.parent.create(recursive: true);
    // Écriture vers un fichier temporaire puis renommage atomique : évite un
    // fichier partiel si le téléchargement échoue en cours de route.
    final tmp = File('$destinationPath.part');
    final sink = tmp.openWrite();
    try {
      await media.stream.pipe(sink);
    } catch (_) {
      await sink.close();
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
    await tmp.rename(destinationPath);
  }

  @override
  Future<void> deleteFile(String fileId) async {
    await _api.files.delete(fileId);
  }

  /// E-mail du propriétaire du dossier (y compris dossier partagé).
  Future<String?> getFolderOwnerEmail(String fileId) async {
    try {
      final file = await _api.files.get(
        fileId,
        $fields: 'owners(emailAddress)',
        supportsAllDrives: true,
      ) as drive.File;
      final owners = file.owners;
      if (owners == null || owners.isEmpty) {
        return null;
      }
      return owners.first.emailAddress;
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 404 || e.status == 403) {
        return null;
      }
      rethrow;
    }
  }

  /// Recherche un dossier par nom (tous Drive accessibles) et renvoie l'e-mail propriétaire.
  Future<String?> findFolderOwnerByName(String folderName) async {
    final trimmed = folderName.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    String? pageToken;
    do {
      final response = await _api.files.list(
        q: "name = '${_escape(trimmed)}' and "
            "mimeType = '$driveFolderMimeType' and trashed = false",
        corpora: 'allDrives',
        includeItemsFromAllDrives: true,
        supportsAllDrives: true,
        $fields: 'nextPageToken, files(owners/emailAddress)',
        pageSize: 20,
        pageToken: pageToken,
      );
      for (final file in response.files ?? const <drive.File>[]) {
        final owners = file.owners;
        if (owners != null && owners.isNotEmpty) {
          final email = owners.first.emailAddress;
          if (email != null && email.isNotEmpty) {
            return email;
          }
        }
      }
      pageToken = response.nextPageToken;
    } while (pageToken != null);

    return null;
  }

  @override
  void dispose() {
    _httpClient.close();
  }
}

/// Authentificateur Google : OAuth via `google_sign_in`, puis construction d'un
/// [GoogleDriveClient] sur un client HTTP authentifié.
///
/// Note plateforme : `google_sign_in` ne supporte pas Windows/Linux desktop —
/// l'auth Drive fonctionne sur Android, iOS, macOS et Web.
class GoogleDriveAuthenticator implements DriveAuthenticator {
  final GoogleSignIn _googleSignIn;

  GoogleDriveAuthenticator({GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn ??
            GoogleSignIn(
              scopes: const [
                drive.DriveApi.driveFileScope,
                drive.DriveApi.driveReadonlyScope,
              ],
            );

  @override
  String? get accountEmail => _googleSignIn.currentUser?.email;

  Future<DriveClient?> _clientForCurrentUser() async {
    final authClient = await _googleSignIn.authenticatedClient();
    if (authClient == null) return null;
    return GoogleDriveClient(drive.DriveApi(authClient), authClient);
  }

  @override
  Future<DriveClient?> connect() async {
    final account = await _googleSignIn.signIn();
    if (account == null) return null; // annulé par l'utilisateur
    return _clientForCurrentUser();
  }

  @override
  Future<DriveClient?> connectSilently() async {
    final account = await _googleSignIn.signInSilently();
    if (account == null) return null;
    return _clientForCurrentUser();
  }

  @override
  Future<void> signOut() => _googleSignIn.signOut();
}
