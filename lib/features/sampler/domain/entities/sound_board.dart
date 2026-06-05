/// Entité métier représentant une soundboard
class SoundBoard {
  final int id;
  final String name;
  final int? libraryId;
  final DateTime createdAt;

  SoundBoard({
    required this.id,
    required this.name,
    this.libraryId,
    required this.createdAt,
  });
}
