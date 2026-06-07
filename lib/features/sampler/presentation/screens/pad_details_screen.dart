import 'dart:async';

import 'package:flutter/material.dart';
import '../../domain/entities/pad.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../widgets/pad_button.dart' show padSoundAvailabilityIcon;
import '../models/pad_sound_slot.dart';
import '../providers/sampler_provider.dart';
import '../utils/sound_type_ui.dart';

/// Écran de détails d'un pad — réglages, sons, mode de lecture.
class PadDetailsScreen extends StatefulWidget {
  final PadItem padItem;
  final SamplerNotifier notifier;

  const PadDetailsScreen({
    super.key,
    required this.padItem,
    required this.notifier,
  });

  @override
  State<PadDetailsScreen> createState() => _PadDetailsScreenState();
}

class _PadDetailsScreenState extends State<PadDetailsScreen> {
  late Color? _selectedColor;
  late double _volume;
  late PadPlayMode _playMode;
  late final TextEditingController _displayNameController;
  Timer? _displayNameDebounce;
  List<TagCategoryWithTags> _tagCatalog = [];
  bool _isTagsLoading = true;

  @override
  void initState() {
    super.initState();
    final pad = widget.padItem.pad;
    _selectedColor = pad.colorValue != null ? Color(pad.colorValue!) : null;
    _volume = pad.volume.clamp(0.0, 1.0);
    _playMode = pad.playMode;
    _displayNameController = TextEditingController(text: pad.name ?? '');
    _loadTagCatalog();
  }

  @override
  void dispose() {
    _displayNameDebounce?.cancel();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _loadTagCatalog() async {
    final catalog = await widget.notifier.loadTagCatalog();
    if (!mounted) return;
    setState(() {
      _tagCatalog = catalog;
      _isTagsLoading = false;
    });
  }

  void _updateColor(Color? color) {
    setState(() => _selectedColor = color);
    widget.notifier.updatePadItemSettings(
      widget.padItem,
      buttonColor: color,
      updateColor: true,
    );
  }

  void _updateVolume(double value) {
    final clamped = value.clamp(0.0, 1.0);
    setState(() => _volume = clamped);
    widget.notifier.updatePadItemSettings(widget.padItem, volume: clamped);
    widget.padItem.currentPlayer?.setVolume(clamped);
  }

  void _updatePlayMode(PadPlayMode mode) {
    setState(() => _playMode = mode);
    widget.notifier.updatePadItemSettings(widget.padItem, playMode: mode);
  }

  Future<void> _updateDisplayName() async {
    if (!mounted) return;
    final trimmed = _displayNameController.text.trim();
    await widget.notifier.updatePadItemSettings(
      widget.padItem,
      displayName: trimmed.isEmpty ? null : trimmed,
      updateDisplayName: true,
    );
  }

  void _scheduleDisplayNameUpdate(String _) {
    _displayNameDebounce?.cancel();
    _displayNameDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _updateDisplayName();
    });
  }

  Future<void> _addSound(BuildContext ctx) async {
    final pad = widget.padItem.pad;
    // Ouvrir la bibliothèque pour choisir un son à ajouter à ce pad
    await showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => _AddSoundSheet(
        padId: pad.id,
        notifier: widget.notifier,
        tagCatalog: _tagCatalog,
      ),
    );
    if (!mounted) return;
    setState(() {}); // Rafraîchir après ajout
  }

  Future<void> _removeSound(int soundId) async {
    await widget.notifier.removeSoundFromPad(
      widget.padItem.pad.id,
      soundId,
    );
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pad = widget.padItem.pad;
    final sounds = pad.sounds;
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
      appBar: AppBar(title: const Text('Détails du pad')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Réglages du pad ──────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Réglages du pad',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nom affiché',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _displayNameController,
                      decoration: InputDecoration(
                        hintText: pad.displayName,
                        border: OutlineInputBorder(
                          borderSide:
                              BorderSide(color: scheme.outline),
                        ),
                        suffixIcon: _displayNameController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(
                                    () => _displayNameController.clear(),
                                  );
                                  _updateDisplayName();
                                },
                              )
                            : null,
                      ),
                      textInputAction: TextInputAction.done,
                      onChanged: (v) {
                        setState(() {});
                        _scheduleDisplayNameUpdate(v);
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
                        for (final c in colorChoices)
                          _buildColorDot(context, c),
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
                    if (sounds.length > 1) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Mode de lecture',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      _PlayModeSelector(
                        value: _playMode,
                        onChanged: _updatePlayMode,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Sons du pad ───────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Sons du pad',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _addSound(context),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Ajouter'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (sounds.isEmpty)
                      Text(
                        'Aucun son',
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    else
                      Column(
                        children: [
                          for (var i = 0; i < sounds.length; i++)
                            _SoundRow(
                              sound: sounds[i],
                              availability: i < widget.padItem.slots.length
                                  ? widget.padItem.slots[i].availability
                                  : PadSoundAvailability.needsDownload,
                              canRemove: sounds.length > 1,
                              typeLabel: sounds[i].type.label,
                              tagCatalog: _tagCatalog,
                              isTagsLoading: _isTagsLoading,
                              notifier: widget.notifier,
                              onRemove: () => _removeSound(sounds[i].id),
                            ),
                        ],
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
            ? Icon(Icons.check, color: _checkColor(color), size: 20)
            : null,
      ),
    );
  }

  Color _checkColor(Color color) =>
      color.computeLuminance() > 0.6 ? Colors.black : Colors.white;
}

