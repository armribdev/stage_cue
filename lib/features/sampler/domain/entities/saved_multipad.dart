import 'pad.dart';
import 'sound.dart';

/// Multipad enregistré dans la bibliothèque : un modèle (nom, couleur, mode de
/// lecture, sons dans l'ordre) qu'on repose sur un plateau en pad ordinaire.
///
/// C'est une copie, pas un lien : modifier le pad posé ne change pas le modèle,
/// et modifier le modèle ne change pas les pads déjà posés (décision 0051).
class SavedMultipad {
  final int id;
  final String name;
  final int? colorValue;
  final PadPlayMode playMode;
  final List<Sound> sounds;

  const SavedMultipad({
    required this.id,
    required this.name,
    this.colorValue,
    this.playMode = PadPlayMode.random,
    this.sounds = const [],
  });

  /// Vrai si tous les sons sont du [type] demandé (filtre de la recherche).
  /// Un modèle sans son ne correspond à aucun type.
  bool hasOnlyType(SoundType type) =>
      sounds.isNotEmpty && sounds.every((sound) => sound.type == type);

  /// Type commun à tous les sons, `null` si mixte, sans son ou non classé.
  SoundType? get commonType {
    final first = sounds.firstOrNull?.type;
    if (first == null) return null;
    return hasOnlyType(first) ? first : null;
  }
}
