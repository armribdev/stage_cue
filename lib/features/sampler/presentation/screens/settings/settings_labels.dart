// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../settings_screen.dart';

/// Décomptes et libellés des dossiers indexés.
/// Méthodes de [_SettingsScreenState] extraites via extension dans le même `part`.
extension _SettingsLabels on _SettingsScreenState {
  String _normalizeWatchedPath(String path) {
    return p.normalize(path).replaceAll('\\', '/');
  }

  int _countSoundsInDirectory(String directoryPath) {
    final prefix = _normalizeWatchedPath(directoryPath);
    final pathPrefix = prefix.endsWith('/') ? prefix : '$prefix/';

    return _sounds.where((sound) {
      final soundPath = _normalizeWatchedPath(sound.filePath);
      return soundPath.startsWith(pathPrefix) || soundPath == prefix;
    }).length;
  }

  int _countSoundsForWatchedPath(db.WatchedPath watchedPath) {
    if (SafDirectoryBridge.isSafTreeUri(watchedPath.path)) {
      final marker = '/saf_watch/${watchedPath.id}/';
      return _sounds
          .where(
            (sound) => sound.filePath.replaceAll('\\', '/').contains(marker),
          )
          .length;
    }
    return _countSoundsInDirectory(watchedPath.path);
  }

  IndexedFolderLabels _labelsForWatchedPath(
    db.WatchedPath watchedPath, [
    SafTreeInfo? safInfo,
  ]) {
    final info = safInfo ?? _safFolderInfo[watchedPath.path];
    return IndexedFolderLabels.forWatchedPath(
      path: watchedPath.path,
      accountEmail: watchedPath.accountEmail,
      safDisplayName: info?.displayName,
      safDisplayPath: info?.displayPath,
    );
  }

  IndexedFolderLabels _labelsForItem(IndexedFolderItem item) {
    if (item.isLocal) {
      return _labelsForWatchedPath(item.watchedPath!);
    }

    final library = item.library!;
    return IndexedFolderLabels.forLibrary(
      name: library.name,
      drivePath: library.drivePath,
      ownerEmail: library.ownerEmail,
    );
  }

  String _driveProgressKey(int libraryId, [String? pendingName]) {
    if (libraryId < 0 && pendingName != null) {
      return 'drive:pending:$pendingName';
    }
    return 'drive:$libraryId';
  }

  int _countSoundsInLibrary(int libraryId) {
    return _sounds.where((sound) => sound.libraryId == libraryId).length;
  }

  List<IndexedFolderItem> _indexedFolderItems() {
    final items = <IndexedFolderItem>[
      for (final watchedPath in _watchedPaths)
        if (watchedPath.isDirectory) IndexedFolderItem.local(watchedPath),
      for (final library in _libraries) IndexedFolderItem.drive(library),
    ];
    items.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return items;
  }

  IndexingProgress _progressForItem(IndexedFolderItem item) {
    final key = item.isLocal
        ? _normalizeWatchedPath(item.watchedPath!.path)
        : _driveProgressKey(item.library!.id, item.library!.name);

    final live =
        _indexingProgress[key] ??
        (item.isLocal
            ? null
            : _indexingProgress[_driveProgressKey(-1, item.library!.name)]);

    if (live != null) {
      return live;
    }

    if (item.isLocal) {
      final soundCount = _countSoundsForWatchedPath(item.watchedPath!);
      return IndexingProgress(
        path: item.watchedPath!.path,
        current: soundCount,
        total: soundCount,
        isComplete: true,
      );
    }

    final soundCount = _countSoundsInLibrary(item.library!.id);
    return IndexingProgress(
      path: item.library!.name,
      current: soundCount,
      total: soundCount,
      isComplete: true,
    );
  }
}
