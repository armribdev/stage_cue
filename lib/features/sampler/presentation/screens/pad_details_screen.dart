import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/app_modal.dart';
import '../../domain/entities/pad.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../models/pad_sound_slot.dart';
import '../providers/sampler_provider.dart';
import '../utils/sound_type_ui.dart';
import '../widgets/sound_picker_overlay.dart';

/// Écran de détails d'un pad — réglages, sons, mode de lecture.
class PadDetailsScreen extends StatefulWidget {
  final PadItem padItem;
  final SamplerNotifier notifier;
  final bool isModal;
  final bool openPickerOnStart;

  const PadDetailsScreen({
    super.key,
    required this.padItem,
    required this.notifier,
    this.isModal = false,
    this.openPickerOnStart = false,
  });

  /// Page plein écran sur téléphone, fenêtre modale sur tablette et desktop.
  static Future<void> open(
    BuildContext context, {
    required PadItem padItem,
    required SamplerNotifier notifier,
    bool openPickerOnStart = false,
  }) {
    return openAdaptiveScreen(
      context: context,
      builder: ({required isModal}) => PadDetailsScreen(
        padItem: padItem,
        notifier: notifier,
        isModal: isModal,
        openPickerOnStart: openPickerOnStart,
      ),
    );
  }

  @override
  State<PadDetailsScreen> createState() => _PadDetailsScreenState();
}

class _PadDetailsScreenState extends State<PadDetailsScreen> {
  static const List<Color> _colorChoices = <Color>[
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.red,
    Colors.teal,
    Colors.brown,
    Colors.grey,
  ];

  late int? _selectedColorValue;
  late PadPlayMode _playMode;
  late final TextEditingController _displayNameController;
  Timer? _displayNameDebounce;
  List<TagCategoryWithTags> _tagCatalog = [];
  bool _isTagsLoading = true;

