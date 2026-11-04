import 'package:flutter/material.dart';

import '../../../../core/utils/string_utils.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';
import 'tag_picker_panel.dart';
import 'tag_pill.dart';

/// Affiche les tags sélectionnés + un bouton "+" qui ouvre un panneau flottant.
///
/// Le panneau est posé en surimpression (sous la rangée, ou au-dessus s'il n'y
/// a pas la place) : il ne pousse pas le contenu du formulaire, qui n'a donc
/// pas à défiler. Il reste ouvert après chaque sélection (on pose rarement un
/// seul tag) ; il se referme via sa croix, Échap, un clic ailleurs, le bouton
/// « + », ou tout seul quand il ne reste plus rien à ajouter.
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

  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _targetKey = GlobalKey();

  /// Relie le bouton « + » et le panneau : un clic dans l'un n'est pas « à
  /// côté » de l'autre (sinon le bouton fermerait puis rouvrirait le panneau).
  final _tapGroup = Object();

  /// Hauteur approximative du panneau ouvert, pour choisir s'il s'ouvre vers le
  /// bas ou vers le haut.
  static const double _panelHeight = 340;

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

  void _setOpen(bool open) {
    if (open) {
      _portal.show();
    } else {
      _portal.hide();
    }
    setState(() => _isPickerOpen = open);
  }

  void _togglePicker() => _setOpen(!_isPickerOpen);

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
    // Plus rien à proposer (tout a été posé ailleurs) : le panneau se ferme,
    // sans quoi il se rouvrirait de lui-même si un tag était retiré ensuite.
    if (_isPickerOpen && availableTags.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isPickerOpen) _setOpen(false);
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        return OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (_) => _buildPanel(width, availableTags),
          child: CompositedTransformTarget(
            link: _link,
            child: Wrap(
              key: _targetKey,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in selectedTags) _buildSelectedChip(tag),
                if (availableTags.isNotEmpty)
                  TapRegion(
                    groupId: _tapGroup,
                    child: TagAddButton(
                      open: _isPickerOpen,
                      verbose: selectedTags.isEmpty,
                      onPressed: _togglePicker,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Panneau en surimpression, ancré sous la rangée d'étiquettes — ou au-dessus
  /// quand le bas de l'écran (clavier compris) n'a pas la place et que le haut
  /// en a davantage.
  Widget _buildPanel(double width, List<TagItem> availableTags) {
    final box = _targetKey.currentContext?.findRenderObject();
    var openUp = false;
    if (box is RenderBox && box.hasSize && box.attached) {
      final media = MediaQuery.of(context);
      final top = box.localToGlobal(Offset.zero).dy;
      final below =
          media.size.height - media.viewInsets.bottom - (top + box.size.height);
      openUp = below < _panelHeight && top > below;
    }

    // L'overlay impose ses contraintes serrées (plein écran) : `Align` les
    // desserre pour que le panneau garde sa taille naturelle.
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: openUp ? Alignment.topLeft : Alignment.bottomLeft,
        followerAnchor: openUp ? Alignment.bottomLeft : Alignment.topLeft,
        offset: Offset(0, openUp ? -6 : 6),
        child: SizedBox(
          width: width,
          child: TapRegion(
            groupId: _tapGroup,
            onTapOutside: (_) => _setOpen(false),
            child: TagPickerPanel(
              availableTags: availableTags,
              tagCatalog: widget.tagCatalog,
              categoryColors: _categoryColors,
              searchKeys: _searchKeys,
              onSelected: (tag) {
                widget.onTagAdded(tag.id);
                // Dernier tag disponible : plus rien à proposer.
                if (availableTags.length <= 1) _setOpen(false);
              },
              onClose: () => _setOpen(false),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedChip(TagItem tag) {
    return TagPill(
      key: ValueKey('tag-${tag.id}'),
      label: tag.name,
      color: _categoryColors[tag.categoryId],
      removeTooltip: 'Retirer ${tag.name}',
      onRemove: () => widget.onTagRemoved(tag.id),
    );
  }
}
