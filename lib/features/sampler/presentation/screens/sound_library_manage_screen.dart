import 'package:flutter/material.dart';

import '../../../../core/database/database.dart' as db;
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../providers/sampler_provider.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/sound_picker_overlay.dart';
import '../widgets/sound_type_picker.dart';
import '../widgets/start_offset_editor.dart';
import '../widgets/tag_chips_editor.dart';
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
          _openSoundEdit(ctx, sound, tagCatalog, repository, notifier),
    );
  }

  // ── Dispatch mobile / tablette ────────────────────────────────────────────

  static Future<void> _openSoundEdit(
    BuildContext context,
    Sound sound,
    List<TagCategoryWithTags> tagCatalog,
    SoundRepository repository,
    SamplerNotifier notifier,
  ) async {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) {
      await _openEditPage(context, sound, tagCatalog, repository, notifier);
    } else {
      await _openEditDialog(context, sound, tagCatalog, repository, notifier);
    }
  }

  // ── Page plein écran (mobile) ─────────────────────────────────────────────

  static Future<void> _openEditPage(
    BuildContext context,
    Sound sound,
    List<TagCategoryWithTags> tagCatalog,
    SoundRepository repository,
    SamplerNotifier notifier,
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
          notifier: notifier,
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
    SamplerNotifier notifier,
  ) async {
    final initialTags = await repository.getTagsForSound(sound.id);
    if (!context.mounted) return;

    final dialogScrollController = ScrollController();
    var selectedColorValue = sound.colorValue;
    var selectedVolume = sound.volume.clamp(0.0, 1.0);
    var displayNameValue = sound.displayName ?? '';
    var startOffsetMs = sound.startOffsetMs;
    var selectedType = sound.type;
    final selectedTagIds = initialTags.map((t) => t.id).toSet();

    String? normalizedOrNull(String value) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
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
                      Text(
                        'Nom affiché',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
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
                      const SizedBox(height: 12),
                      Text(
                        'Type de son',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      SoundTypePicker(
                        selected: selectedType,
                        onChanged: (type) =>
                            setDialogState(() => selectedType = type),
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
                      const SizedBox(height: sectionSpacing),
                      Text(
                        'Point d\'entrée',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'La lecture démarre à ce point au lieu du début du fichier.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 8),
                      StartOffsetEditor(
                        filePath: sound.filePath,
                        waveform: sound.waveform,
                        initialOffsetMs: startOffsetMs,
                        onChanged: (ms) => startOffsetMs = ms,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tags',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      TagChipsEditor(
                        tagCatalog: tagCatalog,
                        selectedTagIds: selectedTagIds,
                        onTagAdded: (id) =>
                            setDialogState(() => selectedTagIds.add(id)),
                        onTagRemoved: (id) =>
                            setDialogState(() => selectedTagIds.remove(id)),
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
                      startOffsetMs: startOffsetMs,
                    );
                    await repository.setTagsForSound(
                        sound.id, selectedTagIds.toList());
                    if (selectedType != null && selectedType != sound.type) {
                      await repository.updateSoundType(sound.id, selectedType!);
                    }
                    await notifier.refreshSoundMetadata(sound.id);
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
