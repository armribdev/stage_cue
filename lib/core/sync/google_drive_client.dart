import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart' as gsi;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart'
    show AccessDeniedException, ServerRequestFailedException;
import 'package:http/http.dart' as http;

import 'drive_account_profile.dart';
import 'drive_client.dart';
import 'drive_models.dart';
import 'drive_profile_cache.dart';
import 'google_drive_desktop_auth.dart';

/// Champs Drive demandés pour décrire un fichier (révision, hash, taille…).
const String _fileFields =
    'id, name, mimeType, modifiedTime, size, md5Checksum';

/// Nombre de dossiers parents interrogés par requête dans [GoogleDriveClient.findInFolders].
///
/// La clause `q` de Drive a une longueur bornée : chaque parent y ajoute une
/// quarantaine de caractères. 40 laisse une marge confortable, sachant qu'un lot
/// trop large ferait échouer la requête entière au lieu de la ralentir.
const int _findInFoldersChunk = 40;

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

  /// Vrai si [error] traduit un token OAuth périmé/révoqué (à convertir en
  /// [DriveAuthException] pour déclencher le renouvellement silencieux).
  ///
  /// Deux formes possibles selon la couche qui rejette : `AccessDeniedException`
  /// (côté googleapis_auth, message « Access was denied … Bearer realm=… ») ou
  /// `DetailedApiRequestError` 401 (côté API Drive).
  static bool _isAuthError(Object error) {
    if (error is AccessDeniedException) return true;
    if (error is drive.DetailedApiRequestError) return error.status == 401;
    return false;
  }

  static bool _isOAuthClientConfigurationError(Object error) {
    if (error is! ServerRequestFailedException) {
      return false;
    }
    final message = error.message.toLowerCase();
    return message.contains('unauthorized_client') ||
        message.contains('invalid_client');
  }

  /// Vrai si l'erreur se résoudra probablement d'elle-même : quota momentané,
  /// incident Google, réseau instable.
  ///
  /// Le 403 est ambigu chez Drive : il sert à la fois au dépassement de quota
  /// (retentable) et au refus de droits (définitif). Seul le motif tranche.
  static bool _isTransient(Object error) {
    if (error is drive.DetailedApiRequestError) {
      final status = error.status;
      if (status == null) return false;
      if (status == 429 || (status >= 500 && status < 600)) return true;
      if (status == 403) return _isRateLimited(error);
      return false;
    }
    return error is SocketException ||
        error is http.ClientException ||
        error is TimeoutException;
  }

  static bool _isRateLimited(drive.DetailedApiRequestError error) {
    final reasons = [
      ...error.errors.map((e) => e.reason?.toLowerCase() ?? ''),
      error.message?.toLowerCase() ?? '',
    ];
    return reasons.any(
      (r) => r.contains('ratelimit') || r.contains('quota'),
    );
  }

  /// Traduit une erreur d'API en message présentable.
  static Object _describe(Object error) {
    if (error is drive.DetailedApiRequestError) {
      final status = error.status;
      if (status == 429 || (status == 403 && _isRateLimited(error))) {
        return const DriveRequestException.quota();
      }
      if (status == 403) return const DriveRequestException.denied();
      if (status != null && status >= 500) {
        return const DriveRequestException.unavailable();
      }
      return error;
    }
    if (error is SocketException ||
        error is http.ClientException ||
        error is TimeoutException) {
      return const DriveRequestException.offline();
    }
    return error;
  }

  /// Attente avant nouvelle tentative : exponentielle, avec un bruit aléatoire
  /// pour ne pas resynchroniser plusieurs appareils sur le même créneau.
  static Duration _backoff(int attempt) {
    final base = 500 * (1 << (attempt - 1)); // 500ms, 1s, 2s…
    return Duration(milliseconds: base + _random.nextInt(250));
  }

  static final math.Random _random = math.Random();

  /// Nombre total de tentatives pour les appels rejouables.
  static const int _maxAttempts = 4;

  /// Exécute [fn] et convertit toute erreur d'auth en [DriveAuthException],
  /// les autres en [DriveRequestException] quand elles sont descriptibles.
  ///
  /// **Sans réessai** : réservé aux appels NON rejouables — ceux qui consomment
  /// un `Stream` (upload) ou qui créent une ressource. Rejouer un upload
  /// enverrait un flux déjà épuisé ; rejouer une création dupliquerait le
  /// dossier si seule la réponse s'est perdue.
  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e) {
      if (_isAuthError(e) || _isOAuthClientConfigurationError(e)) {
        throw const DriveAuthException();
      }
      throw _describe(e);
    }
  }

  /// Comme [_guard], avec réessai exponentiel sur erreur transitoire.
  /// Réservé aux appels IDEMPOTENTS (lecture, listing, téléchargement).
  Future<T> _guardRetry<T>(Future<T> Function() fn) async {
    var attempt = 0;
    while (true) {
      try {
        return await fn();
      } catch (e) {
        if (_isAuthError(e) || _isOAuthClientConfigurationError(e)) {
          throw const DriveAuthException();
        }
        attempt++;
        if (attempt >= _maxAttempts || !_isTransient(e)) {
          throw _describe(e);
        }
        await Future<void>.delayed(_backoff(attempt));
      }
    }
  }

  @override
  Future<List<DriveSharedDrive>> listSharedDrives() {
    return _guardRetry(() async {
      final results = <DriveSharedDrive>[];
      String? pageToken;
      do {
        final driveList = await _api.drives.list(
          pageSize: 100,
          pageToken: pageToken,
        );
        for (final sharedDrive in driveList.drives ?? const <drive.Drive>[]) {
          final id = sharedDrive.id;
          final name = sharedDrive.name;
          if (id == null || name == null) {
            continue;
          }
          results.add(DriveSharedDrive(id: id, name: name));
        }
        pageToken = driveList.nextPageToken;
      } while (pageToken != null);

      results.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return results;
    });
  }

  @override
  Future<List<DriveFile>> listSharedWithMeFolders() async {
    return _listFiles(
      q: "sharedWithMe = true and mimeType = '$driveFolderMimeType' "
          'and trashed = false',
      pageSize: 200,
    );
  }

  @override
  Future<List<DriveFile>> listFolder(
    String folderId, {
    String? sharedDriveId,
  }) async {
    return _listFiles(
      q: "'${_escape(folderId)}' in parents and trashed = false",
      sharedDriveId: sharedDriveId,
    );
  }

  Future<List<DriveFile>> _listFiles({
    required String q,
    String? sharedDriveId,
    int pageSize = 200,
  }) {
    return _guardRetry(() async {
      final results = <DriveFile>[];
      String? pageToken;
      do {
        final fileList = await _api.files.list(
          q: q,
          spaces: 'drive',
          $fields: 'nextPageToken, files($_fileFields)',
          pageSize: pageSize,
          pageToken: pageToken,
          supportsAllDrives: true,
          includeItemsFromAllDrives: true,
          driveId: sharedDriveId,
          corpora: sharedDriveId != null ? 'drive' : null,
        );
        for (final f in fileList.files ?? const <drive.File>[]) {
          results.add(_toDriveFile(f));
        }
        pageToken = fileList.nextPageToken;
      } while (pageToken != null);
      return results;
    });
  }

  @override
  Future<DriveFile?> findInFolder({
    required String parentId,
    required String name,
    String? sharedDriveId,
  }) async {
    return _guardRetry(() async {
      final fileList = await _api.files.list(
        q: "'${_escape(parentId)}' in parents and "
            "name = '${_escape(name)}' and trashed = false",
        spaces: 'drive',
        $fields: 'files($_fileFields)',
        pageSize: 1,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
        driveId: sharedDriveId,
        corpora: sharedDriveId != null ? 'drive' : null,
      );
      final files = fileList.files;
      if (files == null || files.isEmpty) return null;
      return _toDriveFile(files.first);
    });
  }

  @override
  Future<Map<String, DriveFile>> findInFolders({
    required Iterable<String> parentIds,
    required String name,
    String? sharedDriveId,
  }) async {
    final parents = parentIds.toSet().toList();
    if (parents.isEmpty) return const {};

    final results = <String, DriveFile>{};
    // Découpé : la clause `q` a une longueur bornée côté Drive, et un lot trop
    // large ferait échouer la requête entière plutôt que de la ralentir.
    for (var start = 0; start < parents.length; start += _findInFoldersChunk) {
      final chunk = parents.sublist(
        start,
        math.min(start + _findInFoldersChunk, parents.length),
      );
      final parentClause =
          chunk.map((id) => "'${_escape(id)}' in parents").join(' or ');

      await _guardRetry(() async {
        String? pageToken;
        do {
          final fileList = await _api.files.list(
            q: "($parentClause) and name = '${_escape(name)}' "
                'and trashed = false',
            spaces: 'drive',
            // `parents` en plus : c'est lui qui permet de rattacher chaque
            // résultat à son dossier d'origine.
            $fields: 'nextPageToken, files($_fileFields, parents)',
            pageSize: 200,
            pageToken: pageToken,
            supportsAllDrives: true,
            includeItemsFromAllDrives: true,
            driveId: sharedDriveId,
            corpora: sharedDriveId != null ? 'drive' : null,
          );
          for (final f in fileList.files ?? const <drive.File>[]) {
            for (final parent in f.parents ?? const <String>[]) {
              // `putIfAbsent` : à parent égal, on garde le premier trouvé —
              // même arbitrage que `findInFolder`, qui prend `files.first`.
              results.putIfAbsent(parent, () => _toDriveFile(f));
            }
          }
          pageToken = fileList.nextPageToken;
        } while (pageToken != null);
      });
    }
    return results;
  }

  @override
  Future<DriveFile> createFolder({
    required String name,
    String? parentId,
  }) {
    return _guard(() async {
      final metadata = drive.File()
        ..name = name
        ..mimeType = driveFolderMimeType
        ..parents = parentId != null ? [parentId] : null;
      final created = await _api.files.create(metadata, $fields: _fileFields);
      return _toDriveFile(created);
    });
  }

  @override
  Future<DriveFile> uploadFile({
    required String name,
    required String parentId,
    required Stream<List<int>> data,
    required int length,
    String? mimeType,
  }) {
    return _guard(() async {
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
    });
  }

  @override
  Future<DriveFile> updateFileContent({
    required String fileId,
    required Stream<List<int>> data,
    required int length,
    String? mimeType,
  }) {
    return _guard(() async {
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
    });
  }

  @override
  Future<DriveFile?> getFile(
    String fileId, {
    String? sharedDriveId,
  }) async {
    try {
      final f = await _api.files.get(
        fileId,
        $fields: _fileFields,
        supportsAllDrives: true,
      ) as drive.File;
      return _toDriveFile(f);
    } on drive.DetailedApiRequestError catch (e) {
      if (_isAuthError(e)) throw const DriveAuthException();
      if (e.status == 404) return null;
      rethrow;
    } on AccessDeniedException {
      throw const DriveAuthException();
    }
  }

  @override
  Future<List<int>> downloadBytes(String fileId) {
    return _guardRetry(() async {
      final media = await _api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
        supportsAllDrives: true,
      ) as drive.Media;
      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }
      return bytes;
    });
  }

  @override
  Future<void> downloadToFile({
    required String fileId,
    required String destinationPath,
  }) {
    return _guardRetry(() async {
      final media = await _api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
        supportsAllDrives: true,
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
    });
  }

  @override
  Future<void> deleteFile(String fileId) {
    return _guard(() => _api.files.delete(fileId));
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
      if (_isAuthError(e)) throw const DriveAuthException();
      if (e.status == 404 || e.status == 403) return null;
      rethrow;
    } on AccessDeniedException {
      throw const DriveAuthException();
    }
  }

  /// Recherche un dossier par nom (tous Drive accessibles) et renvoie l'e-mail propriétaire.
  Future<String?> findFolderOwnerByName(String folderName) async {
    final folder = await _findFirstFolderByName(folderName);
    if (folder == null) {
      return null;
    }

    try {
      final file = await _api.files.get(
        folder.id!,
        $fields: 'owners(emailAddress)',
        supportsAllDrives: true,
      ) as drive.File;
      final owners = file.owners;
      if (owners == null || owners.isEmpty) {
        return null;
      }
      return owners.first.emailAddress;
    } on drive.DetailedApiRequestError catch (e) {
      if (_isAuthError(e)) throw const DriveAuthException();
      if (e.status == 404 || e.status == 403) return null;
      rethrow;
    } on AccessDeniedException {
      throw const DriveAuthException();
    }
  }

  /// Identifiant Drive d'un dossier trouvé par nom (premier résultat accessible).
  Future<String?> findFolderIdByName(String folderName) async {
    final folder = await _findFirstFolderByName(folderName);
    return folder?.id;
  }

  /// Parcourt « Mon Drive » segment par segment et renvoie l'identifiant du dossier cible.
  Future<String?> findFolderByRelativePath(String relativePath) async {
    final segments = relativePath
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      return null;
    }

    var parentId = 'root';
    for (final segment in segments) {
      final folder = await findInFolder(parentId: parentId, name: segment);
      if (folder == null || !folder.isFolder) {
        return null;
      }
      parentId = folder.id;
    }
    return parentId;
  }

  Future<drive.File?> _findFirstFolderByName(String folderName) async {
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
        $fields: 'nextPageToken, files(id)',
        pageSize: 20,
        pageToken: pageToken,
      );
      final files = response.files;
      if (files != null && files.isNotEmpty) {
        return files.first;
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

/// Authentificateur Google : OAuth via `google_sign_in` (mobile/macOS) ou
/// navigateur système (Windows/Linux), puis [GoogleDriveClient].
class GoogleDriveAuthenticator implements DriveAuthenticator {
  GoogleDriveAuthenticator({
    DriveAuthenticator? authenticator,
    DriveProfileStore? profileStore,
  })  : _delegate = authenticator ?? _createPlatformAuthenticator(),
        _profileStore = profileStore ?? const DriveProfileStore();

  final DriveAuthenticator _delegate;
  final DriveProfileStore _profileStore;

  /// Dernier profil connu, restauré depuis le disque au lancement. Sert de
  /// repli quand le délégué n'a pas encore résolu le profil (ex. hors-ligne),
  /// pour afficher immédiatement nom/e-mail/photo.
  DriveAccountProfile? _persistedProfile;

  static DriveAuthenticator _createPlatformAuthenticator() {
    if (Platform.isWindows || Platform.isLinux) {
      return GoogleDriveDesktopAuthenticator();
    }
    return _MobileGoogleDriveAuthenticator();
  }

  @override
  String? get accountEmail => accountProfile?.email;

  @override
  DriveAccountProfile? get accountProfile =>
      _delegate.accountProfile ?? _persistedProfile;

  /// Recopie le profil résolu par le délégué vers le cache mémoire + disque.
  /// Si le délégué n'a pas de profil (hors-ligne, id_token illisible), on
  /// restaure le dernier profil persisté pour conserver l'affichage.
  Future<void> _syncPersistedProfile() async {
    final current = _delegate.accountProfile;
    if (current == null) {
      _persistedProfile ??= await _profileStore.load();
      return;
    }
    if (current != _persistedProfile) {
      _persistedProfile = current;
      await _profileStore.save(current);
    }
  }

  @override
  Future<DriveClient?> connect() async {
    final client = await _delegate.connect();
    await _syncPersistedProfile();
    return client;
  }

  @override
  Future<DriveClient?> connectSilently() async {
    final client = await _delegate.connectSilently();
    await _syncPersistedProfile();
    return client;
  }

  @override
  Future<void> restoreAccountProfile() async {
    // Restaure d'abord le profil mis en cache pour un affichage immédiat, puis
    // laisse le délégué le rafraîchir (id_token local, sinon réseau).
    _persistedProfile ??= await _profileStore.load();
    await _delegate.restoreAccountProfile();
    await _syncPersistedProfile();
  }

  @override
  Future<void> refreshAccountProfile() async {
    await _delegate.refreshAccountProfile();
    await _syncPersistedProfile();
  }

  @override
  Future<void> signOut() async {
    await _delegate.signOut();
    _persistedProfile = null;
    await _profileStore.clear();
  }
}

/// OAuth via le plugin `google_sign_in` (Android, iOS, macOS).
class _MobileGoogleDriveAuthenticator implements DriveAuthenticator {
  _MobileGoogleDriveAuthenticator({gsi.GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn ??
            gsi.GoogleSignIn(
              scopes: const [
                drive.DriveApi.driveScope,
                drive.DriveApi.driveFileScope,
                drive.DriveApi.driveReadonlyScope,
              ],
            );

  final gsi.GoogleSignIn _googleSignIn;

  @override
  String? get accountEmail => accountProfile?.email;

  @override
  DriveAccountProfile? get accountProfile {
    final user = _googleSignIn.currentUser;
    if (user == null) {
      return null;
    }
    return DriveAccountProfile(
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoUrl,
    );
  }

  Future<DriveClient?> _clientForCurrentUser() async {
    final authClient = await _googleSignIn.authenticatedClient();
    if (authClient == null) {
      return null;
    }
    return GoogleDriveClient(drive.DriveApi(authClient), authClient);
  }

  @override
  Future<DriveClient?> connect() async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      return null;
    }
    return _clientForCurrentUser();
  }

  @override
  Future<DriveClient?> connectSilently() async {
    final account = await _googleSignIn.signInSilently();
    if (account == null) {
      return null;
    }
    // google_sign_in met en cache l'access token OAuth (~1 h) et ne le
    // renouvelle pas de lui-même : sans purge, authenticatedClient() ré-emballe
    // le token périmé et le premier appel Drive échoue en 401 (« Access was
    // denied »). clearAuthCache() force l'émission silencieuse d'un token frais.
    await account.clearAuthCache();
    return _clientForCurrentUser();
  }

  @override
  Future<void> restoreAccountProfile() async {
    await refreshAccountProfile();
  }

  @override
  Future<void> refreshAccountProfile() async {
    await _googleSignIn.signInSilently();
  }

  @override
  Future<void> signOut() => _googleSignIn.signOut();
}
