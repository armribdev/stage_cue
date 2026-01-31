/// Entité métier représentant une soundboard
class SoundBoard {
  final int id;
  final String name;
  final DateTime createdAt;

  SoundBoard({
    required this.id,
    required this.name,
    required this.createdAt,
  });
}
