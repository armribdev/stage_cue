import 'sound.dart';

enum PadPlayMode { random, sequential }

class Pad {
  final int id;
  final int boardId;
  final String? name;
  final int? colorValue;
  final int sortOrder;
  final PadPlayMode playMode;
  final double volume;
  final DateTime createdAt;
  final List<Sound> sounds;

  const Pad({
    required this.id,
    required this.boardId,
    this.name,
    this.colorValue,
    required this.sortOrder,
    this.playMode = PadPlayMode.random,
    this.volume = 1.0,
    required this.createdAt,
    this.sounds = const [],
  });

  String get displayName {
    if (name != null && name!.isNotEmpty) return name!;
    if (sounds.isNotEmpty) {
      return sounds.first.displayName ?? sounds.first.title;
    }
    return 'Pad';
  }

  Pad copyWith({
    String? name,
    bool clearName = false,
    int? colorValue,
    bool clearColor = false,
    PadPlayMode? playMode,
    double? volume,
    List<Sound>? sounds,
  }) {
    return Pad(
      id: id,
      boardId: boardId,
      name: clearName ? null : (name ?? this.name),
      colorValue: clearColor ? null : (colorValue ?? this.colorValue),
      sortOrder: sortOrder,
      playMode: playMode ?? this.playMode,
      volume: volume ?? this.volume,
      createdAt: createdAt,
      sounds: sounds ?? this.sounds,
    );
  }
}
