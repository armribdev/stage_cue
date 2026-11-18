import 'package:flutter/material.dart';

import '../../../../core/theme/app_dialog.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';
import '../utils/title_tag_proposals.dart';
import 'app_form_dialog.dart';
import 'tag_pill.dart';

/// Aperçu de l'action groupée « Tags des titres » (décision 0041) : chaque son
/// non traité avec les tags que son titre désigne. Rien n'est écrit tant que
/// l'utilisateur n'a pas confirmé, et il peut retirer n'importe quel tag d'un
/// toucher (la pastille fantôme le remet).
///
/// Renvoie les tags retenus par son (jamais vides), ou `null` si annulé.
class TitleTagsDialog extends StatefulWidget {
  final List<TitleTagProposal> proposals;
  final List<TagCategoryWithTags> tagCatalog;

  const TitleTagsDialog({
    super.key,
    required this.proposals,
    required this.tagCatalog,
  });

  static Future<Map<int, Set<int>>?> show(
    BuildContext context, {
    required List<TitleTagProposal> proposals,
    required List<TagCategoryWithTags> tagCatalog,
  }) {
    return showAppDialog<Map<int, Set<int>>>(
      context: context,
      builder: (_) =>
          TitleTagsDialog(proposals: proposals, tagCatalog: tagCatalog),
    );
  }

  @override
  State<TitleTagsDialog> createState() => _TitleTagsDialogState();
}

class _TitleTagsDialogState extends State<TitleTagsDialog> {
  late final Map<int, TagItem> _tagById;
  late final Map<int, Color> _colors;

  /// Tags retenus par id de son : tout au départ, l'utilisateur retire.
  late final Map<int, Set<int>> _selected;

  @override
  void initState() {
    super.initState();
    _tagById = {
      for (final cat in widget.tagCatalog)
        for (final tag in cat.tags) tag.id: tag,
    };
    _colors = {
      for (final cat in widget.tagCatalog)
        for (final tag in cat.tags) tag.id: Color(cat.category.color),
    };
    _selected = {
      for (final p in widget.proposals)
        p.sound.id: {
          for (final m in p.matches)
            if (_tagById.containsKey(m.tagId)) m.tagId,
        },
    };
  }

  int get _count => _selected.values.fold(0, (sum, tags) => sum + tags.length);

  int get _soundCount => _selected.values.where((t) => t.isNotEmpty).length;

  void _toggle(int soundId, int tagId) {
    setState(() {
      final tags = _selected[soundId];
      if (tags == null) return;
      if (!tags.remove(tagId)) tags.add(tagId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = MediaQuery.sizeOf(context).height * 0.55;
    final proposals = widget.proposals;
    return AppFormDialog(
      title: 'Tags déduits des titres',
      onClose: () => Navigator.of(context).pop(),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${proposals.length} sons non traités ont un titre qui désigne un '
            'tag. Retirez ceux qui ne conviennent pas : seuls les tags '
            'conservés seront ajoutés, et les sons resteront à traiter.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: height,
            child: ListView.separated(
              itemCount: proposals.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _buildRow(proposals[index], scheme),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(minimumSize: const Size(64, 42)),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _count == 0
              ? null
              : () => Navigator.of(context).pop({
                  for (final entry in _selected.entries)
                    if (entry.value.isNotEmpty) entry.key: {...entry.value},
                }),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 42)),
          child: Text(
            _count == 0
                ? 'Aucun tag'
                : 'Ajouter $_count tag${_count > 1 ? 's' : ''} '
                      'à $_soundCount son${_soundCount > 1 ? 's' : ''}',
          ),
        ),
      ],
    );
  }

  Widget _buildRow(TitleTagProposal proposal, ColorScheme scheme) {
    final soundId = proposal.sound.id;
    final chosen = _selected[soundId] ?? const <int>{};
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            proposal.sound.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final match in proposal.matches)
                if (_tagById[match.tagId] case final tag?)
                  Tooltip(
                    message: 'Trouvé dans le titre : « ${match.matchedText} »',
                    child: chosen.contains(tag.id)
                        ? TagPill(
                            key: ValueKey('title-tags-$soundId-${tag.id}'),
                            label: tag.name,
                            color: _colors[tag.id],
                            onRemove: () => _toggle(soundId, tag.id),
                            removeTooltip: 'Ne pas ajouter',
                          )
                        : TagPill(
                            key: ValueKey('title-tags-$soundId-${tag.id}'),
                            label: tag.name,
                            color: _colors[tag.id],
                            suggestion: true,
                            onTap: () => _toggle(soundId, tag.id),
                          ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}
