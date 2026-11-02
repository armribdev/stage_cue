import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/string_utils.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';
import '../utils/tag_category_ui.dart';
import 'boxed_icon_button.dart';

/// Affiche les tags sélectionnés + un bouton "+" qui ouvre un panneau inline.
///
/// Le panneau reste ouvert après chaque sélection (on pose rarement un seul
/// tag) ; il se referme via sa croix, le bouton « + », ou tout seul quand il
/// ne reste plus rien à ajouter.
class TagChipsEditor extends StatefulWidget {
  final List<TagCategoryWithTags> tagCatalog;
  final Set<int> selectedTagIds;
  final ValueChanged<int> onTagAdded;
  final ValueChanged<int> onTagRemoved;

  const TagChipsEditor({
    super.key,
    required this.tagCatalog,
    required this.selectedTagIds,
    required this.onTagAdded,
    required this.onTagRemoved,
  });

  @override
  State<TagChipsEditor> createState() => _TagChipsEditorState();
}

class _TagChipsEditorState extends State<TagChipsEditor> {
  bool _isPickerOpen = false;

  // Dérivés du catalogue, recalculés seulement quand celui-ci change (et non à
  // chaque `build`, appelé à chaque coche/décoche).
  late List<TagItem> _allTags;
  late Map<int, Color> _categoryColors;
  late Map<int, String> _searchKeys;

  @override
  void initState() {
    super.initState();
    _rebuildCatalogCache();
  }

