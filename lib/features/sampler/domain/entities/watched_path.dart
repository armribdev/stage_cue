/// Entité métier représentant un chemin surveillé (dossier ou fichier)
class WatchedPath {
  final int id;
  final String path;
  final bool isDirectory;
  final DateTime addedAt;

  WatchedPath({
    required this.id,
    required this.path,
    required this.isDirectory,
    required this.addedAt,
  });
}

