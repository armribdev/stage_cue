import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/stroke_icon.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';
import '../models/pad_sound_slot.dart';
import '../providers/sampler_provider.dart';
import '../utils/sound_type_ui.dart';
import 'scrolling_text.dart';
import 'tag_pill.dart';

/// Ligne d'un son dans l'écran de détails d'un pad : type, tags, volume propre
/// au pad, retrait et téléchargement quand le son n'est pas local.
class PadSoundRow extends StatefulWidget {
  final PadItem padItem;
  final int slotIndex;
  final Sound sound;
  final bool canRemove;
  final List<TagCategoryWithTags> tagCatalog;
  final bool isTagsLoading;
  final SamplerNotifier notifier;
  final VoidCallback onRemove;

  const PadSoundRow({
    super.key,
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
  State<PadSoundRow> createState() => _PadSoundRowState();
}

class _PadSoundRowState extends State<PadSoundRow> {
  static const _maxVisibleTags = 3;

  Set<int> _tagIds = {};
  bool _loaded = false;
  late double _volume;
  bool _hovered = false;

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

  List<TagItem> _resolvedTags() {
    final tags = <TagItem>[];
    for (final cat in widget.tagCatalog) {
      for (final tag in cat.tags) {
        if (_tagIds.contains(tag.id)) tags.add(tag);
      }
    }
    return tags;
  }

  Color? _categoryColor(int categoryId) {
    for (final group in widget.tagCatalog) {
      if (group.category.id == categoryId) return Color(group.category.color);
    }
    return null;
  }

  Widget _buildTagRow(List<TagItem> tags) {
    return TagPillRow(
      maxVisible: _maxVisibleTags,
      tags: [
        for (final tag in tags)
          (
            label: TextSpan(text: tag.name),
            color: _categoryColor(tag.categoryId),
          ),
      ],
    );
  }

  Widget _buildSubtitle(
    ColorScheme scheme, {
    required bool isLocal,
    required bool isDownloading,
  }) {
    if (isDownloading) {
      return Text(
        'Téléchargement…',
        style: TextStyle(
          fontSize: 12,
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Row(
      children: [
        Text(
          widget.sound.typeDisplayLabel,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        if (!isLocal) ...[
          const SizedBox(width: 6),
          StrokeIcon(
            AppIcons.cloud,
            size: AppIconSize.sm,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ],
      ],
    );
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

        final tags = _loaded ? _resolvedTags() : const <TagItem>[];

        final soundContent = Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SoundTypeAvatar(
              type: sound.type,
              colorValue: sound.colorValue,
              radius: 12,
              iconSize: 14,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MouseRegion(
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ScrollingTextSpan(
                      animate: _hovered,
                      span: TextSpan(text: sound.displayName),
                    ),
                    _buildSubtitle(
                      scheme,
                      isLocal: isLocal,
                      isDownloading: isDownloading,
                    ),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      _buildTagRow(tags),
                    ],
                  ],
                ),
              ),
            ),
            // Volume propre à ce son dans ce pad — barre compacte inline
            // (plutôt qu'une rangée pleine largeur séparée) ; visible
            // seulement quand le son est jouable localement.
            if (isLocal) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 56,
                child: Slider(
                  value: _volume.clamp(0.0, 1.0),
                  min: 0.0,
                  max: 1.0,
                  label: '${(_volume * 100).round()}%',
                  onChanged: _updateVolume,
                ),
              ),
            ],
            if (widget.canRemove) ...[
              const SizedBox(width: 2),
              IconButton(
                icon: const StrokeIcon(AppIcons.close, size: 16),
                onPressed: widget.onRemove,
                color: scheme.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                style: canDownload
                    ? IconButton.styleFrom(hoverColor: Colors.transparent)
                    : null,
              ),
            ],
          ],
        );

        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.all(AppSpacing.sm + 2),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: AppRadius.radiusMd,
            border: Border.fromBorderSide(AppElevation.border(scheme)),
          ),
          child: canDownload
              ? Material(
                  color: Colors.transparent,
                  borderRadius: AppRadius.radiusSm,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => unawaited(_downloadSound()),
                    borderRadius: AppRadius.radiusSm,
                    hoverColor: scheme.onSurface.withValues(alpha: 0.08),
                    splashColor: scheme.onSurface.withValues(alpha: 0.12),
                    child: soundContent,
                  ),
                )
              : soundContent,
        );
      },
    );
  }
}
