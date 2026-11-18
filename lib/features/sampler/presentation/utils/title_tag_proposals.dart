import '../../../../core/utils/title_tag_matcher.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/tag_item.dart';

/// Tags que le titre d'un son désigne, hors [excluded] (tags déjà posés).
///
/// Cherche dans le nom affiché **et** dans le titre du fichier quand ils
/// diffèrent : l'utilisateur a pu renommer le son sans que le fichier change,
/// et l'un comme l'autre porte le mot qui décide du tag. Chaque texte est
/// apparié séparément pour qu'aucune expression ne se forme à cheval dessus.
List<TitleTagMatch> titleTagMatchesFor(
  Sound sound,
  TitleTagMatcher matcher, {
  Set<int> excluded = const {},
}) {
  final texts = {sound.displayName, sound.title};
  final found = <int, TitleTagMatch>{};
  for (final text in texts) {
    for (final match in matcher.suggest(
      text,
      excluded: excluded,
      limit: kMaxTitleTagSuggestions,
    )) {
      found.putIfAbsent(match.tagId, () => match);
    }
  }
  return found.values.take(kMaxTitleTagSuggestions).toList();
}

/// Un son et les tags que son titre propose de lui ajouter.
typedef TitleTagProposal = ({Sound sound, List<TitleTagMatch> matches});

/// Propositions pour toute une liste de sons, pour l'action groupée.
///
/// Ne retient que les sons **non traités** (un son traité est figé, décisions
/// 0029 et 0041) et ceux qui ont au moins une proposition. [tagsBySound] vient
/// de l'index de recherche : aucune requête par son (décision 0017).
List<TitleTagProposal> proposeTitleTags({
  required Iterable<Sound> sounds,
  required Map<int, List<TagItem>> tagsBySound,
  required TitleTagMatcher matcher,
}) {
  final proposals = <TitleTagProposal>[];
  for (final sound in sounds) {
    if (sound.isProcessed) continue;
    final posed = {
      for (final tag in tagsBySound[sound.id] ?? const <TagItem>[]) tag.id,
    };
    final matches = titleTagMatchesFor(sound, matcher, excluded: posed);
    if (matches.isNotEmpty) proposals.add((sound: sound, matches: matches));
  }
  return proposals;
}
