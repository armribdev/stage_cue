// Modèles indépendants du SDK pour représenter des fichiers/dossiers distants.
//
// Le reste de l'application manipule ces types, jamais directement les classes
// `googleapis`. Cela isole le SDK Google derrière la couche `core/sync`.

/// Type MIME d'un dossier Google Drive.
const String driveFolderMimeType = 'application/vnd.google-apps.folder';

/// Drive d'équipe (partagé) accessible via l'API `drives.list`.
class DriveSharedDrive {
  final String id;
  final String name;

  const DriveSharedDrive({
    required this.id,
    required this.name,
  });
}

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

/// Un changement Drive depuis un jeton de page donné.
///
/// [removed] agrège les trois façons dont un fichier peut disparaître de notre
/// vue : suppression définitive, mise à la corbeille, ou retrait des droits.
/// L'appelant n'a donc jamais à les distinguer.
class DriveChange {
  final String fileId;
  final bool removed;

  /// Métadonnées si le fichier est encore accessible ; `null` si [removed].
  final DriveFile? file;

  /// Parent direct du fichier, quand Drive le renvoie.
  final String? parentId;

  /// Vrai si le changement porte sur un DOSSIER : il peut alors remodeler le
  /// chemin de tout un sous-arbre, ce qu'un delta ne sait pas appliquer seul.
  final bool isFolder;

  const DriveChange({
    required this.fileId,
    required this.removed,
    this.file,
    this.parentId,
    this.isFolder = false,
  });
}

/// Une page de résultats de `changes.list`.
class DriveChangePage {
  final List<DriveChange> changes;

  /// Page suivante du même parcours, ou `null` si c'était la dernière.
  final String? nextPageToken;

  /// Jeton à mémoriser pour le PROCHAIN parcours. Fourni uniquement sur la
  /// dernière page.
  final String? newStartPageToken;

  const DriveChangePage({
    required this.changes,
    this.nextPageToken,
    this.newStartPageToken,
  });
}
