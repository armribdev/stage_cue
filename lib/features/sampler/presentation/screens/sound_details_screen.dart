import 'package:flutter/material.dart';
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

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      final trimmed = _displayNameValue.trim();
      await widget.repository.updateSoundSettings(
        id: widget.sound.id,
        colorValue: _selectedColorValue,
        updateColor: true,
        displayName: trimmed.isEmpty ? null : trimmed,
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
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de la sauvegarde')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            for (final category in widget.tagCatalog) ...[
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
                      selected: _selectedTagIds.contains(tag.id),
                      backgroundColor: Color(category.category.color).withAlpha(
                        25,
                      ),
                      selectedColor: Color(category.category.color).withAlpha(70),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedTagIds.add(tag.id);
                          } else {
                            _selectedTagIds.remove(tag.id);
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
}
