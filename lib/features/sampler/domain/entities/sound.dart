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

  /// Marqué favori par l'opérateur (accès rapide en recherche-éclair).
  final bool isFavorite;

  /// Dernière lecture (pré-écoute / déclenchement) — tri par récence.
  final DateTime? lastPlayedAt;

  /// false = type pas encore lu depuis le fichier (index Drive hors-ligne).
  final bool typeDetected;

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
    this.isFavorite = false,
    this.lastPlayedAt,
    this.typeDetected = true,
  });
}

/// Type de son
enum SoundType {
  soundEffect,
  music,
  ambiance,
}

