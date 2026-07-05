import 'package:flutter/material.dart';
import '../../../../core/utils/copyable_snackbar.dart';
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';
import '../providers/sampler_provider.dart';
import '../utils/sound_type_ui.dart';
import '../widgets/sound_type_picker.dart';
import '../widgets/start_offset_editor.dart';
import '../widgets/tag_chips_editor.dart';

/// Écran d'édition d'un son dans la bibliothèque.
class SoundDetailsScreen extends StatefulWidget {
  final Sound sound;
  final List<TagCategoryWithTags> tagCatalog;
  final List<TagItem> initialTags;
  final SoundRepository repository;
  final SamplerNotifier? notifier;

  const SoundDetailsScreen({
    super.key,
    required this.sound,
    required this.tagCatalog,
    required this.initialTags,
    required this.repository,
    this.notifier,
  });

  @override
  State<SoundDetailsScreen> createState() => _SoundDetailsScreenState();
}

class _SoundDetailsScreenState extends State<SoundDetailsScreen> {
  late String _displayNameValue;
  late int? _selectedColorValue;
  late double _selectedVolume;
  late int _startOffsetMs;
  late Set<int> _selectedTagIds;
  late SoundType? _selectedType;
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
    _startOffsetMs = widget.sound.startOffsetMs;
    _selectedTagIds = widget.initialTags.map((t) => t.id).toSet();
    _selectedType = widget.sound.type;
  }

  String? _normalizedDisplayNameOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await widget.repository.updateSoundSettings(
        id: widget.sound.id,
        colorValue: _selectedColorValue,
        updateColor: true,
        displayName: _normalizedDisplayNameOrNull(_displayNameValue),
        updateDisplayName: true,
        volume: _selectedVolume,
        startOffsetMs: _startOffsetMs,
      );
      await widget.repository.setTagsForSound(
        widget.sound.id,
        _selectedTagIds.toList(),
      );
      if (_selectedType != null && _selectedType != widget.sound.type) {
        await widget.repository.updateSoundType(
          widget.sound.id,
          _selectedType!,
        );
      }
      await widget.notifier?.refreshSoundMetadata(widget.sound.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      showCopyableSnackBar(context, 'Erreur de sauvegarde: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
            _buildSoundTypeHeader(context),
            const SizedBox(height: 24),
            Text(
              'Nom affiché',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _displayNameValue,
              onChanged: (value) => _displayNameValue = value,
              decoration: InputDecoration(
                hintText: widget.sound.title,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Type de son',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            SoundTypePicker(
              selected: _selectedType,
              onChanged: (type) => setState(() => _selectedType = type),
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
                  onTap: () => setState(() => _selectedColorValue = null),
                ),
                for (final color in _defaultColorChoices)
                  _buildColorChoice(
                    context: context,
                    color: color,
                    isSelected: _selectedColorValue == color.toARGB32(),
                    onTap: () =>
                        setState(() => _selectedColorValue = color.toARGB32()),
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
              onChanged: (value) =>
                  setState(() => _selectedVolume = value.clamp(0.0, 1.0)),
            ),
            const SizedBox(height: 8),
            Text(
              'Point d\'entrée',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'La lecture démarre à ce point au lieu du début du fichier.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            StartOffsetEditor(
              filePath: widget.sound.filePath,
              waveform: widget.sound.waveform,
              initialOffsetMs: _startOffsetMs,
              onChanged: (ms) => setState(() => _startOffsetMs = ms),
            ),
            const SizedBox(height: 16),
            Text('Tags', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            TagChipsEditor(
              tagCatalog: widget.tagCatalog,
              selectedTagIds: _selectedTagIds,
              onTagAdded: (id) => setState(() => _selectedTagIds.add(id)),
              onTagRemoved: (id) => setState(() => _selectedTagIds.remove(id)),
            ),
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

  Color _getCheckmarkColor(Color color) =>
      color.computeLuminance() > 0.6 ? Colors.black : Colors.white;

  Widget _buildSoundTypeHeader(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SoundTypeAvatar(type: _selectedType, radius: 32, iconSize: 32),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            widget.sound.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ],
    );
  }
}
