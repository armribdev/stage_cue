import 'package:flutter/material.dart';

import '../../../../core/autotag/auto_tag_status.dart';
import '../../../../core/autotag/mood_tagging.dart';
import '../../../../core/theme/app_icons.dart';

/// Où en est l'analyse IA d'un son (décisions 0029 à 0031) : analysé, pas
/// analysé, en cours… et, tant qu'elle n'a pas commencé, le bouton qui la lance.
class AutoTagStatusRow extends StatelessWidget {
  final SoundAnalysisStatus status;

  /// Lance l'analyse de ce son ; ignoré hors [SoundAnalysisStatus.pending].
  final VoidCallback onStart;

  const AutoTagStatusRow({
    super.key,
    required this.status,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final busy =
        status == SoundAnalysisStatus.queued ||
        status == SoundAnalysisStatus.analyzing;
    return Row(
      children: [
        if (busy)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(
            AppIcons.sparkles,
            size: 14,
            color: status == SoundAnalysisStatus.analyzed
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Analyse IA : ${label(status)}',
            key: const ValueKey('auto-tag-status'),
            style: muted,
          ),
        ),
        if (status == SoundAnalysisStatus.pending)
          TextButton(
            key: const ValueKey('auto-tag-start'),
            style: TextButton.styleFrom(
              minimumSize: const Size(64, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: onStart,
            child: const Text('Analyser'),
          ),
      ],
    );
  }

  static String label(SoundAnalysisStatus status) => switch (status) {
    SoundAnalysisStatus.notMusic => 'réservée aux musiques.',
    SoundAnalysisStatus.processed =>
      'son déjà traité, plus analysé (ses suggestions sont figées).',
    SoundAnalysisStatus.pending => 'pas encore analysé.',
    SoundAnalysisStatus.packMissing =>
      'pas encore analysé — installez le pack de modèles '
          '(Paramètres → Analyse automatique).',
    SoundAnalysisStatus.queued => 'en attente…',
    SoundAnalysisStatus.analyzing => 'en cours…',
    SoundAnalysisStatus.awaitingSuggestions =>
      'analysé — suggestions en attente : il faut au moins '
          '${MoodTagRule.minLibrarySize} musiques analysées dans la '
          'bibliothèque.',
    SoundAnalysisStatus.analyzed => 'analysé.',
    SoundAnalysisStatus.skipped =>
      'impossible à analyser (format, durée ou silence).',
  };
}
