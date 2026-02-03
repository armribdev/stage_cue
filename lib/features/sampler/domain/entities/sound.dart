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

  Sound({
    required this.id,
    required this.title,
    this.displayName,
    required this.filePath,
    required this.type,
    this.colorValue,
    this.volume = 1.0,
    required this.createdAt,
  });
}

/// Type de son
enum SoundType {
  soundEffect,
  music,
  ambiance,
}

