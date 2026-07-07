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

  final seqScore = _subsequenceScore(normalizedText, normalizedQuery);
  if (seqScore != null) return seqScore;

  // La sous-séquence stricte échoue notamment sur les lettres interverties
  // (ex : "epxlosion" vs "explosion") car l'ordre des caractères n'est plus
  // respecté. On tente alors une correspondance approximative tolérant
  // fautes de frappe (substitution, insertion, suppression, transposition).
  final maxTypo = _maxTypoDistance(normalizedQuery.length);
  if (maxTypo == 0) return null;
  final approx = _approximateMatch(normalizedText, normalizedQuery, maxTypo);
  if (approx == null) return null;
  return 260 - approx.distance * 60; // sous les sous-chaînes, au-dessus des sous-séquences
}

/// Distance d'édition maximale tolérée pour une faute de frappe, selon la
/// longueur du mot recherché. Les mots courts (≤ 3 lettres) sont exclus pour
/// éviter les faux positifs (trop de mots courts se ressemblent).
int _maxTypoDistance(int queryLength) {
  if (queryLength <= 3) return 0;
  if (queryLength <= 6) return 1;
  return 2;
}

/// Cherche la fenêtre de [text] la plus proche de [query] au sens de la
/// distance de Damerau-Levenshtein restreinte (substitution, insertion,
/// suppression, transposition de deux lettres adjacentes). Retourne la
/// distance minimale trouvée et les bornes `[start, end)` de cette fenêtre
/// dans [text], ou `null` si aucune fenêtre ne respecte [maxDistance].
({int distance, int start, int end})? _approximateMatch(
  String text,
  String query,
  int maxDistance,
) {
  final m = query.length;
  final n = text.length;
  if (m == 0 || n == 0) return null;

  // d[i][j] : coût minimal pour transformer query[0..i) en une fenêtre de
  // text se terminant en j. d[0][j] = 0 pour tout j : l'alignement peut
  // démarrer n'importe où dans le texte, sans coût.
  final d = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
  // parent[i][j] : 0 = diagonale (match/substitution), 1 = haut (lettre de
  // la requête supprimée), 2 = gauche (lettre du texte insérée), 3 = transposition.
  final parent = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));

  for (var i = 1; i <= m; i++) {
    d[i][0] = i;
    parent[i][0] = 1;
  }

  for (var i = 1; i <= m; i++) {
    for (var j = 1; j <= n; j++) {
      final cost = query[i - 1] == text[j - 1] ? 0 : 1;
      var best = d[i - 1][j - 1] + cost;
      var move = 0;
      if (d[i - 1][j] + 1 < best) {
        best = d[i - 1][j] + 1;
        move = 1;
      }
      if (d[i][j - 1] + 1 < best) {
        best = d[i][j - 1] + 1;
        move = 2;
      }
      if (i > 1 &&
          j > 1 &&
          query[i - 1] == text[j - 2] &&
          query[i - 2] == text[j - 1] &&
          d[i - 2][j - 2] + 1 < best) {
        best = d[i - 2][j - 2] + 1;
        move = 3;
      }
      d[i][j] = best;
      parent[i][j] = move;
    }
  }

  var bestEnd = -1;
  var bestDistance = maxDistance + 1;
  for (var j = 0; j <= n; j++) {
    if (d[m][j] < bestDistance) {
      bestDistance = d[m][j];
      bestEnd = j;
    }
  }
  if (bestEnd == -1 || bestDistance > maxDistance) return null;

  var i = m, j = bestEnd;
  while (i > 0) {
    switch (parent[i][j]) {
      case 1:
        i -= 1;
      case 2:
        j -= 1;
      case 3:
        i -= 2;
        j -= 2;
      default:
        i -= 1;
        j -= 1;
    }
  }
  return (distance: bestDistance, start: j, end: bestEnd);
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
    var found = false;
    while (true) {
      final idx = normalizedText.indexOf(token, i);
      if (idx == -1) break;
      found = true;
      ranges.add((idx, idx + token.length));
      i = idx + 1;
    }
    if (found) continue;

    // Pas d'occurrence exacte : le token a peut-être matché via une
    // correspondance approximative (faute de frappe). On met alors en
    // évidence la fenêtre de texte la plus proche, pour que l'utilisateur
    // voie où est le match malgré l'erreur.
    final maxTypo = _maxTypoDistance(token.length);
    if (maxTypo == 0) continue;
    final approx = _approximateMatch(normalizedText, token, maxTypo);
    if (approx != null) {
      ranges.add((approx.start, approx.end));
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
