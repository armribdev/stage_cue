import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Normalisation Unicode des chemins (NFC) et résolution du chemin réel sur disque.
///
/// Les noms Drive / SQLite arrivent en NFC ; Windows les matérialise souvent en
/// NFD. On stocke toujours en NFC, et on ne résout le disque qu'au moment du
/// cache local.
class PathUnicode {
  PathUnicode._();

  static String toNfc(String input) => unorm.nfc(input);

  static bool sameName(String a, String b) => toNfc(a) == toNfc(b);

  /// Retourne le chemin absolu du fichier s'il existe (exact ou équivalent NFC).
  static Future<String?> canonicalizeLocalPath(String expectedPath) async {
    final normalized = p.normalize(expectedPath);
    if (await File(normalized).exists()) return normalized;

    final parent = Directory(p.dirname(normalized));
    if (!await parent.exists()) return null;

    final expectedName = p.basename(normalized);
    await for (final entity in parent.list(followLinks: false)) {
      if (entity is File && sameName(p.basename(entity.path), expectedName)) {
        return entity.path;
      }
    }
    return null;
  }
}