// ── Sélecteur de mode de lecture ──────────────────────────────────────────

class _PlayModeSelector extends StatelessWidget {
  final PadPlayMode value;
  final ValueChanged<PadPlayMode> onChanged;

  const _PlayModeSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<PadPlayMode>(
      segments: const [
        ButtonSegment(
          value: PadPlayMode.random,
          icon: Icon(Icons.shuffle_rounded, size: 16),
          label: Text('Aléatoire'),
        ),
        ButtonSegment(
          value: PadPlayMode.sequential,
          icon: Icon(Icons.repeat_one_rounded, size: 16),
          label: Text('Séquentiel'),
        ),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

// ── Ligne d'un son ────────────────────────────────────────────────────────

class _SoundRow extends StatefulWidget {
  final Sound sound;
  final PadSoundAvailability availability;
  final bool canRemove;
  final String typeLabel;
  final List<TagCategoryWithTags> tagCatalog;
  final bool isTagsLoading;
  final SamplerNotifier notifier;
  final VoidCallback onRemove;

  const _SoundRow({
    required this.sound,
    required this.availability,
    required this.canRemove,
    required this.typeLabel,
    required this.tagCatalog,
    required this.isTagsLoading,
    required this.notifier,
    required this.onRemove,
  });

  @override
  State<_SoundRow> createState() => _SoundRowState();
}

class _SoundRowState extends State<_SoundRow> {
  Set<int> _tagIds = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final tags = await widget.notifier.getTagsForSound(widget.sound.id);
    if (!mounted) return;
    setState(() {
      _tagIds = tags.map((t) => t.id).toSet();
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sound = widget.sound;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          padSoundAvailabilityIcon(widget.availability, scheme, size: 20),
          const SizedBox(width: 8),
          SoundTypeAvatar(type: sound.type, radius: 16, iconSize: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sound.displayName ?? sound.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  widget.typeLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (_loaded && _tagIds.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      for (final cat in widget.tagCatalog)
                        ...cat.tags
                            .where((t) => _tagIds.contains(t.id))
                            .map(
                              (t) => Chip(
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                padding: EdgeInsets.zero,
                                label: Text(
                                  t.name,
                                  style:
                                      Theme.of(context).textTheme.labelSmall,
                                ),
                                backgroundColor:
                                    Color(cat.category.color).withAlpha(40),
                              ),
                            ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (widget.canRemove)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              tooltip: 'Retirer ce son du pad',
              onPressed: widget.onRemove,
              color: scheme.error,
            ),
        ],
      ),
    );
  }
}

// ── Sheet d'ajout de son ──────────────────────────────────────────────────

class _AddSoundSheet extends StatefulWidget {
  final int padId;
  final SamplerNotifier notifier;
  final List<TagCategoryWithTags> tagCatalog;

  const _AddSoundSheet({
    required this.padId,
    required this.notifier,
    required this.tagCatalog,
  });

  @override
  State<_AddSoundSheet> createState() => _AddSoundSheetState();
}

class _AddSoundSheetState extends State<_AddSoundSheet> {
  List<Sound> _sounds = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSounds();
  }

  Future<void> _loadSounds() async {
    final all = await widget.notifier.getAllSounds();
    if (!mounted) return;
    setState(() {
      _sounds = all;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Ajouter un son au pad',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: controller,
                    itemCount: _sounds.length,
                    itemBuilder: (_, i) {
                      final s = _sounds[i];
                      return ListTile(
                        leading: SoundTypeAvatar(type: s.type, radius: 18),
                        title: Text(s.displayName ?? s.title),
                        subtitle: Text(s.type.label),
                        onTap: () async {
                          await widget.notifier.addSoundToPad(
                            widget.padId,
                            s.id,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

}
