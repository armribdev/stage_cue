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
  final DateTime createdAt;
  final List<Sound> sounds;

  /// Override de volume par son, aligné par index sur [sounds]. Un élément null
  /// (ou un index hors bornes) signifie « suivre le volume par défaut du son ».
  /// Remplace l'ancien volume unique par pad.
  final List<double?> soundVolumes;

  const Pad({
    required this.id,
    required this.boardId,
    this.name,
    this.colorValue,
    required this.sortOrder,
    this.rowIndex = 0,
    this.playMode = PadPlayMode.random,
    required this.createdAt,
    this.sounds = const [],
    this.soundVolumes = const [],
  });

  /// Volume effectif du son à [index] : l'override du pad s'il existe, sinon le
  /// volume par défaut du son. Défensif face aux listes désalignées (brouillons).
  double effectiveVolume(int index) {
    if (index < 0 || index >= sounds.length) return 1.0;
    final override =
        index < soundVolumes.length ? soundVolumes[index] : null;
    return override ?? sounds[index].volume;
  }

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
    List<Sound>? sounds,
    List<double?>? soundVolumes,
  }) {
    return Pad(
      id: id,
      boardId: boardId,
      name: clearName ? null : (name ?? this.name),
      colorValue: clearColor ? null : (colorValue ?? this.colorValue),
      sortOrder: sortOrder ?? this.sortOrder,
      rowIndex: rowIndex ?? this.rowIndex,
      playMode: playMode ?? this.playMode,
      createdAt: createdAt,
      sounds: sounds ?? this.sounds,
      soundVolumes: soundVolumes ?? this.soundVolumes,
    );
  }
}
