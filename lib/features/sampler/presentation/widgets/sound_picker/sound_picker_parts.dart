// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../sound_picker_overlay.dart';

/// Éléments partagés : pied d'aide, tags, bouton icône rond.
/// Méthodes de [_SoundPickerOverlayState] extraites via extension dans le même `part`.
extension _SoundPickerParts on _SoundPickerOverlayState {
  Widget _buildHints(ColorScheme scheme, bool hasResults) {
    if (!hasResults) return const SizedBox.shrink();
    final labelStyle = TextStyle(fontSize: 11, color: scheme.onSurfaceVariant);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: AppElevation.border(scheme)),
      ),
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (keys, label) in _hints)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (keys.isNotEmpty) ...[
                  _KeyCap(keys),
                  const SizedBox(width: AppSpacing.xs + 2),
                ],
                Text(label, style: labelStyle),
              ],
            ),
        ],
      ),
    );
  }

  // ── Affichage des tags ────────────────────────────────────────────────────

  Color? _categoryColor(int categoryId) {
    for (final group in _tagCatalog) {
      if (group.category.id == categoryId) return Color(group.category.color);
    }
    return null;
  }

  Widget _buildTagRow(List<TagItem> tags) {
    return TagPillRow(
      compact: true,
      maxVisible: _maxVisibleTags,
      tags: [
        for (final tag in tags)
          (
            label: buildHighlightedSpan(
              tag.name,
              _highlightTokens
                  .where((t) => tag.normalizedName.contains(t))
                  .toList(),
            ),
            color: _categoryColor(tag.categoryId),
          ),
      ],
    );
  }

  // ── Bouton icône rond partagé ─────────────────────────────────────────────

  Widget _roundIconButton({
    required ColorScheme scheme,
    IconData? icon,
    // Glyphe de transport plein (lecture/pause) à la place d'une icône Lucide.
    TransportGlyph? transport,
    required VoidCallback? onPressed,
    required Color iconColor,
    bool active = false,
    // Désactive tout fond (actif ou survol) — seule la couleur d'icône
    // porte l'état. Pour les toggles serrés type favoris/hors-ligne.
    bool flat = false,
  }) {
    assert((icon == null) != (transport == null));
    // ExcludeFocus : empêche ce bouton de voler le focus au champ de
    // recherche (sinon Flutter le regagnerait en sélectionnant tout le
    // texte, comme un Tab desktop).
    return ExcludeFocus(
      child: SizedBox(
        width: _actionButtonSize,
        height: _actionButtonSize,
        child: IconButton(
          onPressed: onPressed,
          icon: transport != null
              ? TransportIcon(transport, size: AppIconSize.sm)
              : Icon(icon, size: AppIconSize.sm),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusMd),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: !flat && active
                ? scheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            hoverColor: flat
                ? Colors.transparent
                : scheme.onSurface.withValues(alpha: 0.08),
            foregroundColor: iconColor,
          ),
          constraints: const BoxConstraints.tightFor(
            width: _actionButtonSize,
            height: _actionButtonSize,
          ),
        ),
      ),
    );
  }

  String _typeLabel(SoundType? type) => type?.label ?? 'Non classé';
}

/// Touche de clavier d'un pied d'aide : hairline, mono, discrète — une touche
/// se lit comme une touche, pas comme du texte courant.
class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: AppRadius.radiusXs,
        border: Border.fromBorderSide(AppElevation.borderStrong(scheme)),
      ),
      child: Text(
        label,
        style: AppFonts.monoStyle(
          TextStyle(fontSize: 12, color: scheme.onSurface),
        ),
      ),
    );
  }
}
