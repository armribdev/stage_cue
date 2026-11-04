import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../domain/entities/sound_auto_tag.dart';

/// Suggestions de tags de l'IA pour un son (décision 0031), **toujours
/// affichées** avec leur confiance en pourcentage, de la plus à la moins sûre.
///
/// Une suggestion n'est pas un tag : toucher une pastille l'**ajoute** aux tags
/// du son (elle apparaît alors cochée), la retoucher la retire. Rien n'est écrit
/// ici — l'ajout suit l'enregistrement du formulaire, comme n'importe quel tag.
class AutoTagChips extends StatelessWidget {
  final List<SoundAutoTag> suggestions;

  /// Couleur de catégorie de chaque tag (id du tag), absente = neutre.
  final Map<int, Color> colors;

  /// Ids des tags déjà dans ceux du son.
  final Set<int> acceptedTagIds;

  /// Bascule l'acceptation de la suggestion touchée.
  final ValueChanged<SoundAutoTag> onToggle;

  const AutoTagChips({
    super.key,
    required this.suggestions,
    required this.colors,
    required this.acceptedTagIds,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome_outlined, size: 14, color: scheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Suggestions de l’IA d’après le son — touchez pour ajouter. '
                'Le pourcentage est sa confiance relative, pas une certitude.',
                style: muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in suggestions)
              FilterChip(
                key: ValueKey('auto-tag-${s.tag.id}'),
                showCheckmark: true,
                selected: acceptedTagIds.contains(s.tag.id),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s.tag.name),
                    const SizedBox(width: 6),
                    Text(
                      percentLabel(s.score),
                      style: AppFonts.monoStyle(
                        (textTheme.bodySmall ?? const TextStyle()).copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                backgroundColor: colors[s.tag.id]?.withAlpha(24),
                side: colors[s.tag.id] == null
                    ? null
                    : BorderSide(color: colors[s.tag.id]!),
                onSelected: (_) => onToggle(s),
              ),
          ],
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
