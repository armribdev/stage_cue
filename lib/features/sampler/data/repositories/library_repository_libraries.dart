part of 'library_repository.dart';

/// Cycle de vie des bibliothèques : liaison à Drive, propriétaire, liste, suppression.
/// Méthodes de [LibraryRepository] extraites via extension dans le même `part`.
extension LibraryRepositoryLibraries on LibraryRepository {

  /// Ids des sons dont le fichier est déjà présent localement.
  ///
  /// Sonde de masse destinée à la recherche : voir
  /// [probeLocallyAvailableSoundIds] pour pourquoi elle ne passe pas par
  /// [resolvePlayablePath].
  Future<Set<int>> probeLocallyAvailableSoundIds(Iterable<Sound> sounds) async {
    final libraries = await getLibraries();
    return probe.probeLocallyAvailableSoundIds(
      sounds: sounds,
      libraryRootPaths: {
        for (final library in libraries) library.id: library.localRootPath,
      },
    );
  }

  /// Bibliothèque Drive unique liée, si une seule est configurée.
  Future<int?> singleConnectedLibraryId() async {
    final libraries = await getLibraries();
    final connected =
        libraries.where((library) => library.isConnectedToDrive).toList();
    if (connected.length != 1) return null;
    return connected.first.id;
  }

  /// Drives d'équipe accessibles par l'utilisateur connecté.
  Future<List<DriveSharedDrive>> listDriveSharedDrives() {
    return _withDriveClient((client) => client.listSharedDrives());
  }

  /// Dossiers du filtre « Partagés avec moi ».
  Future<List<DriveFile>> listDriveSharedWithMeFolders() {
    return _withDriveClient((client) async {
      final folders = await client.listSharedWithMeFolders();
      return folders
        ..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    });
  }

  /// Liste les sous-dossiers d'un dossier Drive (triés par nom).
  Future<List<DriveFile>> listDriveChildFolders(
    String parentId, {
    String? sharedDriveId,
  }) {
    return _withDriveClient((client) async {
      final children = await client.listFolder(
        parentId,
        sharedDriveId: sharedDriveId,
      );
      return children.where((file) => file.isFolder).toList()
        ..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    });
  }

  /// Lie un dossier Drive existant (sans le créer) et enregistre la bibliothèque.
  Future<Library> linkDriveFolder({
    required String driveFolderId,
    required String name,
    String? drivePath,
    String? ownerEmail,
    String? sharedDriveId,
    bool autoDownload = false,
  }) async {
    final folder = await _withDriveClient(
      (client) => client.getFile(driveFolderId, sharedDriveId: sharedDriveId),
    );
    if (folder == null || !folder.isFolder) {
      throw ArgumentError('Dossier Drive introuvable');
    }

    final localRoot = await _createLocalRoot();
    final resolvedOwner = await _resolveOwnerEmailForFolder(
      driveFolderId,
      explicitOwnerEmail: ownerEmail,
    );
    return _dataSource.insertLibrary(
      name: name,
      localRootPath: localRoot,
      driveFolderId: driveFolderId,
      drivePath: drivePath,
      ownerEmail: resolvedOwner,
      sharedDriveId: sharedDriveId,
      autoDownload: autoDownload,
    );
  }

  /// Lance le consentement OAuth puis crée une bibliothèque : dossier Drive
  /// (réutilisé s'il existe déjà) + dossier de cache local + ligne en base.
  /// Retourne null si l'utilisateur annule la connexion.
  Future<Library?> connectAndCreateLibrary({
    required String name,
    bool autoDownload = false,
  }) async {
    final client = await _authenticator.connect();
    if (client == null) return null;
    _activeClient = client;
    _notifyDriveSessionChanged();

    // Réutilise un dossier homonyme créé précédemment par l'app, sinon crée-le.
    var folder = await client.findInFolder(parentId: 'root', name: name);
    folder ??= await client.createFolder(name: name);

    final localRoot = await _createLocalRoot();
    return _dataSource.insertLibrary(
      name: name,
      localRootPath: localRoot,
      driveFolderId: folder.id,
      drivePath: name,
      ownerEmail: _authenticator.accountEmail,
      autoDownload: autoDownload,
    );
  }

  static final Set<String> _driveOwnerRefreshLogged = {};