  @override
  void initState() {
    super.initState();
    final pad = widget.padItem.pad;
    _selectedColorValue = pad.colorValue;
    _playMode = pad.playMode;
    _displayNameController = TextEditingController(text: pad.name ?? '');
    _loadTagCatalog();
    if (widget.openPickerOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addSound(context);
      });
    }
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

  void _updateColor(int? colorValue) {
    setState(() => _selectedColorValue = colorValue);
    widget.notifier.updatePadItemSettings(
      widget.padItem,
      buttonColor: colorValue != null ? Color(colorValue) : null,
      updateColor: true,
    );
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
    await SoundPickerOverlay.showForPad(
      ctx,
      notifier: widget.notifier,
      padId: widget.padItem.pad.id,
      onPadUpdated: () {
        if (mounted) setState(() {});
      },
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _removeSound(int soundId) async {
    await widget.notifier.removeSoundFromPad(
      widget.padItem.pad.id,
      soundId,
    );
    if (!mounted) return;
    setState(() {});
  }

  Widget _buildBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pad = widget.padItem.pad;
    final sounds = pad.sounds;
    return SingleChildScrollView(
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
                        hintText: widget.padItem.displayName,
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
                        for (final c in _colorChoices)
                          _buildColorDot(context, c),
                      ],
                    ),
                    if (sounds.length > 1) ...[
                      const SizedBox(height: 16),
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
                      ListenableBuilder(
                        listenable: widget.notifier,
                        builder: (context, _) {
                          final offlineMode = widget.notifier.offlineMode;
                          final visibleIndices = <int>[
                            for (var i = 0; i < sounds.length; i++)
                              if (!offlineMode ||
                                  widget.notifier.isSlotLocallyAvailable(
                                    widget.padItem,
                                    i,
                                  ))
                                i,
                          ];
                          if (visibleIndices.isEmpty) {
                            return Text(
                              offlineMode
                                  ? 'Aucun son disponible hors-ligne'
                                  : 'Aucun son',
                              style: Theme.of(context).textTheme.bodyMedium,
                            );
                          }
                          return Column(
                            children: [
                              for (final i in visibleIndices)
                                _SoundRow(
                                  padItem: widget.padItem,
                                  slotIndex: i,
                                  sound: sounds[i],
                                  canRemove: sounds.length > 1,
                                  tagCatalog: _tagCatalog,
                                  isTagsLoading: _isTagsLoading,
                                  notifier: widget.notifier,
                                  onRemove: () => _removeSound(sounds[i].id),
                                ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);

    if (widget.isModal) {
      return AppModalShell(title: 'Détails du pad', body: body);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Détails du pad')),
      body: body,
    );
  }

  Widget _buildDefaultColorOption(BuildContext context) {
    final isSelected = _selectedColorValue == null;
    final scheme = Theme.of(context).colorScheme;
    final borderColor = isSelected ? scheme.primary : scheme.outlineVariant;
    final onSurface = scheme.onSurfaceVariant;
    return InkWell(
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
    );
  }

  Widget _buildColorDot(BuildContext context, Color color) {
    final isSelected = _selectedColorValue == color.toARGB32();
    final scheme = Theme.of(context).colorScheme;
    final borderColor = isSelected ? scheme.primary : scheme.outlineVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _updateColor(color.toARGB32()),
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
  final PadItem padItem;
  final int slotIndex;
  final Sound sound;
  final bool canRemove;
  final List<TagCategoryWithTags> tagCatalog;
  final bool isTagsLoading;
  final SamplerNotifier notifier;
  final VoidCallback onRemove;

  const _SoundRow({
    required this.padItem,
    required this.slotIndex,
    required this.sound,
    required this.canRemove,
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
  late double _volume;

  @override
  void initState() {
    super.initState();
    _volume = _resolvedPadItem().pad.effectiveVolume(widget.slotIndex);
    _loadTags();
  }

  void _updateVolume(double value) {
    final clamped = value.clamp(0.0, 1.0);
    setState(() => _volume = clamped);
    widget.notifier.updatePadSoundVolume(
      _resolvedPadItem(),
      widget.sound.id,
      clamped,
    );
  }

  Widget _buildVolumeControl(BuildContext context, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 2),
      child: Row(
        children: [
          Icon(Icons.volume_up_rounded, size: 18, color: scheme.onSurfaceVariant),
          Expanded(
            child: Slider(
              value: _volume.clamp(0.0, 1.0),
              min: 0.0,
              max: 1.0,
              label: '${(_volume * 100).round()}%',
              onChanged: _updateVolume,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '${(_volume * 100).round()}%',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadTags() async {
    final tags = await widget.notifier.getTagsForSound(widget.sound.id);
    if (!mounted) return;
    setState(() {
      _tagIds = tags.map((t) => t.id).toSet();
      _loaded = true;
    });
  }

  PadItem _resolvedPadItem() =>
      widget.notifier.findPadItemById(widget.padItem.pad.id) ?? widget.padItem;

  PadSoundAvailability _availability(PadItem padItem) =>
      widget.slotIndex < padItem.slots.length
          ? padItem.slots[widget.slotIndex].availability
          : PadSoundAvailability.needsDownload;

  bool _isLocal(PadSoundAvailability availability) =>
      availability == PadSoundAvailability.ready ||
      availability == PadSoundAvailability.cached;

  bool _canDownload(PadSoundAvailability availability) =>
      availability == PadSoundAvailability.needsDownload ||
      availability == PadSoundAvailability.offline ||
      availability == PadSoundAvailability.missingFile;

  Future<void> _downloadSound() async {
    final padItem = _resolvedPadItem();
    final availability = _availability(padItem);
    if (!_canDownload(availability)) return;
    if (padItem.downloadingSlotIndex == widget.slotIndex) return;

    await widget.notifier.downloadPadSoundAtIndex(padItem, widget.slotIndex);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sound = widget.sound;

    return ListenableBuilder(
      listenable: widget.padItem.revision,
      builder: (context, _) {
        final padItem = _resolvedPadItem();
        final availability = _availability(padItem);
        final isLocal = _isLocal(availability);
        final isDownloading = padItem.downloadingSlotIndex == widget.slotIndex;
        final canDownload = _canDownload(availability) && !isDownloading;
        final mutedColor = scheme.onSurface.withValues(alpha: 0.42);

        final soundContent = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SoundSlotAvatar(
              type: sound.type,
              isLocal: isLocal,
              isDownloading: isDownloading,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sound.displayName ?? sound.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isLocal ? null : mutedColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sound.typeDisplayLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isLocal
                          ? scheme.onSurfaceVariant
                          : mutedColor,
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
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
                onPressed: widget.onRemove,
                color: scheme.error,
                style: canDownload
                    ? IconButton.styleFrom(
                        hoverColor: Colors.transparent,
                      )
                    : null,
              ),
          ],
        );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (canDownload)
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => unawaited(_downloadSound()),
                    borderRadius: BorderRadius.circular(8),
                    hoverColor: scheme.onSurface.withValues(alpha: 0.08),
                    splashColor: scheme.onSurface.withValues(alpha: 0.12),
                    child: soundContent,
                  ),
                )
              else
                soundContent,
              // Volume propre à ce son dans ce pad — visible seulement quand le
              // son est jouable localement (sinon le réglage n'a pas d'effet).
              if (isLocal) _buildVolumeControl(context, scheme),
            ],
          ),
        );
      },
    );
  }
}

/// Avatar du son avec état local / téléchargement.
class _SoundSlotAvatar extends StatelessWidget {
  final SoundType? type;
  final bool isLocal;
  final bool isDownloading;

  const _SoundSlotAvatar({
    required this.type,
    required this.isLocal,
    required this.isDownloading,
  });

  static const double _radius = 16;
  static const double _iconSize = 18;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const ringSize = _radius * 2 + 8;

    Widget avatar = Opacity(
      opacity: isLocal ? 1 : 0.38,
      child: SoundTypeAvatar(
        type: type,
        radius: _radius,
        iconSize: _iconSize,
      ),
    );

    avatar = SizedBox(
      width: ringSize,
      height: ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isDownloading)
            SizedBox(
              width: ringSize,
              height: ringSize,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            ),
          avatar,
        ],
      ),
    );

    return avatar;
  }
}

