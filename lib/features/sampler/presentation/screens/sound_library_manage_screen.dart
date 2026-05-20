import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/database/database.dart' as db;
import '../../../../core/utils/string_utils.dart';
import 'sound_details_screen.dart';
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
    var selectedColorValue = sound.colorValue;
    var selectedVolume = sound.volume.clamp(0.0, 1.0);
    var displayNameValue = sound.displayName ?? '';
    final selectedTagIds = initialTags.map((t) => t.id).toSet();

    final didSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Modifier "${sound.title}"'),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
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
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 16),
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
                      for (final category in _tagCatalog) ...[
                        Text(
                          category.category.name,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in category.tags)
                              FilterChip(
                                label: Text(tag.name),
                                selected: selectedTagIds.contains(tag.id),
                                backgroundColor: Color(
                                  category.category.color,
                                ).withAlpha(25),
                                selectedColor: Color(
                                  category.category.color,
                                ).withAlpha(70),
                                onSelected: (selected) {
                                  setDialogState(() {
                                    if (selected) {
                                      selectedTagIds.add(tag.id);
                                    } else {
                                      selectedTagIds.remove(tag.id);
                                    }
                                  });
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final trimmed = displayNameValue.trim();
                    await _repository.updateSoundSettings(
                      id: sound.id,
                      colorValue: selectedColorValue,
                      updateColor: true,
                      displayName: trimmed.isEmpty ? null : trimmed,
                      updateDisplayName: true,
                      volume: selectedVolume,
                    );
                    await _repository.setTagsForSound(
                      sound.id,
                      selectedTagIds.toList(),
                    );
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
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: scheme.primaryContainer,
                              child: Icon(
                                Icons.music_note,
                                color: scheme.primary,
                              ),
                            ),
                            title: Text(sound.displayName ?? sound.title),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  sound.filePath,
                                  style: const TextStyle(fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (tags.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: -6,
                                    children: [
                                      for (final tag in tags)
                                        _buildTagChip(tag),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Text(
                                  'Volume: ${(sound.volume * 100).round()}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                            trailing: const Icon(Icons.edit_rounded),
                            onTap: () => _openSoundEdit(sound),
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