  /// Met à jour [ownerEmail] des bibliothèques Drive depuis l'API (propriétaire
  /// réel, y compris dossiers partagés).
  Future<void> refreshLibraryOwnerEmails() async {
    final client = await _ensureDriveClient();
    if (client == null) return;

    final libraries = await getLibraries();
    for (final library in libraries) {
      final folderId = library.driveFolderId;
      if (folderId == null) continue;

      try {
        final owner = await client.getFolderOwnerEmail(folderId);
        if (owner == null || owner.trim().isEmpty) continue;
        final trimmed = owner.trim();
        if (trimmed == library.ownerEmail?.trim()) continue;
        await _dataSource.updateOwnerEmail(library.id, trimmed);
      } catch (e) {
        final message = e.toString();
        // Session expirée ou non connecté — cas attendu, pas de log.
        if (message.contains('invalid_token')) continue;
        if (_driveOwnerRefreshLogged.add(library.name)) {
          debugPrint(
            'Refresh propriétaire Drive échoué pour ${library.name}: $e',
          );
        }
      }
    }
  }

  /// E-mail propriétaire d'un dossier Drive (via l'API).
  Future<String?> resolveDriveFolderOwnerEmail(String driveFolderId) async {
    final client = await _ensureDriveClient();
    if (client == null) return null;
    return client.getFolderOwnerEmail(driveFolderId);
  }

  Future<String?> _resolveOwnerEmailForFolder(
    String driveFolderId, {
    String? explicitOwnerEmail,
  }) async {
    final explicit = explicitOwnerEmail?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final fromDrive = await resolveDriveFolderOwnerEmail(driveFolderId);
    if (fromDrive != null && fromDrive.trim().isNotEmpty) {
      return fromDrive.trim();
    }
    return _authenticator.accountEmail;
  }

  /// Liste le contenu distant d'une bibliothèque connectée à Drive.
  Future<List<DriveFile>> listLibraryContents(Library library) async {
    final client = _activeClient;
    final folderId = library.driveFolderId;
    if (client == null || folderId == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }
    return client.listFolder(
      folderId,
      sharedDriveId: library.sharedDriveId,
    );
  }

  /// Indique si le dossier Drive possède déjà un snapshot `.stagecue/library.db`.
  Future<bool> hasRemoteSnapshot(Library library) {
    final folderId = library.driveFolderId;
    if (folderId == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }
    return _withDriveClient(
      (client) => _syncService.hasRemoteSnapshot(
        client: client,
        libraryFolderId: folderId,
      ),
    );
  }

  /// Après liaison d'un dossier Drive : pull si BDD distante, indexation des
  /// nouveaux fichiers audio, puis [DriveFolderLinkInitResult.shouldUpload]
  /// indique s'il faut pousser les changements.
  Future<DriveFolderLinkInitResult> initializeLinkedDriveFolder({
    required Library library,
    void Function(IndexingProgress)? onProgress,
  }) async {
    final hasRemote = await hasRemoteSnapshot(library);
    var current = library;

    if (hasRemote) {
      await pullLibrary(current);
      current = await _dataSource.getLibraryById(library.id) ?? current;
    }

    final indexed = await indexDriveFolder(
      library: current,
      onProgress: onProgress,
    );

    return DriveFolderLinkInitResult(
      hadRemoteSnapshot: hasRemote,
      indexedNewFiles: indexed.newFileCount,
    );
  }

  /// Active ou désactive le téléchargement automatique des nouveaux fichiers.
  Future<void> setAutoDownload(Library library, {required bool value}) async {
    await _dataSource.setAutoDownload(library.id, value: value);
  }

  /// Retire une bibliothèque Drive indexée, ses sons et son cache local.
  Future<void> removeLibrary(Library library) async {
    await _soundDataSource.deleteSoundsByLibraryId(library.id);
    await _dataSource.deleteLibrary(library.id);

    try {
      final cacheDir = Directory(library.localRootPath);
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (e) {
      // La bibliothèque a disparu de la base mais son cache reste sur le disque,
      // désormais sans rien pour le référencer : potentiellement des gigaoctets
      // d'audio orphelins qu'aucune éviction ne viendra jamais reprendre. C'est
      // exactement le genre de « disque qui se remplit sans raison » qu'on ne
      // peut pas diagnostiquer après coup sans cette ligne.
      SyncLog.warn(
        'Cache de « ${library.name} » non supprimé (${library.localRootPath}), '
        'fichiers orphelins à retirer à la main — $e',
      );
      // Le cache local est optionnel à la suppression.
    }
  }

  Future<String> _createLocalRoot() async {
    final docs = await getApplicationSupportDirectory();
    final dir = Directory(p.join(docs.path, 'libraries', const Uuid().v4()));
    await dir.create(recursive: true);
    return dir.path;
  }
}
