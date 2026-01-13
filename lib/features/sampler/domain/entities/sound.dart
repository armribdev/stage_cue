/// Entité métier représentant un son
class Sound {
  final int id;
  final String title;
  final String filePath;
  final SoundType type;
  final DateTime createdAt;

  Sound({
    required this.id,
    required this.title,
    required this.filePath,
    required this.type,
    required this.createdAt,
  });
}

/// Type de son
enum SoundType {
  soundEffect,
  music,
  ambiance,
}

