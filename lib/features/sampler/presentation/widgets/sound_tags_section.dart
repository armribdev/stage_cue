import 'package:flutter/material.dart';

import '../../../../core/autotag/auto_tag_status.dart';
import '../../../../core/utils/title_tag_matcher.dart';
import '../../domain/entities/sound_auto_tag.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import 'animated_pill_wrap.dart';
import 'auto_tag_chips.dart';
import 'auto_tag_status_row.dart';
import 'sound_edit_preload.dart';
import 'tag_chips_editor.dart';

/// Section « Tags » du formulaire d'un son : éditeur des tags de l'utilisateur,
/// suggestions de l'IA (décision 0031) et du titre (décision 0041), et état de
/// l'analyse. Ne garde que de quoi animer sa hauteur : tout le reste vient de
/// [SoundEditForm], qui reste seul à décider de ce qui est modifié.
class SoundTagsSection extends StatefulWidget {
  final List<TagCategoryWithTags> tagCatalog;
  final Set<int> selectedTagIds;
  final List<SoundAutoTag> autoTags;

  /// Tags que le titre du son désigne (décision 0041), pas encore posés.
  final List<TitleTagMatch> titleMatches;
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

  /// Hauteur de la section du formulaire précédent, et où inscrire la sienne :
  /// elle part de l'une et s'anime vers l'autre. `null` = pas de suite.
  final TagsSectionMemory? memory;

  const SoundTagsSection({
    super.key,
    required this.tagCatalog,
    required this.selectedTagIds,
    required this.autoTags,
    this.titleMatches = const [],
    required this.tagsLoaded,
    required this.tagsFailed,
    required this.hasAnalysis,
    required this.analysisStatus,
    required this.analysisRequested,
    required this.onTagAdded,
    required this.onTagRemoved,
    required this.onStartAnalysis,
    this.memory,
  });

  @override
  State<SoundTagsSection> createState() => _SoundTagsSectionState();
}

class _SoundTagsSectionState extends State<SoundTagsSection> {
  Map<int, Color> _categoryColorsByTagId() => {
    for (final cat in widget.tagCatalog)
      for (final tag in cat.tags) tag.id: Color(cat.category.color),
  };

  /// Tags déduits du titre, résolus dans le catalogue, sans ceux que l'IA
  /// propose déjà (sa pastille, avec son score, prime).
  List<TitleTagSuggestion> _titleSuggestions() {
    if (widget.titleMatches.isEmpty) return const [];
    final tagById = {
      for (final cat in widget.tagCatalog)
        for (final tag in cat.tags) tag.id: tag,
    };
    final proposedByAi = {for (final s in widget.autoTags) s.tag.id};
    return [
      for (final match in widget.titleMatches)
        if (!proposedByAi.contains(match.tagId))
          if (tagById[match.tagId] case final tag?)
            (tag: tag, word: match.matchedText),
    ];
  }

  /// Hauteur d'une rangée de pastilles (bouton « + Tag » : 2 × 7 de marge +
  /// ligne de 14 × 1,25, bordure comprise).
  static const _rowHeight = 32.0;

  /// Contenu mesuré (sa hauteur naturelle) et conservé d'un mode à l'autre.
  final _contentKey = GlobalKey();

  /// Première image : la section est tenue à la hauteur de celle du son
  /// précédent, puis relâchée pour que [AnimatedSize] la mène à la sienne.
  late double? _seedHeight = widget.memory?.value;

  /// Ce formulaire en suit un autre (il part de sa hauteur) : ses suggestions
  /// s'animent par rapport aux siennes au lieu d'apparaître d'un coup.
  late final bool _switching = _seedHeight != null;

  /// Le formulaire précédent avait des suggestions à l'écran : celles qui ne
  /// sont pas aussi celles de ce son se referment. Un son sans aucune suggestion
  /// n'en montre pas la fermeture : seule la hauteur se réduit (sinon ça
  /// saccade).
  late final bool _hadSuggestions =
      widget.memory?.suggestions.entries.isNotEmpty ?? false;

