import 'package:flutter/material.dart';

import '../../domain/entities/sound_auto_tag.dart';
import 'tag_pill.dart';

/// Suggestions de tags de l'IA pour un son (décision 0031), avec leur confiance
/// en pourcentage, de la plus à la moins sûre.
///
/// Une suggestion n'est pas un tag : toucher une pastille l'**ajoute** aux tags
/// du son, et elle disparaît d'ici (elle est alors dans l'éditeur de tags ; la
/// retirer de là la fait revenir). Les suggestions déjà dans les tags du son
/// sont masquées. Rien n'est écrit ici — l'ajout suit l'enregistrement du
/// formulaire, comme n'importe quel tag.
class AutoTagChips extends StatelessWidget {
  final List<SoundAutoTag> suggestions;

  /// Couleur de catégorie de chaque tag (id du tag), absente = neutre.
  final Map<int, Color> colors;

  /// Ids des tags déjà dans ceux du son : leurs suggestions sont masquées.
  final Set<int> acceptedTagIds;

  /// Ajoute la suggestion touchée aux tags du son.
  final ValueChanged<SoundAutoTag> onAdd;

  const AutoTagChips({
    super.key,
    required this.suggestions,
    required this.colors,
    required this.acceptedTagIds,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final pending = [
      for (final s in suggestions)
        if (!acceptedTagIds.contains(s.tag.id)) s,
    ];
    if (pending.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in pending)
          TagPill(
            key: ValueKey('auto-tag-${s.tag.id}'),
            label: s.tag.name,
            color: colors[s.tag.id],
            suggestion: true,
            meta: percentLabel(s.score),
            onTap: () => onAdd(s),
          ),
      ],
    );
  }

  /// « 38 % » pour 0,38. Jamais « 0 % » pour une suggestion retenue : en dessous
  /// de 1 % on affiche « <1 % ».
  static String percentLabel(double score) {
    final percent = (score * 100).round();
    return percent < 1 ? '<1 %' : '$percent %';
  }
}
