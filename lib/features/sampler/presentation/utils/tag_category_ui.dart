import '../../domain/entities/tag_category.dart';

/// Libellés d'affichage pour les catégories de tags.
///
/// Les noms en base sont des clés techniques (ex. 'ACTION', 'OBJET').
/// Cette extension fournit un label localisé réutilisable dans toute l'UI.
/// Les catégories inconnues (créées par l'utilisateur) retombent sur le
/// nom brut mis en forme.
extension TagCategoryUi on TagCategory {
  String get displayLabel => switch (name) {
        'ACTION' => 'Actions',
        'OBJET' => 'Objets',
        'MUSIQUE' => 'Musique',
        _ => _toSentenceCase(name),
      };
}

String _toSentenceCase(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1).toLowerCase();
}
