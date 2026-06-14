import 'package:flutter/material.dart';

import '../../../../core/database/database.dart' as db;
import '../../../../core/utils/string_utils.dart';
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';
import '../providers/sampler_provider.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/sound_picker_overlay.dart';
import 'sound_details_screen.dart';

/// Bibliothèque d'édition : utilise [SoundPickerOverlay] pour la navigation,
/// ouvre le formulaire d'édition au tap sur un son.
class SoundLibraryManageScreen {
  SoundLibraryManageScreen._();

  static Future<void> open(
    BuildContext context, {
    required SamplerNotifier notifier,
    required db.AppDatabase database,
  }) {
    final repository = SoundRepository.fromDatabase(database);
    return SoundPickerOverlay.showForManage(
      context,
      notifier: notifier,
      onTap: (ctx, sound, tagCatalog) =>
          _openSoundEdit(ctx, sound, tagCatalog, repository),
    );
  }

  // ── Dispatch mobile / tablette ────────────────────────────────────────────

  static Future<void> _openSoundEdit(
    BuildContext context,
    Sound sound,
    List<TagCategoryWithTags> tagCatalog,
    SoundRepository repository,
  ) async {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) {
      await _openEditPage(context, sound, tagCatalog, repository);
    } else {
      await _openEditDialog(context, sound, tagCatalog, repository);
    }
  }

  // ── Page plein écran (mobile) ─────────────────────────────────────────────

  static Future<void> _openEditPage(
    BuildContext context,
    Sound sound,
    List<TagCategoryWithTags> tagCatalog,
    SoundRepository repository,
  ) async {
    final initialTags = await repository.getTagsForSound(sound.id);
    if (!context.mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SoundDetailsScreen(
          sound: sound,
          tagCatalog: tagCatalog,
          initialTags: initialTags,
          repository: repository,
        ),
      ),
    );
  }

  // ── Dialogue (tablette / desktop) ────────────────────────────────────────

  static Future<void> _openEditDialog(
    BuildContext context,
    Sound sound,
    List<TagCategoryWithTags> tagCatalog,
    SoundRepository repository,
  ) async {
    final initialTags = await repository.getTagsForSound(sound.id);
    if (!context.mounted) return;

    final dialogScrollController = ScrollController();
    var selectedColorValue = sound.colorValue;
    var selectedVolume = sound.volume.clamp(0.0, 1.0);
    var displayNameValue = sound.displayName ?? '';
    final selectedTagIds = initialTags.map((t) => t.id).toSet();
    var tagAutocompleteText = '';
    TextEditingController? tagAutocompleteFieldController;

    String? normalizedOrNull(String value) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    List<TagItem> buildAllTags() {
      final tagsById = <int, TagItem>{};
      for (final category in tagCatalog) {
        for (final tag in category.tags) {
          tagsById[tag.id] = tag;
        }
      }
      return tagsById.values.toList()
        ..sort((a, b) =>
            normalizeForSearch(a.name).compareTo(normalizeForSearch(b.name)));
    }

    List<TagItem> buildSelectedTags(List<TagItem> allTags) {
      return allTags.where((t) => selectedTagIds.contains(t.id)).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    }

    List<TagItem> buildAvailableTags(List<TagItem> allTags, String query) {
      final q = normalizeForSearch(query);
      return allTags.where((t) {
        if (selectedTagIds.contains(t.id)) return false;
        if (q.isEmpty) return true;
        return normalizeForSearch(t.name).contains(q);
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    }

    await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            const sectionSpacing = 16.0;

            return AppFormDialog(
              title: 'Modifier "${sound.title}"',
              onClose: () => Navigator.of(dialogContext).pop(false),
              content: Scrollbar(
                controller: dialogScrollController,
                thumbVisibility: true,
                thickness: 8,
                radius: const Radius.circular(8),
                child: SingleChildScrollView(
                  controller: dialogScrollController,
                  padding: const EdgeInsets.only(right: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        initialValue: displayNameValue,
                        onChanged: (v) => displayNameValue = v,
                        onFieldSubmitted: (v) => displayNameValue = v,
                        decoration: InputDecoration(
                          hintText: sound.title,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: sectionSpacing),
                      Text(
                        'Couleur par défaut',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _colorSwatch(
                            context: context,
                            label: 'D',
                            color: null,
                            isSelected: selectedColorValue == null,
                            onTap: () => setDialogState(
                                () => selectedColorValue = null),
                          ),
                          for (final color in _defaultColorChoices)
                            _colorSwatch(
                              context: context,
                              color: color,
                              isSelected:
                                  selectedColorValue == color.toARGB32(),
                              onTap: () => setDialogState(
                                  () => selectedColorValue = color.toARGB32()),
                            ),
                        ],
                      ),
                      const SizedBox(height: sectionSpacing),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Volume par défaut',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          Text('${(selectedVolume * 100).round()}%'),
                        ],
                      ),
                      Slider(
                        value: selectedVolume,
                        onChanged: (v) => setDialogState(
                            () => selectedVolume = v.clamp(0.0, 1.0)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tags',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      if (tagCatalog
                          .where((c) => c.tags.isNotEmpty)
                          .isEmpty)
                        const Text('Aucun tag disponible')
                      else
                        Builder(
                          builder: (context) {
                            final allTags = buildAllTags();
                            final selectedTags = buildSelectedTags(allTags);
                            final availableTags = buildAvailableTags(
                                allTags, tagAutocompleteText);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (selectedTags.isNotEmpty) ...[
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final tag in selectedTags)
                                        _tagInputChip(
                                          tag,
                                          tagCatalog,
                                          () => setDialogState(() =>
                                              selectedTagIds.remove(tag.id)),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                Autocomplete<TagItem>(
                                  displayStringForOption: (t) => t.name,
                                  optionsBuilder: (v) => buildAvailableTags(
                                      buildAllTags(), v.text),
                                  onSelected: (tag) {
                                    setDialogState(() {
                                      selectedTagIds.add(tag.id);
                                      tagAutocompleteText = '';
                                    });
                                    tagAutocompleteFieldController?.clear();
                                  },
                                  optionsViewBuilder: (ctx, onSelected, opts) {
                                    final scheme =
                                        Theme.of(ctx).colorScheme;
                                    return Align(
                                      alignment: Alignment.topLeft,
                                      child: Material(
                                        elevation: 4,
                                        borderRadius: BorderRadius.circular(8),
                                        clipBehavior: Clip.antiAlias,
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                              maxHeight: 280),
                                          child: ListView.builder(
                                            padding: EdgeInsets.zero,
                                            shrinkWrap: true,
                                            itemCount: opts.length,
                                            itemBuilder: (_, i) {
                                              final tag = opts.elementAt(i);
                                              final color = _categoryColor(
                                                  tag.categoryId, tagCatalog);
                                              return InkWell(
                                                onTap: () => onSelected(tag),
                                                child: Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 12,
                                                      vertical: 10),
                                                  child: Row(
                                                    children: [
                                                      Container(
                                                        width: 10,
                                                        height: 10,
                                                        decoration: BoxDecoration(
                                                          color: color ??
                                                              scheme
                                                                  .outlineVariant,
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: Text(
                                                          tag.name,
                                                          maxLines: 1,
                                                          overflow:
                                                              TextOverflow
                                                                  .ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                  fieldViewBuilder: (ctx, ctrl, focus, submit) {
                                    tagAutocompleteFieldController = ctrl;
                                    return TextField(
                                      controller: ctrl,
                                      focusNode: focus,
                                      decoration: InputDecoration(
                                        labelText: 'Ajouter un tag',
                                        hintText: 'Taper pour filtrer...',
                                        prefixIcon: const Icon(Icons.search),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      onChanged: (v) => setDialogState(
                                          () => tagAutocompleteText = v),
                                      onSubmitted: (_) => submit(),
                                    );
                                  },
                                ),
                                const SizedBox(height: 8),
                                if (allTags.isEmpty)
                                  const Text('Aucun tag disponible')
                                else if (availableTags.isEmpty)
                                  Text(
                                    tagAutocompleteText.trim().isEmpty
                                        ? 'Tous les tags sont déjà ajoutés'
                                        : 'Aucun tag pour cette recherche',
                                  ),
                              ],
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                  ),
                  onPressed: () async {
                    await repository.updateSoundSettings(
                      id: sound.id,
                      colorValue: selectedColorValue,
                      updateColor: true,
                      displayName: normalizedOrNull(displayNameValue),
                      updateDisplayName: true,
                      volume: selectedVolume,
                    );
                    await repository.setTagsForSound(
                        sound.id, selectedTagIds.toList());
                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );
    dialogScrollController.dispose();
  }

  // ── Helpers UI ────────────────────────────────────────────────────────────

  static Color? _categoryColor(
      int categoryId, List<TagCategoryWithTags> catalog) {
    for (final c in catalog) {
      if (c.category.id == categoryId) return Color(c.category.color);
    }
    return null;
  }

  static Widget _tagInputChip(
    TagItem tag,
    List<TagCategoryWithTags> catalog,
    VoidCallback onDeleted,
  ) {
    final color = _categoryColor(tag.categoryId, catalog);
    return InputChip(
      label: Text(tag.name),
      backgroundColor: color?.withAlpha(24),
      side: color == null ? null : BorderSide(color: color),
      onDeleted: onDeleted,
    );
  }

  static Widget _colorSwatch({
    required BuildContext context,
    Color? color,
    required bool isSelected,
    required VoidCallback onTap,
    String? label,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? scheme.surfaceContainerHighest;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: effectiveColor,
          border: Border.all(
            color: isSelected ? scheme.primary : scheme.outlineVariant,
            width: isSelected ? 3 : 1,
          ),
        ),
        child: isSelected
            ? Icon(
                Icons.check,
                size: 18,
                color: color == null
                    ? scheme.onSurfaceVariant
                    : _checkmarkColor(effectiveColor),
              )
            : (label != null
                ? Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  )
                : null),
      ),
    );
  }

  static Color _checkmarkColor(Color bg) =>
      bg.computeLuminance() > 0.6 ? Colors.black : Colors.white;

  static const List<Color> _defaultColorChoices = <Color>[
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.red,
    Colors.teal,
    Colors.brown,
    Colors.grey,
  ];
}
