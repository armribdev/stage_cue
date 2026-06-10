import 'sound.dart';

enum PadPlayMode { random, sequential }

class Pad {
  final int id;
  final int boardId;
  final String? name;
  final int? colorValue;
  final int sortOrder;
  final int rowIndex;
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
    this.rowIndex = 0,
    this.playMode = PadPlayMode.random,
    this.volume = 1.0,
    required this.createdAt,
    this.sounds = const [],
  });

  /// Numéros 1-based des multipads dans l'ordre d'affichage du plateau.
  static Map<int, int> multipadNumbersFor(Iterable<Pad> padsInBoardOrder) {
    var index = 0;
    final numbers = <int, int>{};
    for (final pad in padsInBoardOrder) {
      if (pad.sounds.length > 1) {
        index++;
        numbers[pad.id] = index;
      }
    }
    return numbers;
  }

  String get displayName => resolveDisplayName();

  String resolveDisplayName({int? multipadNumber}) {
    if (name != null && name!.isNotEmpty) return name!;
    if (sounds.length > 1) {
      final number = multipadNumber;
      return number != null ? 'Multipad #$number' : 'Multipad';
    }
    if (sounds.isNotEmpty) {
      return sounds.first.displayName ?? sounds.first.title;
    }
    return 'Pad';
  }

  /// Vrai si le pad ne contient que des sons de type musique.
  bool get isMusicPad =>
      sounds.isNotEmpty &&
      sounds.every((sound) => sound.type == SoundType.music);

  Pad copyWith({
    String? name,
    bool clearName = false,
    int? colorValue,
    bool clearColor = false,
    int? sortOrder,
    int? rowIndex,
    PadPlayMode? playMode,
    double? volume,
    List<Sound>? sounds,
  }) {
    return Pad(
      id: id,
      boardId: boardId,
      name: clearName ? null : (name ?? this.name),
      colorValue: clearColor ? null : (colorValue ?? this.colorValue),
      sortOrder: sortOrder ?? this.sortOrder,
      rowIndex: rowIndex ?? this.rowIndex,
      playMode: playMode ?? this.playMode,
      volume: volume ?? this.volume,
      createdAt: createdAt,
      sounds: sounds ?? this.sounds,
    );
  }
}
