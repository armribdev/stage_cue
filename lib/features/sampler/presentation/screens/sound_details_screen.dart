import 'dart:async';

import 'package:flutter/material.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../providers/sampler_provider.dart';

/// Écran de détails d'un son
class SoundDetailScreen extends StatefulWidget {
  final SoundItem soundItem;
  final SamplerNotifier notifier;

  const SoundDetailScreen({
    super.key,
    required this.soundItem,
    required this.notifier,
  });

  @override
  State<SoundDetailScreen> createState() => _SoundDetailScreenState();
}

class _SoundDetailScreenState extends State<SoundDetailScreen> {
  late Color? _selectedColor;
  late double _volume;
  late final TextEditingController _displayNameController;
  Timer? _displayNameDebounce;
  List<TagCategoryWithTags> _tagCatalog = [];
  Set<int> _selectedTagIds = {};
  bool _isTagsLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.soundItem.buttonColor;
    _volume = widget.soundItem.volume.clamp(0.0, 1.0);
    _displayNameController = TextEditingController(
      text: widget.soundItem.sound.displayName ?? '',
    );
    _loadTags();
  }

  @override
  void dispose() {
    _displayNameDebounce?.cancel();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    setState(() {
      _isTagsLoading = true;
    });
    final catalog = await widget.notifier.loadTagCatalog();
    final selected = await widget.notifier.getTagsForSound(
      widget.soundItem.sound.id,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _tagCatalog = catalog;
      _selectedTagIds = selected.map((t) => t.id).toSet();
      _isTagsLoading = false;
    });
  }

  String _getSoundTypeLabel(SoundType type) {
    switch (type) {
      case SoundType.soundEffect:
        return 'Bruitage';
      case SoundType.music:
        return 'Musique';
      case SoundType.ambiance:
        return 'Son d\'ambiance';
    }
  }

  void _updateColor(Color? color) {
    setState(() {
      _selectedColor = color;
    });
    widget.notifier.updateSoundItemSettings(
      widget.soundItem,
      buttonColor: color,
      updateColor: true,
    );
  }

  void _updateVolume(double value) {
    final clamped = value.clamp(0.0, 1.0);
    setState(() {
      _volume = clamped;
    });
    widget.notifier.updateSoundItemSettings(widget.soundItem, volume: clamped);
    widget.soundItem.player.setVolume(clamped);
  }

  Future<void> _updateDisplayName() async {
    final trimmed = _displayNameController.text.trim();
    await widget.notifier.updateSoundItemSettings(
      widget.soundItem,
      displayName: trimmed.isEmpty ? null : trimmed,
      updateDisplayName: true,
    );
  }

  void _scheduleDisplayNameUpdate(String _) {
    _displayNameDebounce?.cancel();
    _displayNameDebounce = Timer(const Duration(milliseconds: 400), () {
      _updateDisplayName();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sound = widget.soundItem.sound;
    final colorChoices = <Color>[
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.brown,
      Colors.grey,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Détails du son')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sound.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow(
                      context,
                      'Type',
                      _getSoundTypeLabel(sound.type),
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow(context, 'Chemin', sound.filePath),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      context,
                      'Date de création',
                      _formatDate(sound.createdAt),
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow(context, 'ID', sound.id.toString()),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            'Tags:',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _isTagsLoading
                              ? const Center(child: CircularProgressIndicator())
                              : (_tagCatalog.isEmpty || _selectedTagIds.isEmpty)
                              ? Text(
                                  'Aucun tag disponible',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                )
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    return Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      clipBehavior: Clip.none,
                                      alignment: WrapAlignment.start,
                                      children: [
                                        for (final category in _tagCatalog)
                                          ...category.tags
                                              .where(
                                                (tag) => _selectedTagIds
                                                    .contains(tag.id),
                                              )
                                              .map(
                                                (tag) => Chip(
                                                  materialTapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  padding: EdgeInsets.zero,
                                                  label: Text(
                                                    tag.name,
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.labelSmall,
                                                  ),
                                                  backgroundColor: Color(
                                                    category.category.color,
                                                  ).withAlpha(40),
                                                ),
                                              ),
                                      ],
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Réglages du pad',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _displayNameController,
                      decoration: InputDecoration(
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        labelText: 'Nom affiché :',
                        hintText: sound.title,
                        border: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        suffixIcon: _displayNameController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _displayNameController.clear();
                                  });
                                  _updateDisplayName();
                                },
                              )
                            : null,
                      ),
                      textInputAction: TextInputAction.done,
                      onChanged: (value) {
                        setState(() {});
                        _scheduleDisplayNameUpdate(value);
                      },
                      onSubmitted: (_) => _updateDisplayName(),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Couleur du bouton',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildDefaultColorOption(context),
                        for (final color in colorChoices)
                          _buildColorDot(context, color),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Volume',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Text('${(_volume * 100).round()}%'),
                      ],
                    ),
                    Slider(
                      value: _volume,
                      min: 0.0,
                      max: 1.0,
                      label: '${(_volume * 100).round()}%',
                      onChanged: _updateVolume,
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

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            '$label:',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildDefaultColorOption(BuildContext context) {
    final isSelected = _selectedColor == null;
    final scheme = Theme.of(context).colorScheme;
    final borderColor = isSelected ? scheme.primary : scheme.outlineVariant;
    final onSurface = scheme.onSurfaceVariant;
    return Tooltip(
      message: 'Couleur par défaut',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _updateColor(null),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.surfaceContainerHighest,
            border: Border.all(color: borderColor, width: isSelected ? 3 : 1),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: isSelected
              ? Icon(Icons.check, color: onSurface, size: 20)
              : Text(
                  'D',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: onSurface,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildColorDot(BuildContext context, Color color) {
    final isSelected = _selectedColor == color;
    final scheme = Theme.of(context).colorScheme;
    final borderColor = isSelected ? scheme.primary : scheme.outlineVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _updateColor(color),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: borderColor, width: isSelected ? 3 : 1),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: isSelected
            ? Icon(Icons.check, color: _getCheckmarkColor(color), size: 20)
            : null,
      ),
    );
  }

  Color _getCheckmarkColor(Color color) {
    return color.computeLuminance() > 0.6 ? Colors.black : Colors.white;
  }
}
