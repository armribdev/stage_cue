import 'dart:math' show min;

import 'string_utils.dart';

/// Un tag du catalogue et les expressions qui le désignent : son nom et ses
/// alias, tels que stockés (la normalisation est faite par [TitleTagMatcher]).
class TagVocabularyEntry {
  final int tagId;
  final List<String> phrases;

  const TagVocabularyEntry({required this.tagId, required this.phrases});
}

/// Un tag trouvé dans un titre, avec les mots du titre qui l'ont désigné
/// (tels qu'écrits, pour l'afficher à l'utilisateur et qu'il juge).
class TitleTagMatch {
  final int tagId;
  final String matchedText;

  const TitleTagMatch({required this.tagId, required this.matchedText});
}

/// Nombre maximal de tags déduits d'un même titre : au-delà, la rangée de
/// suggestions noie les tags qui comptent (la moyenne mesurée est de 1,7 par
/// son couvert).
const int kMaxTitleTagSuggestions = 4;

/// Expressions qui restent des alias pour la **recherche** (où l'utilisateur
/// tape le mot exprès) mais qui ne déduisent rien d'un titre, trop souvent
/// employées dans un autre sens : « pas » (négation, alias de Marcher),
/// « theme » (titre d'un thème musical, alias de BO), « mix » (Remix) et
/// « hit » (Célèbre).
const Set<String> kAmbiguousTitlePhrases = {'pas', 'theme', 'mix', 'hit'};

/// Déduit des tags du titre d'un son (décision 0041). Dart pur, sans E/S : le
/// vocabulaire (noms de tags et alias) est fourni à la construction.
///
/// Règles d'appariement :
/// - **mots entiers** : « bar » ne se trouve pas dans « Barbara » ;
/// - mêmes normalisations que la recherche ([normalizeForSearch]) : accents et
///   casse ignorés, tout ce qui n'est ni lettre ni chiffre sépare les mots
///   (`-`, `_`, apostrophe, parenthèses…) ;
/// - pluriel simple : un « s » final est ignoré des deux côtés (« rires » ↔
///   « rire ») ;
/// - expression multi-mots (« bande originale ») prioritaire sur ses mots
///   isolés, et chaque mot du titre ne sert qu'une fois.
class TitleTagMatcher {
  final Map<String, List<int>> _tagIdsByPhrase = {};
  int _maxWords = 1;

  TitleTagMatcher(
    Iterable<TagVocabularyEntry> vocabulary, {
    Set<String> ambiguousPhrases = kAmbiguousTitlePhrases,
  }) {
    final ignored = {
      for (final phrase in ambiguousPhrases) _key(_words(phrase)),
    };
    for (final entry in vocabulary) {
      for (final phrase in entry.phrases) {
        final words = _words(phrase);
        final key = _key(words);
        if (key.isEmpty || ignored.contains(key)) continue;
        final tagIds = _tagIdsByPhrase.putIfAbsent(key, () => []);
        if (!tagIds.contains(entry.tagId)) tagIds.add(entry.tagId);
        if (words.length > _maxWords) _maxWords = words.length;
      }
    }
  }

  /// Tags désignés par [title], dans l'ordre d'apparition, sans doublon, hors
  /// [excluded] (tags déjà posés). Au plus [limit].
  List<TitleTagMatch> suggest(
    String title, {
    Set<int> excluded = const {},
    int limit = kMaxTitleTagSuggestions,
  }) {
    final words = _words(title);
    final found = <int, String>{};
    var i = 0;
    while (i < words.length) {
      var consumed = 1;
      for (var n = min(_maxWords, words.length - i); n >= 1; n--) {
        final tagIds = _tagIdsByPhrase[_key(words.sublist(i, i + n))];
        if (tagIds == null) continue;
        final text = title.substring(words[i].start, words[i + n - 1].end);
        for (final id in tagIds) {
          if (!excluded.contains(id)) found.putIfAbsent(id, () => text);
        }
        consumed = n;
        break;
      }
      i += consumed;
    }
    return [
      for (final entry in found.entries.take(limit))
        TitleTagMatch(tagId: entry.key, matchedText: entry.value),
    ];
  }

  static final RegExp _wordPattern = RegExp(r'[\p{L}\p{N}]+', unicode: true);

  static List<_Word> _words(String text) => [
    for (final match in _wordPattern.allMatches(text))
      _Word(_stem(normalizeForSearch(match[0]!)), match.start, match.end),
  ];

  static String _key(List<_Word> words) => words.map((w) => w.stem).join(' ');

  /// Pluriel simple : « rires » → « rire », mais ni « bus » (3 lettres) ni
  /// « glass » (déjà en « ss »).
  static String _stem(String word) =>
      word.length > 3 && word.endsWith('s') && !word.endsWith('ss')
      ? word.substring(0, word.length - 1)
      : word;
}

class _Word {
  final String stem;
  final int start;
  final int end;

  const _Word(this.stem, this.start, this.end);
}
