import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../domain/entities/sound_auto_tag.dart';

/// Tags trouvés par l'IA pour un son (décision 0030) : ceux qui comptent, que
/// l'on peut **masquer** d'un geste, puis ceux déjà masqués, que l'on peut
/// **rétablir**. Masquer ne supprime rien : l'IA garde la mémoire et ne repose
/// pas le tag.
class AutoTagChips extends StatelessWidget {
  final List<SoundAutoTag> tags;

  /// Couleur de catégorie de chaque tag (id du tag), absente = neutre.
  final Map<int, Color> colors;

  /// Le son est encore « à traiter » : l'IA peut s'être trompée, on invite à
  /// vérifier avant de valider.
  final bool awaitingValidation;
  final ValueChanged<SoundAutoTag> onHide;
  final ValueChanged<SoundAutoTag> onRestore;

  const AutoTagChips({
    super.key,
    required this.tags,
    required this.colors,
    required this.awaitingValidation,
    required this.onHide,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final visible = [
      for (final t in tags)
        if (!t.hidden) t,
    ];
    final hidden = [
      for (final t in tags)
        if (t.hidden) t,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome_outlined, size: 14, color: scheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                awaitingValidation && visible.isNotEmpty
                    ? 'Trouvés par l’IA d’après le son — vérifiez-les, puis '
                          'validez. Un tag masqué reste en mémoire.'
                    : 'Trouvés par l’IA d’après le son. Un tag masqué reste '
                          'en mémoire.',
                style: muted,
              ),
            ),
          ],
        ),
        if (visible.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in visible)
                InputChip(
                  key: ValueKey('auto-tag-${t.tag.id}'),
                  avatar: Icon(
                    Icons.auto_awesome_outlined,
                    size: 14,
                    color: scheme.primary,
                  ),
                  label: Text(t.tag.name),
                  backgroundColor: colors[t.tag.id]?.withAlpha(24),
                  side: colors[t.tag.id] == null
                      ? null
                      : BorderSide(color: colors[t.tag.id]!),
                  deleteButtonTooltipMessage: 'Masquer ce tag',
                  onDeleted: () => onHide(t),
                ),
            ],
          ),
        ],
        if (hidden.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Masqués', style: muted),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in hidden)
                Tooltip(
                  message: 'Rétablir ce tag',
                  child: ActionChip(
                    key: ValueKey('auto-tag-hidden-${t.tag.id}'),
                    avatar: Icon(
                      Icons.undo,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    label: Text(
                      t.tag.name,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    side: BorderSide(color: AppElevation.border(scheme).color),
                    onPressed: () => onRestore(t),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
