import 'package:path/path.dart' as p;

import '../platform/saf_directory_bridge.dart';

/// Libellés d'affichage unifiés pour un dossier indexé (local ou Drive).
class IndexedFolderLabels {
  final String title;
  final String subtitle;

  const IndexedFolderLabels({
    required this.title,
    required this.subtitle,
  });

  /// Dossier local ou cloud indexé via [WatchedPaths].
  factory IndexedFolderLabels.forWatchedPath({
    required String path,
    String? accountEmail,
    String? safDisplayName,
    String? safDisplayPath,
  }) {
    if (SafDirectoryBridge.isSafTreeUri(path)) {
      final name = safDisplayName?.trim().isNotEmpty == true
          ? safDisplayName!.trim()
          : 'Dossier cloud';
      final drivePath = safDisplayPath?.trim() ?? '';
      return IndexedFolderLabels(
        title: name,
        subtitle: _driveSubtitle(
          ownerEmail: accountEmail,
          drivePath: drivePath,
          fallback: path,
        ),
      );
    }

    return IndexedFolderLabels(
      title: p.basename(path),
      subtitle: path,
    );
  }

  /// Bibliothèque Drive indexée via [Libraries].
  factory IndexedFolderLabels.forLibrary({
    required String name,
    String? drivePath,
    String? ownerEmail,
  }) {
    final resolvedPath = drivePath?.trim() ?? '';
    final resolvedOwner = ownerEmail?.trim().isNotEmpty == true
        ? ownerEmail!.trim()
        : null;

    return IndexedFolderLabels(
      title: name.trim().isNotEmpty ? name.trim() : 'Dossier Drive',
      subtitle: _driveSubtitle(
        ownerEmail: resolvedOwner,
        drivePath: resolvedPath,
        fallback: resolvedPath.isNotEmpty ? resolvedPath : 'Drive',
      ),
    );
  }

  static String _driveSubtitle({
    required String? ownerEmail,
    required String drivePath,
    required String fallback,
  }) {
    final normalizedPath = normalizeDrivePathForDisplay(drivePath);
    if (ownerEmail != null &&
        ownerEmail.isNotEmpty &&
        normalizedPath.isNotEmpty) {
      return '$ownerEmail/$normalizedPath';
    }
    if (normalizedPath.isNotEmpty) {
      return normalizedPath;
    }
    if (ownerEmail != null && ownerEmail.isNotEmpty) {
      return ownerEmail;
    }
    return fallback;
  }
}

/// Normalise un chemin Drive pour l'affichage (sans espaces autour des `/`).
String normalizeDrivePathForDisplay(String path) {
  return path
      .replaceAll('\\', '/')
      .split(RegExp(r'\s*/\s*'))
      .where((segment) => segment.isNotEmpty)
      .join('/');
}

/// Extrait le chemin relatif Drive depuis un fil d'Ariane « Mon Drive / … ».
String relativeDrivePathFromBreadcrumb(String displayPath) {
  const root = 'Mon Drive';
  final trimmed = displayPath.trim();
  if (trimmed == root) {
    return '';
  }
  if (trimmed.startsWith('$root / ')) {
    return trimmed.substring(root.length + 3);
  }
  return trimmed;
}

/// Dérive nom + chemin depuis un ancien libellé « Mon Drive / A / B ».
({String name, String? drivePath}) parseLegacyLibraryName(String storedName) {
  final trimmed = storedName.trim();
  if (trimmed.isEmpty) {
    return (name: 'Dossier Drive', drivePath: null);
  }

  final drivePath = relativeDrivePathFromBreadcrumb(trimmed);
  if (drivePath != trimmed && drivePath.isNotEmpty) {
    final segments = drivePath.split(' / ');
    return (name: segments.last, drivePath: drivePath);
  }

  if (trimmed.contains(' / ')) {
    final segments = trimmed.split(' / ');
    return (name: segments.last, drivePath: trimmed);
  }

  return (name: trimmed, drivePath: null);
}
