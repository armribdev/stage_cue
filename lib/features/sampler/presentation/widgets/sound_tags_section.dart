import 'package:flutter/material.dart';

import '../../../../core/autotag/auto_tag_status.dart';
import '../../domain/entities/sound_auto_tag.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import 'auto_tag_chips.dart';
import 'auto_tag_status_row.dart';
import 'tag_chips_editor.dart';

/// Section « Tags » du formulaire d'un son : éditeur des tags de l'utilisateur,
/// suggestions de l'IA (décision 0031) et état de l'analyse. Sans état propre :
/// tout vient de [SoundEditForm], qui reste seul à décider de ce qui est modifié.
class SoundTagsSection extends StatelessWidget {
  final List<TagCategoryWithTags> tagCatalog;
  final Set<int> selectedTagIds;
  final List<SoundAutoTag> autoTags;
  final bool tagsLoaded;
  final bool tagsFailed;

  /// La fonction d'analyse existe sur cet appareil (`false` sur mobile).
  final bool hasAnalysis;
  final SoundAnalysisStatus? analysisStatus;

  /// L'utilisateur a cliqué « Analyser » et le passage n'est pas fini.
  final bool analysisRequested;
  final ValueChanged<int> onTagAdded;
  final ValueChanged<int> onTagRemoved;
  final VoidCallback onStartAnalysis;

  const SoundTagsSection({
    super.key,
    required this.tagCatalog,
    required this.selectedTagIds,
    required this.autoTags,
    required this.tagsLoaded,
    required this.tagsFailed,
    required this.hasAnalysis,
    required this.analysisStatus,
    required this.analysisRequested,
    required this.onTagAdded,
    required this.onTagRemoved,
    required this.onStartAnalysis,
  });

  Map<int, Color> _categoryColorsByTagId() => {
    for (final cat in tagCatalog)
      for (final tag in cat.tags) tag.id: Color(cat.category.color),
  };

  @override
  Widget build(BuildContext context) {
    if (tagsFailed) {
      return Text(
        'Tags indisponibles — réessayez en rouvrant le son.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    if (!tagsLoaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final editor = TagChipsEditor(
      tagCatalog: tagCatalog,
      selectedTagIds: selectedTagIds,
      onTagAdded: onTagAdded,
      onTagRemoved: onTagRemoved,
    );
    final status = analysisStatus;
    // Analysé : rien à dire, les suggestions parlent d'elles-mêmes. Sinon : le
    // bouton « Analyser », ou la raison pour laquelle le son ne peut pas l'être.
    final showStatus =
        hasAnalysis && status != null && status != SoundAnalysisStatus.analyzed;
    final hasPending = autoTags.any((s) => !selectedTagIds.contains(s.tag.id));
    if (!hasPending && !showStatus) return editor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        editor,
        if (hasPending) ...[
          const SizedBox(height: 14),
          AutoTagChips(
            suggestions: autoTags,
            colors: _categoryColorsByTagId(),
            acceptedTagIds: selectedTagIds,
            // Accepter = ajouter aux tags du son, enregistré avec le formulaire.
            onAdd: (s) => onTagAdded(s.tag.id),
          ),
        ],
        if (showStatus) ...[
          const SizedBox(height: 10),
          AutoTagStatusRow(
            // Demandée, pas encore dans la file du passage : déjà « en attente ».
            status: analysisRequested && status == SoundAnalysisStatus.pending
                ? SoundAnalysisStatus.queued
                : status,
            onStart: onStartAnalysis,
          ),
        ],
      ],
    );
  }
}
