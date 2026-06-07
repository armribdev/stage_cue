/// Entité métier représentant une soundboard
class SoundBoard {
  final int id;
  final String name;
  final int? color;
  final int? icon;
  final int? libraryId;
  final DateTime createdAt;

  SoundBoard({
    required this.id,
    required this.name,
    this.color,
    this.icon,
    this.libraryId,
    required this.createdAt,
  });

  SoundBoard copyWith({
    int? id,
    String? name,
    Object? color = _sentinel,
    Object? icon = _sentinel,
    Object? libraryId = _sentinel,
    DateTime? createdAt,
  }) {
    return SoundBoard(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color == _sentinel ? this.color : color as int?,
      icon: icon == _sentinel ? this.icon : icon as int?,
      libraryId: libraryId == _sentinel ? this.libraryId : libraryId as int?,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

const _sentinel = Object();
