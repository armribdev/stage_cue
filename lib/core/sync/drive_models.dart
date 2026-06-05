// Modèles indépendants du SDK pour représenter des fichiers/dossiers distants.
//
// Le reste de l'application manipule ces types, jamais directement les classes
// `googleapis`. Cela isole le SDK Google derrière la couche `core/sync`.

/// Type MIME d'un dossier Google Drive.
const String driveFolderMimeType = 'application/vnd.google-apps.folder';

/// Référence vers un fichier ou dossier distant.
class DriveFile {
  final String id;
  final String name;
  final String? mimeType;
  final DateTime? modifiedTime;
  final int? size;
  final String? md5Checksum;

  const DriveFile({
    required this.id,
    required this.name,
    this.mimeType,
    this.modifiedTime,
    this.size,
    this.md5Checksum,
  });

  bool get isFolder => mimeType == driveFolderMimeType;
}
