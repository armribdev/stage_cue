import 'package:flutter/material.dart';
import '../../../../core/utils/copyable_snackbar.dart';
import '../../../../core/utils/string_utils.dart';
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';

/// Écran d'édition d'un son dans la bibliothèque.
class SoundDetailsScreen extends StatefulWidget {
  final Sound sound;
  final List<TagCategoryWithTags> tagCatalog;
  final List<TagItem> initialTags;
  final SoundRepository repository;

  const SoundDetailsScreen({
    super.key,
    required this.sound,
    required this.tagCatalog,
    required this.initialTags,
    required this.repository,
  });

  @override
  State<SoundDetailsScreen> createState() => _SoundDetailsScreenState();
}

class _SoundDetailsScreenState extends State<SoundDetailsScreen> {
  late String _displayNameValue;
  late int? _selectedColorValue;
  late double _selectedVolume;
  late Set<int> _selectedTagIds;
  String _tagSearchQuery = '';
  bool _isSaving = false;

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

  @override
  void initState() {
    super.initState();
    _displayNameValue = widget.sound.displayName ?? '';
    _selectedColorValue = widget.sound.colorValue;
    _selectedVolume = widget.sound.volume.clamp(0.0, 1.0);
    _selectedTagIds = widget.initialTags.map((t) => t.id).toSet();
  }

  String? _normalizedDisplayNameOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      await widget.repository.updateSoundSettings(
        id: widget.sound.id,
        colorValue: _selectedColorValue,
        updateColor: true,
        displayName: _normalizedDisplayNameOrNull(_displayNameValue),
        updateDisplayName: true,
        volume: _selectedVolume,
      );
      await widget.repository.setTagsForSound(
        widget.sound.id,
        _selectedTagIds.toList(),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showCopyableSnackBar(context, 'Erreur de sauvegarde: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  List<TagItem> get _allTags {
    final tagsById = <int, TagItem>{};
    for (final category in widget.tagCatalog) {
      for (final tag in category.tags) {
        tagsById[tag.id] = tag;
      }
    }
    final tags = tagsById.values.toList()
      ..sort(
        (a, b) => normalizeForSearch(a.name).compareTo(normalizeForSearch(b.name)),
      );
    return tags;
  }

  List<TagItem> get _selectedTags {
    final selected = _allTags.where((tag) => _selectedTagIds.contains(tag.id)).toList();
    selected.sort((a, b) => a.name.compareTo(b.name));
    return selected;
  }

  List<TagItem> get _filteredTags {
    final normalizedQuery = normalizeForSearch(_tagSearchQuery);
    final matching = _allTags.where((tag) {
      if (normalizedQuery.isEmpty) {
        return true;
      }
      return normalizeForSearch(tag.name).contains(normalizedQuery);
    }).toList();
    matching.sort((a, b) {
      final aSelected = _selectedTagIds.contains(a.id);
      final bSelected = _selectedTagIds.contains(b.id);
      if (aSelected != bSelected) {
        return aSelected ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });
    return matching;
  }

  void _toggleTagSelection(TagItem tag, bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedTagIds.add(tag.id);
      } else {
        _selectedTagIds.remove(tag.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedTags = _selectedTags;
    final filteredTags = _filteredTags;

    return Scaffold(
      appBar: AppBar(
        title: Text('Édition du son "${widget.sound.title}"'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Enregistrer'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSoundTypeHeader(context),
            const SizedBox(height: 24),
            Text(
              'Nom affiché',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _displayNameValue,
              onChanged: (value) {
                _displayNameValue = value;
              },
              decoration: InputDecoration(
                hintText: widget.sound.title,
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
                  isSelected: _selectedColorValue == null,
                  onTap: () {
                    setState(() {
                      _selectedColorValue = null;
                    });
                  },
                ),
                for (final color in _defaultColorChoices)
                  _buildColorChoice(
                    context: context,
                    color: color,
                    isSelected: _selectedColorValue == color.toARGB32(),
                    onTap: () {
                      setState(() {
                        _selectedColorValue = color.toARGB32();
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
                Text('${(_selectedVolume * 100).round()}%'),
              ],
            ),
            Slider(
              value: _selectedVolume,
              min: 0.0,
              max: 1.0,
              label: '${(_selectedVolume * 100).round()}%',
              onChanged: (value) {
                setState(() {
                  _selectedVolume = value.clamp(0.0, 1.0);
                });
              },
            ),
            const SizedBox(height: 8),
            Text('Tags', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            if (_allTags.isEmpty)
              const Text('Aucun tag disponible')
            else ...[
              if (selectedTags.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in selectedTags)
                      InputChip(
                        label: Text(tag.name),
                        onDeleted: () => _toggleTagSelection(tag, false),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                decoration: InputDecoration(
                  hintText: 'Rechercher un tag...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _tagSearchQuery = value;
                  });
                },
              ),
              const SizedBox(height: 8),
              if (filteredTags.isEmpty)
                const Text('Aucun tag trouvé')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in filteredTags)
                      FilterChip(
                        label: Text(tag.name),
                        selected: _selectedTagIds.contains(tag.id),
                        onSelected: (selected) =>
                            _toggleTagSelection(tag, selected),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
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

  String _soundTypeLabel(SoundType type) {
    switch (type) {
      case SoundType.soundEffect:
        return 'Bruitage';
      case SoundType.music:
        return 'Musique';
      case SoundType.ambiance:
        return 'Son d\'ambiance';
    }
  }

  IconData _soundTypeIcon(SoundType type) {
    switch (type) {
      case SoundType.soundEffect:
        return Icons.graphic_eq_rounded;
      case SoundType.music:
        return Icons.music_note_rounded;
      case SoundType.ambiance:
        return Icons.waves_rounded;
    }
  }

  ({Color background, Color foreground}) _soundTypeAvatarColors(
    BuildContext context,
    SoundType type,
  ) {
    final scheme = Theme.of(context).colorScheme;
    switch (type) {
      case SoundType.soundEffect:
        return (
          background: scheme.tertiaryContainer,
          foreground: scheme.onTertiaryContainer,
        );
      case SoundType.music:
        return (
          background: scheme.primaryContainer,
          foreground: scheme.onPrimaryContainer,
        );
      case SoundType.ambiance:
        return (
          background: scheme.secondaryContainer,
          foreground: scheme.onSecondaryContainer,
        );
    }
  }

  Widget _buildSoundTypeHeader(BuildContext context) {
    final type = widget.sound.type;
    final colors = _soundTypeAvatarColors(context, type);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: colors.background,
          child: Icon(
            _soundTypeIcon(type),
            size: 32,
            color: colors.foreground,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.sound.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                _soundTypeLabel(type),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
