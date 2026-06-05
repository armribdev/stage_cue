/// Entité métier représentant un son
class Sound {
  final int id;
  final String title;
  final String? displayName;
  final String filePath;
  final SoundType type;
  final int? colorValue;
  final double volume;
  final DateTime createdAt;

  /// Bibliothèque d'appartenance ; `null` = son purement local (legacy).
  final int? libraryId;

  /// Chemin relatif à la racine de la bibliothèque ; `null` pour les sons locaux.
  final String? relativePath;

  /// Empreinte de contenu pour réidentifier un fichier déplacé/renommé.
  final String? contentHash;

  Sound({
    required this.id,
    required this.title,
    this.displayName,
    required this.filePath,
    required this.type,
    this.colorValue,
    this.volume = 1.0,
    required this.createdAt,
    this.libraryId,
    this.relativePath,
    this.contentHash,
  });
}

/// Type de son
enum SoundType {
  soundEffect,
  music,
  ambiance,
}

