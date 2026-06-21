import 'package:flutter/widgets.dart';

String normalizeForSearch(String value) {
  final lower = value.trim().toLowerCase();
  const replacements = {
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'á': 'a',
    'ç': 'c',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'ì': 'i',
    'í': 'i',
    'ô': 'o',
    'ö': 'o',
    'ò': 'o',
    'ó': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ú': 'u',
    'ÿ': 'y',
    'œ': 'oe',
    'æ': 'ae',
  };
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(replacements[char] ?? char);
  }
  return buffer.toString();
}

/// Score de correspondance floue entre un texte et une requête, tous deux déjà
/// normalisés via [normalizeForSearch]. Retourne `null` si la requête n'est pas
/// une sous-séquence du texte (pas de correspondance). Plus le score est élevé,
/// meilleure la pertinence : préfixe > début de mot > sous-chaîne > sous-séquence
/// dispersée. Utilisé par la recherche-éclair pour classer les sons.
int? fuzzyMatchScore(String normalizedText, String normalizedQuery) {
  if (normalizedQuery.isEmpty) return 0;
  final idx = normalizedText.indexOf(normalizedQuery);
  if (idx == 0) return 1000; // préfixe exact
  if (idx > 0) {
    final wordStart = normalizedText[idx - 1] == ' ';
    return (wordStart ? 800 : 500) - idx; // début de mot > sous-chaîne
  }
  return _subsequenceScore(normalizedText, normalizedQuery);
}

/// Construit un [TextSpan] avec les portions de [text] correspondant aux
/// [normalizedTokens] mises en gras. Les tokens doivent être déjà normalisés
/// via [normalizeForSearch]. Gère les expansions œ→oe et æ→ae.
TextSpan buildHighlightedSpan(String text, List<String> normalizedTokens) {
  if (normalizedTokens.isEmpty) return TextSpan(text: text);

  final normalizedText = normalizeForSearch(text);

  // Map : index dans le texte normalisé → index dans le texte original.
  // Nécessaire car œ→oe et æ→ae expandent 1 char original en 2 chars normalisés.
  final normToOrig = <int>[];
  for (var i = 0; i < text.length; i++) {
    final lower = text[i].toLowerCase();
    if (lower == 'œ' || lower == 'æ') {
      normToOrig..add(i)..add(i);
    } else {
      normToOrig.add(i);
    }
  }
  normToOrig.add(text.length); // sentinelle : position après le dernier char

  final ranges = <(int, int)>[];
  for (final token in normalizedTokens) {
    if (token.isEmpty) continue;
    var i = 0;
    while (true) {
      final idx = normalizedText.indexOf(token, i);
      if (idx == -1) break;
      ranges.add((idx, idx + token.length));
      i = idx + 1;
    }
  }

  if (ranges.isEmpty) return TextSpan(text: text);

  ranges.sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(int, int)>[];
  for (final r in ranges) {
    if (merged.isEmpty || r.$1 >= merged.last.$2) {
      merged.add(r);
    } else {
      final last = merged.removeLast();
      merged.add((last.$1, r.$2 > last.$2 ? r.$2 : last.$2));
    }
  }

  final spans = <InlineSpan>[];
  var pos = 0;
  const boldStyle = TextStyle(fontWeight: FontWeight.bold);
  for (final (normStart, normEnd) in merged) {
    final origStart = normToOrig[normStart];
    final origEnd = normToOrig[normEnd];
    if (origStart > pos) {
      spans.add(TextSpan(text: text.substring(pos, origStart)));
    }
    if (origEnd > origStart) {
      spans.add(TextSpan(text: text.substring(origStart, origEnd), style: boldStyle));
    }
    pos = origEnd;
  }
  if (pos < text.length) {
    spans.add(TextSpan(text: text.substring(pos)));
  }

  return TextSpan(children: spans);
}

int? _subsequenceScore(String s, String q) {
  var si = 0, qi = 0, score = 0, streak = 0;
  while (si < s.length && qi < q.length) {
    if (s[si] == q[qi]) {
      qi++;
      streak++;
      score += streak; // récompense les caractères consécutifs
    } else {
      streak = 0;
    }
    si++;
  }
  return qi == q.length ? score : null;
}
