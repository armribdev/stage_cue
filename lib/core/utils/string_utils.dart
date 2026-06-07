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
