import 'tag_item.dart';

/// Tag suggéré par l'analyse automatique pour un son (décisions 0030 et 0031).
///
/// [score] : confiance relative du modèle, entre 0 et 1 — pas une probabilité
/// calibrée. Une suggestion n'est pas un tag : elle n'entre dans les tags du son
/// que si l'utilisateur l'accepte.
class SoundAutoTag {
  final TagItem tag;
  final double score;

  const SoundAutoTag({required this.tag, required this.score});
}
