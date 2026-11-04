/// Suggestion de l'analyse automatique avant enregistrement : le nom d'un tag
/// **existant** et la confiance du modèle, entre 0 et 1 (décision 0031).
class AutoTagSuggestion {
  final String tagName;
  final double score;
  const AutoTagSuggestion(this.tagName, this.score);
}
