import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import '../../../../core/database/database.dart' as db;
import '../../../../core/utils/string_utils.dart';
import 'sound_details_screen.dart';
import '../widgets/app_form_dialog.dart';
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';

/// Écran bibliothèque dédié à l'édition des propriétés des sons.
class SoundLibraryManageScreen extends StatefulWidget {
  final db.AppDatabase database;

  const SoundLibraryManageScreen({super.key, required this.database});

  @override
  State<SoundLibraryManageScreen> createState() =>
      _SoundLibraryManageScreenState();
}

class _SoundLibraryManageScreenState extends State<SoundLibraryManageScreen> {
  late final SoundRepository _repository;
  List<Sound> _availableSounds = [];
  final Map<int, List<TagItem>> _soundTags = {};
  List<TagCategoryWithTags> _tagCatalog = [];
  bool _isLoading = true;
  String _searchQuery = '';
  Set<int>? _searchMatchedSoundIds;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _repository = SoundRepository.fromDatabase(widget.database);
    _loadTagCatalog();
    _loadSounds();
  }

  Future<void> _loadSounds() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final allSounds = await _repository.getAllSounds();
      final availableSounds = allSounds
          .where((sound) => sound.type == SoundType.soundEffect)
          .toList();

      setState(() {
        _availableSounds = availableSounds;
        _isLoading = false;
      });
      await _loadTagsForSounds(availableSounds);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du chargement: $e')),
        );
      }
    }
  }

  Future<void> _loadTagCatalog() async {
    final catalog = await _repository.getTagCatalog();
    if (!mounted) {
      return;
    }
    setState(() {
      _tagCatalog = catalog;
    });
  }

  Future<void> _loadTagsForSounds(List<Sound> sounds) async {
    if (sounds.isEmpty) {
      setState(() {
        _soundTags.clear();
      });
      return;
    }
    final entries = await Future.wait(
      sounds.map((sound) async {
        final tags = await _repository.getTagsForSound(sound.id);
        return MapEntry(sound.id, tags);
      }),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _soundTags
        ..clear()
        ..addEntries(entries);
    });
  }

  List<String> _parseSearchTokens(String query) {
    return query
        .split(RegExp(r'[\s,]+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty && t.length >= 2)
        .toList();
  }

  bool _soundMatchesToken(Sound sound, String token) {
    final normalizedToken = normalizeForSearch(token);
    final matchInTitle = normalizeForSearch(
      sound.title,
    ).contains(normalizedToken);
    final matchInDisplayName =
        sound.displayName != null &&
        normalizeForSearch(sound.displayName!).contains(normalizedToken);
    final matchInPath = normalizeForSearch(
      sound.filePath,
    ).contains(normalizedToken);
    return matchInTitle || matchInDisplayName || matchInPath;
  }

  void _scheduleSearch(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchMatchedSoundIds = null;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      final tokens = _parseSearchTokens(query);
      if (tokens.isEmpty) {
        if (!mounted) return;
        setState(() {
          _searchMatchedSoundIds = null;
        });
        return;
      }

      Set<int>? intersection;
      for (final token in tokens) {
        final tagIds = await _repository.findSoundIdsByTagQuery(token);
        final titleIds = _availableSounds
            .where((s) => _soundMatchesToken(s, token))
            .map((s) => s.id)
            .toSet();
        final tokenMatchIds = tagIds.union(titleIds);

        if (intersection == null) {
          intersection = tokenMatchIds;
        } else {
          intersection = intersection.intersection(tokenMatchIds);
        }
      }

      if (!mounted) return;
      setState(() {
        _searchMatchedSoundIds = intersection ?? {};
      });
    });
  }

  Color? _getCategoryColor(int categoryId) {
    for (final category in _tagCatalog) {
      if (category.category.id == categoryId) {
        return Color(category.category.color);
      }
    }
    return null;
  }

  Widget _buildTagChip(TagItem tag) {
    final color = _getCategoryColor(tag.categoryId);
    return Chip(
      label: Text(tag.name, style: const TextStyle(fontSize: 11)),
      visualDensity: VisualDensity.compact,
      backgroundColor: color?.withAlpha(24),
      side: color == null ? null : BorderSide(color: color),
    );
  }

  Widget _buildDialogTagInputChip(TagItem tag, VoidCallback onDeleted) {
    final color = _getCategoryColor(tag.categoryId);
    return InputChip(
      label: Text(tag.name),
      backgroundColor: color?.withAlpha(24),
      side: color == null ? null : BorderSide(color: color),
      onDeleted: onDeleted,
    );
  }

  List<Sound> get _filteredSounds {
    if (_searchQuery.trim().isEmpty || _searchMatchedSoundIds == null) {
      return _availableSounds;
    }
    return _availableSounds
        .where((s) => _searchMatchedSoundIds!.contains(s.id))
        .toList();
  }

  Future<void> _openEditDialog(Sound sound) async {
    final initialTags = await _repository.getTagsForSound(sound.id);
    if (!mounted) {
      return;
    }
    final dialogScrollController = ScrollController();
    var selectedColorValue = sound.colorValue;
    var selectedVolume = sound.volume.clamp(0.0, 1.0);
    var displayNameValue = sound.displayName ?? '';
    final selectedTagIds = initialTags.map((t) => t.id).toSet();
    var hasPersistedChanges = false;
    var tagAutocompleteText = '';
    TextEditingController? tagAutocompleteFieldController;

    String? normalizedDisplayNameOrNull(String value) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    List<TagItem> buildAllTags() {
      final tagsById = <int, TagItem>{};
      for (final category in _tagCatalog) {
        for (final tag in category.tags) {
          tagsById[tag.id] = tag;
        }
      }
      final tags = tagsById.values.toList()
        ..sort(
          (a, b) =>
              normalizeForSearch(a.name).compareTo(normalizeForSearch(b.name)),
        );
      return tags;
    }

    List<TagItem> buildSelectedTags(List<TagItem> allTags) {
      final selected = allTags
          .where((tag) => selectedTagIds.contains(tag.id))
          .toList();
      selected.sort((a, b) => a.name.compareTo(b.name));
      return selected;
    }

    List<TagItem> buildAvailableTags(List<TagItem> allTags, String query) {
      final normalizedQuery = normalizeForSearch(query);
      final available = allTags.where((tag) {
        if (selectedTagIds.contains(tag.id)) {
          return false;
        }
        if (normalizedQuery.isEmpty) {
          return true;
        }
        return normalizeForSearch(tag.name).contains(normalizedQuery);
      }).toList();
      available.sort((a, b) => a.name.compareTo(b.name));
      return available;
    }

    final didSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            const dialogSectionSpacing = 16.0;

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
                          onChanged: (value) {
                            displayNameValue = value;
                          },
                          onFieldSubmitted: (value) {
                            displayNameValue = value;
                          },
                          decoration: InputDecoration(
                            hintText: sound.title,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: dialogSectionSpacing),
                        Text(
                          'Couleur par défaut',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _buildColorChoice(
                              context: context,
                              label: 'D',
                              color: null,
                              isSelected: selectedColorValue == null,
                              onTap: () {
                                setDialogState(() {
                                  selectedColorValue = null;
                                });
                              },
                            ),
                            for (final color in _defaultColorChoices)
                              _buildColorChoice(
                                context: context,
                                color: color,
                                isSelected:
                                    selectedColorValue == color.toARGB32(),
                                onTap: () {
                                  setDialogState(() {
                                    selectedColorValue = color.toARGB32();
                                  });
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: dialogSectionSpacing),
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
                          min: 0.0,
                          max: 1.0,
                          label: '${(selectedVolume * 100).round()}%',
                          onChanged: (value) {
                            setDialogState(() {
                              selectedVolume = value.clamp(0.0, 1.0);
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tags',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        if (_tagCatalog
                            .where((category) => category.tags.isNotEmpty)
                            .isEmpty)
                          const Text('Aucun tag disponible')
                        else ...[
                          Builder(
                            builder: (context) {
                              final allTags = buildAllTags();
                              final selectedTags = buildSelectedTags(allTags);
                              final availableTags =
                                  buildAvailableTags(allTags, tagAutocompleteText);

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (selectedTags.isNotEmpty) ...[
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        for (final tag in selectedTags)
                                          _buildDialogTagInputChip(tag, () {
                                            setDialogState(() {
                                              selectedTagIds.remove(tag.id);
                                            });
                                          }),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  Autocomplete<TagItem>(
                                    displayStringForOption: (TagItem option) =>
                                        option.name,
                                    optionsBuilder:
                                        (TextEditingValue textEditingValue) {
                                      final all = buildAllTags();
                                      return buildAvailableTags(
                                        all,
                                        textEditingValue.text,
                                      );
                                    },
                                    onSelected: (TagItem selection) {
                                      setDialogState(() {
                                        selectedTagIds.add(selection.id);
                                        tagAutocompleteText = '';
                                      });
                                      tagAutocompleteFieldController?.clear();
                                    },
                                    optionsViewBuilder: (
                                      BuildContext context,
                                      AutocompleteOnSelected<TagItem> onSelected,
                                      Iterable<TagItem> options,
                                    ) {
                                      final scheme = Theme.of(context).colorScheme;
                                      return Align(
                                        alignment: Alignment.topLeft,
                                        child: Material(
                                          elevation: 4,
                                          borderRadius: BorderRadius.circular(8),
                                          clipBehavior: Clip.antiAlias,
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxHeight: 280,
                                            ),
                                            child: ListView.builder(
                                              padding: EdgeInsets.zero,
                                              shrinkWrap: true,
                                              itemCount: options.length,
                                              itemBuilder: (context, index) {
                                                final tag = options.elementAt(
                                                  index,
                                                );
                                                final color = _getCategoryColor(
                                                  tag.categoryId,
                                                );
                                                return InkWell(
                                                  onTap: () => onSelected(tag),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 10,
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Container(
                                                          width: 10,
                                                          height: 10,
                                                          decoration:
                                                              BoxDecoration(
                                                            color: color ??
                                                                scheme
                                                                    .outlineVariant,
                                                            shape:
                                                                BoxShape.circle,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 10,
                                                        ),
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
                                    fieldViewBuilder: (
                                      BuildContext context,
                                      TextEditingController textEditingController,
                                      FocusNode focusNode,
                                      VoidCallback onFieldSubmitted,
                                    ) {
                                      tagAutocompleteFieldController =
                                          textEditingController;
                                      return TextField(
                                        controller: textEditingController,
                                        focusNode: focusNode,
                                        decoration: InputDecoration(
                                          labelText: 'Ajouter un tag',
                                          hintText: 'Taper pour filtrer...',
                                          prefixIcon: const Icon(Icons.search),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                        onChanged: (value) {
                                          setDialogState(() {
                                            tagAutocompleteText = value;
                                          });
                                        },
                                        onSubmitted: (_) =>
                                            onFieldSubmitted(),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  if (allTags.isEmpty)
                                    const Text('Aucun tag disponible')
                                  else if (availableTags.isEmpty)
                                    Text(
                                      tagAutocompleteText.trim().isEmpty
                                          ? 'Tous les tags sont deja ajoutes'
                                          : 'Aucun tag disponible pour cette recherche',
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () async {
                    await _repository.updateSoundSettings(
                      id: sound.id,
                      colorValue: selectedColorValue,
                      updateColor: true,
                      displayName: normalizedDisplayNameOrNull(displayNameValue),
                      updateDisplayName: true,
                      volume: selectedVolume,
                    );
                    await _repository.setTagsForSound(
                      sound.id,
                      selectedTagIds.toList(),
                    );
                    hasPersistedChanges = true;
                    if (!dialogContext.mounted) {
                      return;
                    }
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

    if (didSave != true && !hasPersistedChanges) {
      return;
    }

    await _loadSounds();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Son mis à jour')));
  }

  Future<void> _openEditPage(Sound sound) async {
    final initialTags = await _repository.getTagsForSound(sound.id);
    if (!mounted) {
      return;
    }
    final didSave = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SoundDetailsScreen(
          sound: sound,
          tagCatalog: _tagCatalog,
          initialTags: initialTags,
          repository: _repository,
        ),
      ),
    );

    if (didSave != true) {
      return;
    }

    await _loadSounds();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Son mis à jour')));
  }

  Future<void> _openSoundEdit(Sound sound) async {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) {
      await _openEditPage(sound);
      return;
    }
    await _openEditDialog(sound);
  }

  Widget _buildColorChoice({
    required BuildContext context,
    Color? color,
    required bool isSelected,
    required VoidCallback onTap,
    String? label,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor = isSelected ? scheme.primary : scheme.outlineVariant;
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
          border: Border.all(color: borderColor, width: isSelected ? 3 : 1),
        ),
        child: isSelected
            ? Icon(
                Icons.check,
                size: 18,
                color: color == null
                    ? scheme.onSurfaceVariant
                    : _getCheckmarkColor(effectiveColor),
              )
            : (label != null
                  ? Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null),
      ),
    );
  }

  Color _getCheckmarkColor(Color color) {
    return color.computeLuminance() > 0.6 ? Colors.black : Colors.white;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDesktopPlatform =
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
    return Scaffold(
      appBar: AppBar(title: const Text('Bibliothèque des sons')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Rechercher un bruitage...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
                _scheduleSearch(value);
              },
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredSounds.isEmpty
                  ? Center(
                      child: Text(
                        _searchQuery.isEmpty
                            ? 'Aucun bruitage disponible'
                            : 'Aucun bruitage trouvé',
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredSounds.length,
                      itemBuilder: (context, index) {
                        final sound = _filteredSounds[index];
                        final tags = _soundTags[sound.id] ?? [];
                        // Correction : On retire le minVerticalPadding forcé pour uniformiser la hauteur entre tuiles avec/sans tags.
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: scheme.primaryContainer,
                                child: Icon(
                                  Icons.music_note,
                                  color: scheme.primary,
                                ),
                              ),
                              title: Text(sound.displayName ?? sound.title),
                              subtitle: tags.isNotEmpty
                                  ? Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: -6,
                                          children: [
                                            for (final tag in tags) _buildTagChip(tag),
                                          ],
                                        ),
                                      ],
                                    )
                                  : null,
                              trailing: IconButton(
                                icon: const Icon(Icons.edit_rounded),
                                tooltip: 'Modifier',
                                onPressed: () => _openSoundEdit(sound),
                              ),
                              onTap: isDesktopPlatform
                                  ? null
                                  : () => _openSoundEdit(sound),
                              hoverColor: Colors.transparent,
                              splashColor: Colors.transparent,
                              focusColor: Colors.transparent,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
                              // minVerticalPadding enlevé : hauteur homogène quelle que soit la présence de tags.
                            ),
                          ),
                        );
                      },
           
                    ),
            ),
          ),
        ],
      ),
    );
  }

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
