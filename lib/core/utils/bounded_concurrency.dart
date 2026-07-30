import 'dart:math' as math;

/// Applique [task] à chaque élément de [items] avec au plus [concurrency]
/// exécutions simultanées, en préservant l'ordre des résultats.
///
/// Sert aux rafales d'appels Drive **idempotents** (listings, téléchargements),
/// où la latence domine et où le séquentiel laisse le réseau au repos. Ne pas
/// l'utiliser pour des appels non rejouables : la borne de concurrence n'a rien
/// à voir avec l'idempotence (cf. décision 0012).
///
/// **Complet ou rien** : la première erreur arrête l'alimentation des workers et
/// remonte. Les appels déjà en vol sont attendus avant la propagation, pour ne
/// laisser aucune requête orpheline derrière soi. Un appelant qui a besoin des
/// succès partiels doit capturer les erreurs dans [task] lui-même — mais qu'il
/// se demande d'abord si un résultat partiel a un sens pour lui : côté
/// synchronisation, un scan incomplet pris pour complet fait supprimer des
/// données (cf. décisions 0005 et 0019).
Future<List<R>> mapBounded<T, R>(
  List<T> items,
  Future<R> Function(T item) task, {
  required int concurrency,
}) async {
  assert(concurrency >= 1, 'concurrency doit être ≥ 1');
  if (items.isEmpty) return const [];

  final results = List<R?>.filled(items.length, null);
  var nextIndex = 0;
  var failed = false;

  Future<void> worker() async {
    while (!failed) {
      final index = nextIndex++;
      if (index >= items.length) return;
      try {
        results[index] = await task(items[index]);
      } catch (_) {
        failed = true;
        rethrow;
      }
    }
  }

  final workerCount = math.min(concurrency, items.length);
  await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
  return results.cast<R>();
}
