part of 'library_repository.dart';

/// Réalignement des chemins relatifs sur les fichiers réellement présents sur Drive.
/// Méthodes de [LibraryRepository] extraites via extension dans le même `part`.
extension LibraryRepositoryPathReconcile on LibraryRepository {

  /// Réaligne les chemins issus d'un snapshot sur les fichiers réellement
  /// présents sur Drive (déplacement, renommage, préfixe legacy `sounds/`).
  Future<void> _reconcileOrphanedSoundPaths({
    required Library library,
    required List<String> driveRelativePaths,
  }) async {
    final drivePaths = driveRelativePaths
        .map(LibrarySoundPaths.normalizeRelativePath)
        .toSet();
    final byBasename = <String, List<String>>{};
    for (final path in drivePaths) {
      final key = p.basename(path).toLowerCase();
      byBasename.putIfAbsent(key, () => []).add(path);
    }

    final sounds = await _soundDataSource.getSoundsForLibrary(library.id);
    for (final sound in sounds) {
      final raw = sound.relativePath;
      if (raw == null || raw.isEmpty) continue;

      final current = LibrarySoundPaths.normalizeRelativePath(raw);
      if (drivePaths.contains(current)) continue;

      final candidates = byBasename[p.basename(current).toLowerCase()];
      if (candidates == null || candidates.isEmpty) continue;

      final corrected =
          ReconcilePathMatcher.pickBestCandidate(current, candidates);
      if (corrected == null) continue;
      await _soundDataSource.updateSoundRelativePath(
        soundId: sound.id,
        relativePath: corrected,
        localPath: _cacheManager.localPathFor(library, corrected),
      );
    }
  }

  /// Réaligne le chemin relatif d'un son sur Drive avant téléchargement.
  Future<String> _reconcileSoundRelativePathFromDrive({
    required DriveClient client,
    required Library library,
    required Sound sound,
    required String relativePath,
  }) async {
    final remoteAtPath = await _resolveRemoteOnDrive(
      client: client,
      library: library,
      relativePath: relativePath,
    );
    if (remoteAtPath != null) return relativePath;

    final basename = p.basename(relativePath);
    final matches = await _collectDriveFilesByBasename(
      client: client,
      library: library,
      basename: basename,
    );
    if (matches.isEmpty) return relativePath;

    final corrected =
        ReconcilePathMatcher.pickBestCandidate(relativePath, matches);
    if (corrected == null || corrected == relativePath) return relativePath;

    await _soundDataSource.updateSoundRelativePath(
      soundId: sound.id,
      relativePath: corrected,
      localPath: _cacheManager.localPathFor(library, corrected),
    );
    return corrected;
  }

  Future<DriveFile?> _resolveRemoteOnDrive({
    required DriveClient client,
    required Library library,
    required String relativePath,
  }) async {
    final segments = relativePath.split('/');
    final rootId = library.driveFolderId;
    if (rootId == null) return null;
    var parentId = rootId;
    for (var i = 0; i < segments.length - 1; i++) {
      final folder = await _findDriveChildCaseInsensitive(
        client,
        parentId: parentId,
        name: segments[i],
        sharedDriveId: library.sharedDriveId,
      );
      if (folder == null || !folder.isFolder) return null;
      parentId = folder.id;
    }
    return _findDriveChildCaseInsensitive(
      client,
      parentId: parentId,
      name: segments.last,
      sharedDriveId: library.sharedDriveId,
    );
  }

  Future<DriveFile?> _findDriveChildCaseInsensitive(
    DriveClient client, {
    required String parentId,
    required String name,
    String? sharedDriveId,
  }) async {
    final exact = await client.findInFolder(
      parentId: parentId,
      name: name,
      sharedDriveId: sharedDriveId,
    );
    if (exact != null) return exact;

    final children = await client.listFolder(
      parentId,
      sharedDriveId: sharedDriveId,
    );
    for (final child in children) {
      if (PathUnicode.sameName(
        child.name.toLowerCase(),
        name.toLowerCase(),
      )) {
        return child;
      }
    }
    return null;
  }

  Future<List<String>> _collectDriveFilesByBasename({
    required DriveClient client,
    required Library library,
    required String basename,
  }) async {
    final folderId = library.driveFolderId;
    if (folderId == null) return const [];

    final matches = <String>[];
    final target = basename.toLowerCase();
    await _collectBasenameMatches(
      client,
      folderId,
      '',
      target,
      matches,
      sharedDriveId: library.sharedDriveId,
    );
    return matches;
  }

  Future<void> _collectBasenameMatches(
    DriveClient client,
    String folderId,
    String relativePrefix,
    String basenameLower,
    List<String> matches, {
    String? sharedDriveId,
  }) async {
    final children = await client.listFolder(
      folderId,
      sharedDriveId: sharedDriveId,
    );
    for (final child in children) {
      if (child.isFolder) {
        if (child.name == '.stagecue') continue;
        final subPrefix = relativePrefix.isEmpty
            ? child.name
            : '$relativePrefix/${child.name}';
        await _collectBasenameMatches(
          client,
          child.id,
          subPrefix,
          basenameLower,
          matches,
          sharedDriveId: sharedDriveId,
        );
      } else if (PathUnicode.sameName(
        child.name.toLowerCase(),
        basenameLower,
      )) {
        matches.add(
          relativePrefix.isEmpty ? child.name : '$relativePrefix/${child.name}',
        );
      }
    }
  }
}