  @override
  void didUpdateWidget(TagChipsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tagCatalog, widget.tagCatalog)) {
      _rebuildCatalogCache();
    }
  }

  void _rebuildCatalogCache() {
    final byId = <int, TagItem>{};
    final colors = <int, Color>{};
    for (final cat in widget.tagCatalog) {
      colors[cat.category.id] = Color(cat.category.color);
      for (final tag in cat.tags) {
        byId[tag.id] = tag;
      }
    }
    final keys = {
      for (final tag in byId.values) tag.id: normalizeForSearch(tag.name),
    };
    // Même ordre partout (puces et panneau) : nom normalisé (insensible à la
    // casse et aux accents), l'id départageant les homonymes.
    final tags = byId.values.toList()
      ..sort((a, b) {
        final byName = keys[a.id]!.compareTo(keys[b.id]!);
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
    _allTags = tags;
    _categoryColors = colors;
    _searchKeys = keys;
  }

  void _togglePicker() => setState(() => _isPickerOpen = !_isPickerOpen);

  @override
  Widget build(BuildContext context) {
    if (_allTags.isEmpty) {
      return Text(
        'Aucun tag disponible',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }

    final selectedIds = widget.selectedTagIds;
    final selectedTags = [
      for (final t in _allTags)
        if (selectedIds.contains(t.id)) t,
    ];
    final availableTags = [
      for (final t in _allTags)
        if (!selectedIds.contains(t.id)) t,
    ];
    // Dérivé plutôt que muté depuis `build` : si un tag est retiré plus tard,
    // le panneau ne se rouvre pas de lui-même.
    final pickerOpen = _isPickerOpen && availableTags.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in selectedTags) _buildSelectedChip(tag),
            if (availableTags.isNotEmpty) _buildAddButton(context, pickerOpen),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topLeft,
          child: pickerOpen
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _TagPickerPanel(
                    availableTags: availableTags,
                    tagCatalog: widget.tagCatalog,
                    categoryColors: _categoryColors,
                    searchKeys: _searchKeys,
                    onSelected: (tag) {
                      widget.onTagAdded(tag.id);
                      // Dernier tag disponible : plus rien à proposer.
                      if (availableTags.length <= 1) {
                        setState(() => _isPickerOpen = false);
                      }
                    },
                    onClose: () => setState(() => _isPickerOpen = false),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildAddButton(BuildContext context, bool open) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      child: Tooltip(
        message: open ? 'Fermer la liste des tags' : 'Ajouter un tag',
        child: InkWell(
          onTap: _togglePicker,
          borderRadius: AppRadius.radiusSm,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: open ? AppColors.accentSoft : Colors.transparent,
              border: Border.fromBorderSide(
                open
                    ? AppElevation.emphasizedBorder(scheme)
                    : AppElevation.border(scheme),
              ),
              borderRadius: AppRadius.radiusSm,
            ),
            child: Icon(
              open ? Icons.close : Icons.add,
              size: 16,
              color: open ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedChip(TagItem tag) {
    final color = _categoryColors[tag.categoryId];
    return InputChip(
      label: Text(tag.name),
      backgroundColor: color?.withAlpha(24),
      side: color == null ? null : BorderSide(color: color),
      onDeleted: () => widget.onTagRemoved(tag.id),
    );
  }
}

// ── Panneau inline ────────────────────────────────────────────────────────────

class _TagPickerPanel extends StatefulWidget {
  final List<TagItem> availableTags;
  final List<TagCategoryWithTags> tagCatalog;
  final Map<int, Color> categoryColors;

  /// Clé de recherche (nom normalisé) de chaque tag, calculée une fois par le
  /// parent plutôt qu'à chaque frappe.
  final Map<int, String> searchKeys;
  final ValueChanged<TagItem> onSelected;
  final VoidCallback onClose;

  const _TagPickerPanel({
    required this.availableTags,
    required this.tagCatalog,
    required this.categoryColors,
    required this.searchKeys,
    required this.onSelected,
    required this.onClose,
  });

  @override
  State<_TagPickerPanel> createState() => _TagPickerPanelState();
}

class _TagPickerPanelState extends State<_TagPickerPanel> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  int? _categoryFilter;

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

  List<TagItem> _filtered(int? categoryFilter) {
    final q = _query;
    return widget.availableTags.where((t) {
      if (categoryFilter != null && t.categoryId != categoryFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      return (widget.searchKeys[t.id] ?? '').contains(q);
    }).toList();
  }

  /// Sélectionne un tag et prépare l'ajout suivant : recherche vidée (le tag
  /// choisi disparaît de la liste), filtre de catégorie conservé, focus rendu
  /// au champ.
  void _select(TagItem tag) {
    widget.onSelected(tag);
    _searchController.clear();
    _searchFocus.requestFocus();
    setState(() {});
  }

  /// Entrée valide le premier résultat d'une recherche saisie.
  void _submit(int? categoryFilter) {
    if (_query.isEmpty) return;
    final results = _filtered(categoryFilter);
    if (results.isEmpty) {
      _searchFocus.requestFocus();
      return;
    }
    _select(results.first);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final categories = _activeCategories;
    // Le filtre mémorisé peut viser une catégorie dont le dernier tag vient
    // d'être posé : on l'ignore alors, sinon la liste serait vide sans qu'aucune
    // pastille de filtre ne soit visible pour s'en dépêtrer.
    final categoryFilter =
        categories.any((c) => c.category.id == _categoryFilter)
        ? _categoryFilter
        : null;
    final filtered = _filtered(categoryFilter);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.fromBorderSide(AppElevation.border(scheme)),
        borderRadius: AppRadius.radiusLg,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.radiusLg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // En-tête : recherche + fermer
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      autofocus: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Rechercher un tag… (Entrée pour ajouter)',
                        prefixIcon: Icon(Icons.search, size: 18),
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submit(categoryFilter),
                    ),
                  ),
                  const SizedBox(width: 4),
                  BoxedIconButton(
                    icon: Icons.close,
                    tooltip: 'Fermer',
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            // Filtre par catégorie
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
                      onTap: () => setState(() => _categoryFilter = null),
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
                        }),
                      ),
                  ],
                ),
              ),
            const Divider(height: 1),
            // Liste des tags
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
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final tag in filtered)
                        InkWell(
                          onTap: () => _select(tag),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color:
                                        widget.categoryColors[tag.categoryId] ??
                                        scheme.outlineVariant,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    tag.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Chip de catégorie ─────────────────────────────────────────────────────────

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
    // Pastille (stade) comme `chipTheme` : pas de rayon codé en dur.
    const shape = StadiumBorder();
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: selected ? accent.withAlpha(30) : Colors.transparent,
            shape: StadiumBorder(
              side: selected
                  ? BorderSide(color: accent, width: 1.5)
                  : AppElevation.border(scheme),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (color != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected ? accent : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
