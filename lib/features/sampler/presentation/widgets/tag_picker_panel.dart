import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/layout_utils.dart';
import '../../../../core/utils/string_utils.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';
import '../utils/tag_category_ui.dart';
import 'boxed_icon_button.dart';

// ── Bouton d'ajout ────────────────────────────────────────────────────────────

/// Bouton « + Tag » en fin de rangée d'étiquettes : même gabarit qu'une
/// étiquette, en filet seul. Ouvert, il prend l'accent et la croix (le « + »
/// pivote de 45°).
class TagAddButton extends StatefulWidget {
  final bool open;

  /// Libellé long (« Ajouter un tag ») quand aucun tag n'est encore posé.
  final bool verbose;
  final VoidCallback onPressed;

  const TagAddButton({
    super.key,
    required this.open,
    required this.verbose,
    required this.onPressed,
  });

  @override
  State<TagAddButton> createState() => _TagAddButtonState();
}

class _TagAddButtonState extends State<TagAddButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final open = widget.open;
    final color = open
        ? scheme.primary
        : (_hovered ? scheme.onSurface : scheme.onSurfaceVariant);
    return Semantics(
      button: true,
      child: Tooltip(
        message: open ? 'Fermer la liste des tags' : 'Ajouter un tag',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: open
                    ? AppColors.accentSoft
                    : (_hovered
                          ? scheme.onSurface.withAlpha(12)
                          : Colors.transparent),
                borderRadius: AppRadius.radiusMd,
                border: Border.all(
                  color: open
                      ? AppColors.accentLine
                      : AppElevation.borderStrong(scheme).color,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedRotation(
                    turns: open ? 0.125 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(Icons.add, size: 16, color: color),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.verbose ? 'Ajouter un tag' : 'Tag',
                    style: TextStyle(
                      fontFamily: AppFonts.ui,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Panneau d'ajout ───────────────────────────────────────────────────────────

/// Panneau d'ajout de tags, façon palette de commandes : recherche sans cadre
/// en tête, onglets de catégorie, liste, puis rappel des raccourcis (poste
/// fixe). Flèches ↑↓ pour parcourir, Entrée pour ajouter la ligne active,
/// Échap pour fermer.
///
/// La ligne active est celle que validerait Entrée : la première dès qu'une
/// recherche est saisie, ou celle atteinte aux flèches. Sans recherche ni
/// flèche, aucune ligne n'est active (Entrée n'ajoute rien).
class TagPickerPanel extends StatefulWidget {
  final List<TagItem> availableTags;
  final List<TagCategoryWithTags> tagCatalog;
  final Map<int, Color> categoryColors;

  /// Clé de recherche (nom normalisé) de chaque tag, calculée une fois par le
  /// parent plutôt qu'à chaque frappe.
  final Map<int, String> searchKeys;
  final ValueChanged<TagItem> onSelected;
  final VoidCallback onClose;

  const TagPickerPanel({
    super.key,
    required this.availableTags,
    required this.tagCatalog,
    required this.categoryColors,
    required this.searchKeys,
    required this.onSelected,
    required this.onClose,
  });

  @override
  State<TagPickerPanel> createState() => _TagPickerPanelState();
}

class _TagPickerPanelState extends State<TagPickerPanel> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  int? _categoryFilter;
  int? _active;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String get _query => normalizeForSearch(_searchController.text);

  List<TagCategoryWithTags> get _activeCategories {
    final ids = widget.availableTags.map((t) => t.categoryId).toSet();
    return widget.tagCatalog.where((c) => ids.contains(c.category.id)).toList();
  }

  /// Le filtre mémorisé peut viser une catégorie dont le dernier tag vient
  /// d'être posé : on l'ignore alors, sinon la liste serait vide sans qu'aucun
  /// onglet de filtre ne soit visible pour s'en dépêtrer.
  int? get _effectiveFilter =>
      _activeCategories.any((c) => c.category.id == _categoryFilter)
      ? _categoryFilter
      : null;

  List<TagItem> get _filtered {
    final q = _query;
    final filter = _effectiveFilter;
    return widget.availableTags.where((t) {
      if (filter != null && t.categoryId != filter) return false;
      if (q.isEmpty) return true;
      return (widget.searchKeys[t.id] ?? '').contains(q);
    }).toList();
  }

  /// Après un changement de recherche ou de filtre : la première ligne devient
  /// active si une recherche est saisie, sinon plus aucune.
  void _resetActive() => _active = _query.isEmpty ? null : 0;

  /// Sélectionne un tag et prépare l'ajout suivant : recherche vidée (le tag
  /// choisi disparaît de la liste), filtre de catégorie conservé, focus rendu
  /// au champ.
  void _select(TagItem tag) {
    widget.onSelected(tag);
    _searchController.clear();
    _searchFocus.requestFocus();
    setState(() => _active = null);
  }

  /// Entrée valide la ligne active.
  void _submit() {
    final index = _active;
    if (index == null) return;
    final results = _filtered;
    if (results.isEmpty) {
      _searchFocus.requestFocus();
      return;
    }
    _select(results[index.clamp(0, results.length - 1)]);
  }

  void _move(int delta) {
    final count = _filtered.length;
    if (count == 0) return;
    setState(() {
      final from = _active ?? (delta > 0 ? -1 : count);
      _active = (from + delta).clamp(0, count - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final categories = _activeCategories;
    final categoryFilter = _effectiveFilter;
    final filtered = _filtered;
    final query = _query;
    final showEnterHint = _active != null && filtered.isNotEmpty;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Panneau flottant au-dessus du contenu : surface pleine et filet
          // marqué plutôt qu'une ombre.
          color: scheme.surfaceContainer,
          border: Border.fromBorderSide(AppElevation.borderStrong(scheme)),
          borderRadius: AppRadius.radiusMd,
        ),
        child: ClipRRect(
          borderRadius: AppRadius.radiusMd,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        autofocus: true,
                        style: const TextStyle(fontSize: 13),
                        // Champ intégré à l'en-tête du panneau : ni fond ni
                        // cadre, contrairement aux champs de formulaire.
                        decoration: const InputDecoration(
                          filled: false,
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: 'Rechercher un tag…',
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (_) => setState(_resetActive),
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                    if (showEnterHint && query.isNotEmpty) ...[
                      const _Kbd('↵'),
                      const SizedBox(width: 4),
                    ],
                    BoxedIconButton(
                      icon: Icons.close,
                      tooltip: 'Fermer',
                      framed: false,
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
              if (categories.length > 1)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    children: [
                      _CategoryChip(
                        label: 'Tous',
                        color: null,
                        selected: categoryFilter == null,
                        onTap: () => setState(() {
                          _categoryFilter = null;
                          _resetActive();
                        }),
                      ),
                      for (final cat in categories)
                        _CategoryChip(
                          label: cat.category.displayLabel,
                          color: Color(cat.category.color),
                          selected: categoryFilter == cat.category.id,
                          onTap: () => setState(() {
                            _categoryFilter = categoryFilter == cat.category.id
                                ? null
                                : cat.category.id;
                            _resetActive();
                          }),
                        ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Aucun résultat',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < filtered.length; i++)
                          _TagRow(
                            key: ValueKey('tag-row-${filtered[i].id}'),
                            tag: filtered[i],
                            color:
                                widget.categoryColors[filtered[i].categoryId],
                            active: i == _active,
                            onTap: () => _select(filtered[i]),
                          ),
                      ],
                    ),
                  ),
                ),
              // Rappel des raccourcis : utile seulement avec un clavier.
              if (context.prefersDesktopUi) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      const _Kbd('↑↓'),
                      const SizedBox(width: 6),
                      _hint(scheme, 'naviguer'),
                      const SizedBox(width: 14),
                      const _Kbd('↵'),
                      const SizedBox(width: 6),
                      _hint(scheme, 'ajouter'),
                      const SizedBox(width: 14),
                      const _Kbd('Échap'),
                      const SizedBox(width: 6),
                      _hint(scheme, 'fermer'),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _hint(ColorScheme scheme, String text) => Text(
    text,
    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
  );
}

// ── Ligne de tag ──────────────────────────────────────────────────────────────

class _TagRow extends StatefulWidget {
  final TagItem tag;
  final Color? color;

  /// Ligne que validerait Entrée.
  final bool active;
  final VoidCallback onTap;

  const _TagRow({
    super.key,
    required this.tag,
    required this.color,
    required this.active,
    required this.onTap,
  });

  @override
  State<_TagRow> createState() => _TagRowState();
}

class _TagRowState extends State<_TagRow> {
  bool _hovered = false;

  @override
  void didUpdateWidget(_TagRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      // Aux flèches, garder la ligne active à l'écran (défilement minimal,
      // dans un sens puis dans l'autre : un seul des deux agit).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (final policy in [
          ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        ]) {
          Scrollable.ensureVisible(
            context,
            alignmentPolicy: policy,
            duration: const Duration(milliseconds: 80),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highlighted = widget.active || _hovered;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: widget.active
                ? AppColors.accentSoft
                : (highlighted
                      ? scheme.onSurface.withAlpha(12)
                      : Colors.transparent),
            borderRadius: AppRadius.radiusSm,
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color ?? scheme.outlineVariant,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.tag.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: highlighted
                        ? scheme.onSurface
                        : scheme.onSurface.withAlpha(214),
                  ),
                ),
              ),
              if (widget.active) const _Kbd('↵'),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Onglet de catégorie ───────────────────────────────────────────────────────

class _CategoryChip extends StatelessWidget {
  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    // Même langage que `TagPill` (coin `sm`, filet, point de catégorie) ; la
    // sélection se lit au fond teinté et au filet de ton, pas à une bordure épaisse.
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? accent.withAlpha(30) : Colors.transparent,
              borderRadius: AppRadius.radiusSm,
              border: Border.fromBorderSide(
                selected
                    ? BorderSide(color: accent.withAlpha(140))
                    : AppElevation.border(scheme),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (color != null) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppFonts.ui,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: selected
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Touche ────────────────────────────────────────────────────────────────────

/// Pastille de raccourci clavier (« ↵ », « Échap »).
class _Kbd extends StatelessWidget {
  final String label;

  const _Kbd(this.label);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.radiusXs,
        border: Border.fromBorderSide(AppElevation.borderStrong(scheme)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: Text(
          label,
          style: AppFonts.monoStyle(
            TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
