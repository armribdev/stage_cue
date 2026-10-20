import 'dart:io';

import 'package:path/path.dart' as p;

/// Marqueur d'arrêt propre : `session.lock` est posé au démarrage et supprimé
/// à la fermeture. S'il existe déjà au démarrage suivant, la session précédente
/// ne s'est pas terminée normalement (crash, kill, coupure de courant).
///
/// Ne détecte rien que si la fermeture déclenche réellement
/// [markCleanExit] — voir ADR 0025 pour ce qui a été vérifié sous Windows.
class LogSession {
  LogSession._();

  static const lockFileName = 'session.lock';

  static File? _lock;

  /// Pose le marqueur et retourne `true` si la session précédente n'a pas eu
  /// de fin propre. Ne lève jamais.
  static Future<bool> markStarted(Directory directory, {DateTime? now}) async {
    try {
      final lock = File(p.join(directory.path, lockFileName));
      _lock = lock;
      final previousUnclean = await lock.exists();
      await lock.writeAsString((now ?? DateTime.now()).toIso8601String());
      return previousUnclean;
    } catch (_) {
      return false;
    }
  }

  /// Supprime le marqueur. Synchrone : à la fermeture, rien ne garantit qu'un
  /// `await` aura le temps de se terminer.
  static void markCleanExit() {
    try {
      _lock?.deleteSync();
    } catch (_) {}
  }
}

/// Construit les lignes de l'en-tête de session. Pure — les valeurs viennent de
/// l'appelant, ce qui la rend testable sans plugin.
List<String> buildSessionHeader({
  required DateTime startedAt,
  required String appVersion,
  required String buildNumber,
  required String operatingSystem,
  required String operatingSystemVersion,
  required String locale,
  required int schemaVersion,
  required bool cueConfigured,
  required int? freeDiskBytes,
  required bool previousSessionUnclean,
}) {
  return [
    '=== Stage Cue — démarrage ${startedAt.toIso8601String()} ===',
    'Version : $appVersion (build $buildNumber)',
    'Système : $operatingSystemVersion',
    'Plateforme : $operatingSystem',
    'Schéma base : v$schemaVersion',
    'Locale : $locale',
    'Device cue configuré : ${cueConfigured ? 'oui' : 'non'}',
    'Espace disque libre (volume du cache) : ${formatBytes(freeDiskBytes)}',
    if (previousSessionUnclean) 'Session précédente sans arrêt propre.',
  ];
}

String formatBytes(int? bytes) {
  if (bytes == null) return 'inconnu';
  const units = ['o', 'Ko', 'Mo', 'Go', 'To'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0 ? '$bytes o' : '${value.toStringAsFixed(1)} ${units[unit]}';
}
