/// Choisit, parmi des candidats Drive partageant le même basename, celui qui
/// correspond le mieux à un chemin relatif devenu périmé (fichier déplacé ou
/// renommé directement sur Drive).
///
/// Purement fonctionnel — aucune dépendance au SDK Drive ni à la base : testable
/// isolément. Les chemins utilisent toujours `/` (portables) et sont comparés de
/// façon insensible à la casse ; la valeur retournée est le candidat d'origine.
class ReconcilePathMatcher {
  ReconcilePathMatcher._();

  /// Retourne le meilleur candidat, ou `null` si le choix reste ambigu.
  ///
  /// Principe : mieux vaut laisser un son sur son ancien chemin que le rattacher
  /// au mauvais fichier. On ne tranche donc que lorsqu'un candidat se détache
  /// **strictement** ; toute égalité au sommet renvoie `null`.
  ///
  /// Ordre de décision :
  /// 1. candidat unique ;
  /// 2. correspondance exacte du chemin complet (insensible à la casse) ;
  /// 3. plus grande similarité du dossier parent (segments communs en partant
  ///    du parent immédiat), à condition qu'elle soit strictement unique.
  static String? pickBestCandidate(
    String currentPath,
    List<String> candidates,
  ) {
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.single;

    final currentLower = currentPath.toLowerCase();

    // 2. Correspondance exacte du chemin complet.
    final exact = candidates
        .where((path) => path.toLowerCase() == currentLower)
        .toList();
    if (exact.length == 1) return exact.single;
    if (exact.length > 1) return null; // doublons stricts : indécidable

    // 3. Similarité du dossier parent : on privilégie le candidat qui partage le
    //    plus de segments de dossier avec le chemin périmé (suffixe commun, à
    //    partir du parent immédiat). Un maximum STRICTEMENT unique tranche.
    final currentParents = _parentSegments(currentLower);
    var bestScore = 0;
    String? best;
    var tiedAtBest = false;
    for (final candidate in candidates) {
      final score = _commonSuffixLength(
        currentParents,
        _parentSegments(candidate.toLowerCase()),
      );
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
        tiedAtBest = false;
      } else if (score == bestScore && score > 0) {
        tiedAtBest = true;
      }
    }
    if (best == null || tiedAtBest) return null;
    return best;
  }

  /// Segments du dossier parent (le chemin sans son basename).
  static List<String> _parentSegments(String path) {
    final segments = path.split('/');
    return segments.sublist(0, segments.length - 1);
  }

  /// Longueur du plus long suffixe commun entre deux listes de segments.
  static int _commonSuffixLength(List<String> a, List<String> b) {
    var i = a.length - 1;
    var j = b.length - 1;
    var shared = 0;
    while (i >= 0 && j >= 0 && a[i] == b[j]) {
      shared++;
      i--;
      j--;
    }
    return shared;
  }
}
