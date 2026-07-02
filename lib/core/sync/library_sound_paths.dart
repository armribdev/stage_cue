import 'package:path/path.dart' as p;

import '../utils/path_unicode.dart';

/// Chemins des sons d'une bibliothèque portable synchronisable.
///
/// **Identité portable** : `(libraryId, relativePath)` — miroir exact de la
/// structure du dossier Drive lié.
///
/// **`filePath`** en base est dérivé et propre à l'appareil :
/// `{localRootPath}/{relativePath}` (segments séparés par `/` dans
/// [relativePath], convertis au séparateur de la plateforme ici).
class LibrarySoundPaths {
  LibrarySoundPaths._();

  static const String _legacySoundsPrefix = 'sounds/';

  /// Chemin local absolu dans le cache d'une bibliothèque.
  static String localPathFor(String localRootPath, String relativePath) {
    return p.joinAll([localRootPath, ...relativePath.split('/')]);
  }

  /// Normalise un chemin relatif (préfixe `sounds/` legacy + NFC portable).
  static String normalizeRelativePath(String relativePath) {
    var path = relativePath;
    if (path.startsWith(_legacySoundsPrefix)) {
      path = path.substring(_legacySoundsPrefix.length);
    }
    return PathUnicode.toNfc(path);
  }
}
