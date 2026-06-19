import 'package:flutter/material.dart';

import '../../../../core/utils/string_utils.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';
import '../utils/tag_category_ui.dart';

/// Affiche les tags sélectionnés + un bouton "+" qui ouvre un panneau inline.
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

  List<TagItem> get _allTags {
    final byId = <int, TagItem>{};
    for (final cat in widget.tagCatalog) {
      for (final tag in cat.tags) {
        byId[tag.id] = tag;
      }
    }
    final tags = byId.values.toList();
    tags.sort(
      (a, b) =>
          normalizeForSearch(a.name).compareTo(normalizeForSearch(b.name)),
    );
    return tags;
  }

  List<TagItem> get _selectedTags =>
      (_allTags.where((t) => widget.selectedTagIds.contains(t.id)).toList()
        ..sort((a, b) => a.name.compareTo(b.name)));

  List<TagItem> get _availableTags =>
      _allTags.where((t) => !widget.selectedTagIds.contains(t.id)).toList();

  Color? _categoryColor(int categoryId) {
    for (final c in widget.tagCatalog) {
      if (c.category.id == categoryId) return Color(c.category.color);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tagCatalog.every((c) => c.tags.isEmpty)) {
      return const Text('Aucun tag disponible');
    }

    final selectedTags = _selectedTags;
    final availableTags = _availableTags;

    // Auto-fermeture si tous les tags sont déjà ajoutés
    if (_isPickerOpen && availableTags.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isPickerOpen = false);
      });
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in selectedTags) _buildSelectedChip(tag),
            if (availableTags.isNotEmpty) _buildAddButton(context),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topLeft,
          child: _isPickerOpen && availableTags.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _TagPickerPanel(
                    availableTags: availableTags,
                    tagCatalog: widget.tagCatalog,
                    onSelected: (tag) => widget.onTagAdded(tag.id),
                    onClose: () => setState(() => _isPickerOpen = false),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildAddButton(BuildContext context) {
    const size = 34.0;
    final scheme = Theme.of(context).colorScheme;
    final open = _isPickerOpen;
    return InkWell(
      onTap: () => setState(() => _isPickerOpen = !_isPickerOpen),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: open ? scheme.primaryContainer : Colors.transparent,
          border: Border.all(
            color: open ? scheme.primary : scheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          open ? Icons.close : Icons.add,
          size: 18,
          color: open ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildSelectedChip(TagItem tag) {
    final color = _categoryColor(tag.categoryId);
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
  final ValueChanged<TagItem> onSelected;
  final VoidCallback onClose;

  const _TagPickerPanel({
    required this.availableTags,
    required this.tagCatalog,
    required this.onSelected,
    required this.onClose,
  });

  @override
  State<_TagPickerPanel> createState() => _TagPickerPanelState();
}

class _TagPickerPanelState extends State<_TagPickerPanel> {
  String _query = '';
  int? _categoryFilter;

  List<TagCategoryWithTags> get _activeCategories {
    final ids = widget.availableTags.map((t) => t.categoryId).toSet();
    return widget.tagCatalog
        .where((c) => ids.contains(c.category.id))
        .toList();
  }

  Color? _categoryColor(int categoryId) {
    for (final c in widget.tagCatalog) {
      if (c.category.id == categoryId) return Color(c.category.color);
    }
    return null;
  }

  List<TagItem> get _filtered {
    final q = normalizeForSearch(_query);
    return widget.availableTags.where((t) {
      if (_categoryFilter != null && t.categoryId != _categoryFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      return normalizeForSearch(t.name).contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filtered = _filtered;
    final categories = _activeCategories;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // En-tête : recherche + fermer
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Rechercher un tag...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
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
                      selected: _categoryFilter == null,
                      onTap: () => setState(() => _categoryFilter = null),
                    ),
                    for (final cat in categories)
                      _CategoryChip(
                        label: cat.category.displayLabel,
                        color: Color(cat.category.color),
                        selected: _categoryFilter == cat.category.id,
                        onTap: () => setState(() {
                          _categoryFilter =
                              _categoryFilter == cat.category.id
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
                          onTap: () {
                            widget.onSelected(tag);
                            widget.onClose();
                          },
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
                                    color: _categoryColor(tag.categoryId) ??
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
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? accent.withAlpha(30) : Colors.transparent,
            border: Border.all(
              color: selected ? accent : scheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(16),
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
