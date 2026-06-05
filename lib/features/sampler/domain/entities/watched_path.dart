/// Entité métier représentant un dossier local surveillé pour l'indexation.
class WatchedPath {
  final int id;
  final String path;
  /// Toujours `true` : seuls les dossiers locaux sont indexés via cette entité.
  final bool isDirectory;
  final String? accountEmail;
  final String? driveFileId;
  final DateTime addedAt;

  WatchedPath({
    required this.id,
    required this.path,
    required this.isDirectory,
    this.accountEmail,
    this.driveFileId,
    required this.addedAt,
  });
}

