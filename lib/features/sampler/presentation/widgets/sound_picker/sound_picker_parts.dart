// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../sound_picker_overlay.dart';

/// Éléments partagés : pied d'aide, tags, bouton icône rond.
/// Méthodes de [_SoundPickerOverlayState] extraites via extension dans le même `part`.
extension _SoundPickerParts on _SoundPickerOverlayState {

  Widget _buildHints(ColorScheme scheme, bool hasResults) {
    if (!hasResults) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Text(
        _hintsText,
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
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

  Widget _buildTagRow(ColorScheme scheme, List<TagItem> tags) {
    final visible = tags.take(_maxVisibleTags).toList();
    final overflow = tags.length - visible.length;
    return Row(
      children: [
        for (final tag in visible) ...[
          _buildTagChip(scheme, tag),
          const SizedBox(width: 4),
        ],
        if (overflow > 0)
          Text(
            '+$overflow',
            style: TextStyle(
              fontSize: 10,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
      ],
    );
  }

  Widget _buildTagChip(ColorScheme scheme, TagItem tag) {
    final color = _categoryColor(tag.categoryId);
    final matchingTokens = _highlightTokens
        .where((t) => tag.normalizedName.contains(t))
        .toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color?.withAlpha(24),
        borderRadius: BorderRadius.circular(4),
        border: color == null ? null : Border.all(color: color),
      ),
      child: Text.rich(
        buildHighlightedSpan(tag.name, matchingTokens),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10, color: color ?? scheme.onSurfaceVariant),
      ),
    );
  }

  // ── Bouton icône rond partagé ─────────────────────────────────────────────

  Widget _roundIconButton({
    required ColorScheme scheme,
    required IconData icon,
    required VoidCallback? onPressed,
    required Color iconColor,
    bool active = false,
    // Désactive tout fond (actif ou survol) — seule la couleur d'icône
    // porte l'état. Pour les toggles serrés type favoris/hors-ligne.
    bool flat = false,
  }) {
    // ExcludeFocus : empêche ce bouton de voler le focus au champ de
    // recherche (sinon Flutter le regagnerait en sélectionnant tout le
    // texte, comme un Tab desktop).
    return ExcludeFocus(
      child: SizedBox(
        width: _actionButtonSize,
        height: _actionButtonSize,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            shape: const CircleBorder(),
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
