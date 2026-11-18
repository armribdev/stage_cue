import 'sound.dart' show SoundType;

/// Catégorie de tags (ex: ACTION, OBJET)
class TagCategory {
  final int id;
  final String name;
  final int color;
  final int sortOrder;
  final String? description;

  TagCategory({
    required this.id,
    required this.name,
    required this.color,
    required this.sortOrder,
    this.description,
  });
}

/// Types de son pour lesquels une catégorie de tags **se suggère** (décision
/// 0041). Une affinité, pas une règle : l'utilisateur peut poser n'importe quel
/// tag sur n'importe quel son, seules les suggestions déduites du titre s'y
/// tiennent. Une catégorie absente (créée par l'utilisateur) n'a pas
/// d'affinité connue et se suggère toujours.
const Map<String, Set<SoundType>> kTagCategorySoundTypes = {
  'ACTION': {SoundType.soundEffect},
  'OBJET': {SoundType.soundEffect},
  'MATIERE': {SoundType.soundEffect, SoundType.ambiance},
  'AMBIANCE': {SoundType.ambiance, SoundType.music},
  'EMOTION_STYLE': {SoundType.music, SoundType.ambiance},
};

/// Vrai si une suggestion de la catégorie [category] a du sens pour un son de
/// type [type]. Un type inconnu (son pas encore téléchargé) ne filtre rien.
bool tagCategoryFitsSoundType(String category, SoundType? type) {
  if (type == null) return true;
  final types = kTagCategorySoundTypes[category];
  return types == null || types.contains(type);
}
