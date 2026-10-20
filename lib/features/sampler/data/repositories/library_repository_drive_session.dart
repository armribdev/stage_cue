part of 'library_repository.dart';

/// Session Drive : obtention du client, renouvellement de token, (re)connexion.
/// Méthodes de [LibraryRepository] extraites via extension dans le même `part`.
extension LibraryRepositoryDriveSession on LibraryRepository {
  /// Identifiant Drive d'un dossier choisi via le sélecteur SAF Android.
  ///
  /// SAF expose parfois l'ID directement ; sinon on le déduit via l'API Drive
  /// (chemin relatif ou nom du dossier).
  Future<String?> resolveSafDriveFolderId({
    required String? driveFileId,
    required String folderName,
    String? relativeDrivePath,
  }) async {
    if (driveFileId != null && driveFileId.isNotEmpty) {
      return driveFileId;
    }

    final client = await _ensureDriveClient();
    if (client == null) {
      return null;
    }

    final path = relativeDrivePath?.trim() ?? '';
    if (path.isNotEmpty) {
      final byPath = await client.findFolderByRelativePath(path);
      if (byPath != null) {
        return byPath;
      }
    }

    return client.findFolderIdByName(folderName);
  }

  /// Résout l'e-mail propriétaire d'un dossier Drive choisi via SAF.
  ///
  /// Réutilise [activeClient] (session Bibliothèque Drive) si déjà connecté.
  Future<String?> resolveSafFolderOwnerEmail({
    required String? driveFileId,
    required String folderName,
  }) async {
    if (_authenticator is! GoogleDriveAuthenticator) {
      return null;
    }

    final client = await _ensureDriveClient();
    if (client == null) {
      return null;
    }

    return SafDriveOwnerResolver(_authenticator).resolveOwnerEmail(
      driveFileId: driveFileId,
      folderName: folderName,
      existingClient: client,
    );
  }

  /// Session utilisable par tout ce qui se contente du contrat [DriveClient].
  ///
  /// À préférer systématiquement à [_ensureDriveClient], qui restreint au type
  /// CONCRET `GoogleDriveClient` pour les rares appels hors interface
  /// (résolution de dossier par chemin, e-mail du propriétaire). Passer par le
  /// type concret là où l'interface suffit rend le code indissociable de
  /// l'implémentation Google — donc impossible à couvrir avec un double, ce qui
  /// avait laissé `downloadAllLibraryAudio` sans aucun test.
  Future<DriveClient?> _ensureAnyDriveClient() async {
    if (_requiresInteractiveReconnect) {
      return null;
    }
    final active = _activeClient;
    if (active != null) {
      return active;
    }

    final client = await _authenticator.connectSilently();
    if (client != null) {
      _activeClient = client;
      _notifyDriveSessionChanged();
    }
    return client;
  }

  /// Client Drive actif ou reconnexion silencieuse (sans nouveau consentement).
  Future<GoogleDriveClient?> _ensureDriveClient() async {
    if (_requiresInteractiveReconnect) {
      return null;
    }
    if (_activeClient is GoogleDriveClient) {
      return _activeClient as GoogleDriveClient;
    }

    final client = await _authenticator.connectSilently();
    if (client is GoogleDriveClient) {
      _activeClient = client;
      _notifyDriveSessionChanged();
      return client;
    }

    return null;
  }

  /// Exécute [action] avec le client Drive actif ; sur 401 (token périmé),
  /// renouvelle silencieusement la session une fois et réessaie.
  ///
  /// Couvre le cas d'une session ouverte depuis > 1 h : le client en cache
  /// porte un token expiré, [connectSilently] (avec `clearAuthCache`) en émet
  /// un frais. Un second 401 malgré le renouvellement = session réellement
  /// invalide → exige un OAuth interactif.
  Future<T> _withDriveClient<T>(
    Future<T> Function(DriveClient client) action,
  ) async {
    final client = _activeClient;
    if (client == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }
    try {
      return await action(client);
    } on DriveAuthException {
      final refreshed = await _remintDriveClientSilently();
      if (refreshed != null) {
        try {
          return await action(refreshed);
        } on DriveAuthException {
          // Deuxième 401 : le token frais est lui aussi rejeté.
        }
      }
      _requiresInteractiveReconnect = true;
      _notifyDriveSessionChanged();
      rethrow;
    }
  }

  /// Renouvelle silencieusement le client Drive (nouveau token). Null si aucune
  /// session ne peut être rétablie sans consentement interactif.
  Future<DriveClient?> _remintDriveClientSilently() async {
    if (_requiresInteractiveReconnect) {
      return null;
    }
    final fresh = await _authenticator.connectSilently();
    if (fresh == null) {
      return null;
    }
    _activeClient?.dispose();
    _activeClient = fresh;
    _notifyDriveSessionChanged();
    return fresh;
  }

  /// Établit une session Drive (silencieuse puis interactive si besoin).
  /// Retourne false si l'utilisateur annule la connexion.
  ///
  /// Le refresh silencieux est toujours tenté, même si [_activeClient] est
  /// déjà défini : les tokens Google expirent après ~1 h et l'API renverrait
  /// un 401 si on réutilisait un token périmé sans le renouveler.
  Future<bool> ensureDriveConnected() async {
    if (_requiresInteractiveReconnect) {
      if (_activeClient != null) {
        _activeClient!.dispose();
        _activeClient = null;
      }
      final client = await _authenticator.connect();
      if (client == null) {
        _notifyDriveSessionChanged();
        return false;
      }
      _activeClient = client;
      _requiresInteractiveReconnect = false;
      await _authenticator.refreshAccountProfile();
      _notifyDriveSessionChanged();
      return true;
    }

    final fresh = await _authenticator.connectSilently();
    if (fresh != null) {
      _activeClient?.dispose();
      _activeClient = fresh;
      _requiresInteractiveReconnect = false;
      await _authenticator.refreshAccountProfile();
      _notifyDriveSessionChanged();
      return true;
    }

    // Le refresh silencieux a échoué (session révoquée ou inexistante).
    if (_activeClient != null) {
      _activeClient!.dispose();
      _activeClient = null;
    }

    final client = await _authenticator.connect();
    if (client == null) {
      _notifyDriveSessionChanged();
      return false;
    }
    _activeClient = client;
    _requiresInteractiveReconnect = false;
    _notifyDriveSessionChanged();
    await _authenticator.refreshAccountProfile();
    _notifyDriveSessionChanged();
    return true;
  }

  /// Recharge le profil Google (photo, nom) après reconnexion OAuth.
  Future<void> refreshConnectedAccountProfile() async {
    await _authenticator.refreshAccountProfile();
    _notifyDriveSessionChanged();
  }

  /// Ferme la session Drive et révoque la connexion du compte.
  Future<void> disconnect() async {
    _activeClient?.dispose();
    _activeClient = null;
    _requiresInteractiveReconnect = false;
    await _authenticator.signOut();
    _notifyDriveSessionChanged();
  }
}
