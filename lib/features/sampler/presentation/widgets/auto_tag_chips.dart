import 'package:flutter/material.dart';

import '../../domain/entities/sound_auto_tag.dart';
import '../../domain/entities/tag_item.dart';
import 'animated_pill_wrap.dart';
import 'tag_pill.dart';

/// Un tag que le titre du son désigne, avec les mots du titre qui l'ont désigné.
typedef TitleTagSuggestion = ({TagItem tag, String word});

/// Suggestions de tags pour un son : celles de l'IA (décision 0031), de la plus
/// à la moins sûre mais sans afficher le score (décision 0042), puis celles
/// déduites du titre (décision 0041) ; leur infobulle donne le mot trouvé.
///
/// Une suggestion n'est pas un tag : toucher une pastille l'**ajoute** aux tags
/// du son, et elle disparaît d'ici (elle est alors dans l'éditeur de tags ; la
/// retirer de là la fait revenir). Les suggestions déjà dans les tags du son
/// sont masquées. Rien n'est écrit ici — l'ajout suit l'enregistrement du
/// formulaire, comme n'importe quel tag.
class AutoTagChips extends StatelessWidget {
  final List<SoundAutoTag> suggestions;

  /// Tags déduits du titre. Un tag déjà proposé par l'IA n'y figure pas : la
  /// pastille de l'IA prime.
  final List<TitleTagSuggestion> titleSuggestions;

  /// Couleur de catégorie de chaque tag (id du tag), absente = neutre.
  final Map<int, Color> colors;

  /// Ids des tags déjà dans ceux du son : leurs suggestions sont masquées.
  final Set<int> acceptedTagIds;

  /// Ajoute le tag de la suggestion touchée aux tags du son.
  final ValueChanged<TagItem> onAdd;

  /// Suggestions du formulaire précédent et animation du passage de l'une à
  /// l'autre (voir [AnimatedPillWrap.memory]). `null` = pas de suite.
  final PillMemory? memory;
  final bool animateInitial;

  const AutoTagChips({
    super.key,
    required this.suggestions,
    this.titleSuggestions = const [],
    required this.colors,
    required this.acceptedTagIds,
    required this.onAdd,
    this.memory,
    this.animateInitial = false,
  });

  @override
  Widget build(BuildContext context) {
    final pending = [
      for (final s in suggestions)
        if (!acceptedTagIds.contains(s.tag.id)) s,
    ];
    final pendingFromTitle = [
      for (final s in titleSuggestions)
        if (!acceptedTagIds.contains(s.tag.id)) s,
    ];
    // Toujours rendu, même vide : une suggestion qui part (touchée, ou devenue
    // tag) se referme en s'animant au lieu de disparaître d'un coup.
    return AnimatedPillWrap(
      memory: memory,
      animateInitial: animateInitial,
      entries: [
        for (final s in pending)
          PillEntry(
            ValueKey('auto-tag-${s.tag.id}'),
            TagPill(
              key: ValueKey('auto-tag-${s.tag.id}'),
              label: s.tag.name,
              color: colors[s.tag.id],
              suggestion: true,
              onTap: () => onAdd(s.tag),
            ),
          ),
        for (final s in pendingFromTitle)
          PillEntry(
            ValueKey('title-tag-${s.tag.id}'),
            Tooltip(
              message: 'Trouvé dans le titre : « ${s.word} »',
              child: TagPill(
                key: ValueKey('title-tag-${s.tag.id}'),
                label: s.tag.name,
                color: colors[s.tag.id],
                suggestion: true,
                onTap: () => onAdd(s.tag),
              ),
            ),
          ),
      ],
    );
  }
}