  @override
  void initState() {
    super.initState();
    // Fixés maintenant, avant que les pastilles de ce formulaire ne remplacent
    // celles du précédent en mémoire.
    final _ = (_switching, _hadSuggestions);
    if (_seedHeight != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _seedHeight = null);
      });
    }
  }

  /// Le formulaire est recréé à chaque changement de son, mais [SoundEditPane]
  /// lui fournit tout d'avance : la section est complète dès sa première
  /// image, sans « démarrer vide » avant de se remplir. Elle ne s'anime que
  /// pour passer de la hauteur du son précédent à la sienne (suggestions qui se
  /// referment ou s'ouvrent). Sans données d'avance (mobile), elle réserve une
  /// rangée vide le temps de la lecture : afficher l'éditeur tout de suite ferait
  /// arriver le bouton « + Tag » à gauche, puis le repousserait à droite quand
  /// les pastilles viennent se placer avant lui.
  @override
  Widget build(BuildContext context) {
    final seed = _seedHeight;
    // Pleine largeur : `AnimatedSize` anime aussi la largeur, et un contenu qui
    // colle à ses pastilles s'ouvrirait en balayage depuis la gauche. La clé
    // globale garde le contenu (et son état) au passage d'un mode à l'autre.
    final content = SizedBox(
      key: _contentKey,
      width: double.infinity,
      child: _content(context),
    );
    if (seed == null) {
      // Le contenu a la hauteur qu'il aura : c'est celle que le suivant imitera.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final box = _contentKey.currentContext?.findRenderObject();
        if (box is RenderBox && box.hasSize) {
          widget.memory?.value = box.size.height;
        }
      });
    }
    return AnimatedSize(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: seed == null
          ? content
          : SizedBox(
              height: seed,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: content,
                ),
              ),
            ),
    );
  }

  Widget _content(BuildContext context) {
    if (widget.tagsFailed) {
      return Text(
        'Tags indisponibles — réessayez en rouvrant le son.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    if (!widget.tagsLoaded) return const SizedBox(height: _rowHeight);
    final editor = TagChipsEditor(
      tagCatalog: widget.tagCatalog,
      selectedTagIds: widget.selectedTagIds,
      onTagAdded: widget.onTagAdded,
      onTagRemoved: widget.onTagRemoved,
    );
    final status = widget.analysisStatus;
    // Analysé : rien à dire, les suggestions parlent d'elles-mêmes ; pas une
    // musique : rien à proposer non plus. Sinon : le bouton « Analyser », ou la
    // raison pour laquelle le son ne peut pas l'être.
    final showStatus =
        widget.hasAnalysis &&
        status != null &&
        status != SoundAnalysisStatus.analyzed &&
        status != SoundAnalysisStatus.notMusic;
    final fromTitle = _titleSuggestions();
    final hasPending =
        widget.autoTags.any((s) => !widget.selectedTagIds.contains(s.tag.id)) ||
        fromTitle.any((s) => !widget.selectedTagIds.contains(s.tag.id));
    final hasAnySuggestion = widget.autoTags.isNotEmpty || fromTitle.isNotEmpty;
    // Toujours la même colonne, aux mêmes emplacements : l'éditeur (et les
    // pastilles qui s'animent) ne doit pas être recréé quand les suggestions ou
    // l'état d'analyse apparaissent ou disparaissent.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        editor,
        if (hasAnySuggestion)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Le libellé se referme avec la dernière suggestion.
              Reveal(
                visible: hasPending,
                appear: _switching && !_hadSuggestions,
                initiallyOpen: _hadSuggestions,
                child: Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 8),
                  child: Text(
                    'Suggestions',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              AutoTagChips(
                suggestions: widget.autoTags,
                titleSuggestions: fromTitle,
                colors: _categoryColorsByTagId(),
                acceptedTagIds: widget.selectedTagIds,
                // Accepter = ajouter aux tags du son, enregistré avec le
                // formulaire.
                onAdd: (tag) => widget.onTagAdded(tag.id),
                memory: widget.memory?.suggestions,
                animateInitial: _switching,
              ),
            ],
          )
        else
          const SizedBox.shrink(),
        if (showStatus)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: AutoTagStatusRow(
              // Demandée, pas encore dans la file du passage : déjà « en
              // attente ».
              status:
                  widget.analysisRequested &&
                      status == SoundAnalysisStatus.pending
                  ? SoundAnalysisStatus.queued
                  : status,
              onStart: widget.onStartAnalysis,
            ),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }
}
