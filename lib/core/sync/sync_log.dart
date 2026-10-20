import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../logging/log_sink.dart';

/// Journalisation de l'indexation, du cache et de la synchronisation Drive, via
/// DevTools et la Debug Console (`developer.log`).
///
/// Pendant de [AudioLoadLog] pour le sous-système distant. Canal distinct
/// (`StageCue.Sync`) : les deux sous-systèmes s'investiguent séparément, et
/// mélanger le bruit de lecture audio avec celui de la synchro rend les deux
/// illisibles.
///
/// Deux principes tirés de l'audit de journalisation :
///
/// - **Un point de décision ne doit jamais être muet.** Tout ce qui écarte une
///   bibliothèque, retombe sur un mode dégradé ou renonce à une opération se
///   journalise — sinon un lancement qui ne fait rien est indiscernable d'un
///   lancement qui a échoué.
/// - **Un `catch` best-effort reste non bloquant, mais pas silencieux.** Ne pas
///   propager une erreur est un choix légitime ; ne pas la dire n'en est pas un.
class SyncLog {
  SyncLog._();

  static const _name = 'StageCue.Sync';
  static const _channel = 'Sync';

  /// Traces à **haute fréquence** (une ligne par dossier, par lot, par fichier).
  /// Muettes par défaut : sur une bibliothèque de milliers de sons, elles
  /// noieraient la console. Activer pour investiguer :
  /// `--dart-define=STAGE_CUE_SYNC_TRACE=true`.
  static const bool traceEnabled = bool.fromEnvironment('STAGE_CUE_SYNC_TRACE');

  static void trace(String message) {
    if (!traceEnabled) return;
    debugPrint('[sync] $message');
    LogSink.log(_channel, LogLevel.trace, message);
  }

  static void info(String message) => _emit(message, sinkLevel: LogLevel.info);

  /// Un avertissement porte TOUT dans son message — pas d'objet d'erreur.
  ///
  /// `developer.log` imprime le message ET l'erreur qu'on lui passe : accepter
  /// les deux, c'est garantir qu'un appelant finira par interpoler `$e` dans son
  /// message tout en le passant aussi ici, et doubler le volume de la console
  /// pile au moment où elle sert — pendant une rafale d'échecs. Le seul endroit
  /// qui justifie l'objet est [severe], où la stack trace doit lui être
  /// attachée.
  static void warn(String message) =>
      _emit(message, level: 900, sinkLevel: LogLevel.warn);

  static void severe(String message, {Object? error, StackTrace? stackTrace}) =>
      _emit(
        message,
        level: 1000,
        sinkLevel: LogLevel.severe,
        error: error,
        stackTrace: stackTrace,
      );

  // ── Choix du chemin de synchronisation ─────────────────────────────────────

  /// Delta appliqué : le chemin rapide a suffi.
  static void deltaApplied({
    required String library,
    required int upserted,
    required int removed,
  }) {
    info(
      '$library : delta appliqué '
      '($upserted ajout(s)/modif(s), $removed retrait(s)).',
    );
  }

  /// Repli sur le scan complet. [reason] vient de `DriveSyncNeedsFullScan` :
  /// c'est la seule façon de savoir si le chemin incrémental sert réellement ou
  /// si l'app rescanne à chaque lancement.
  static void fullScanRequired({
    required String library,
    required String reason,
  }) {
    info('$library : scan complet — $reason.');
  }

  /// Bibliothèque écartée du pull pour toute la session (index incomplet).
  ///
  /// Conséquence lourde et jusqu'ici totalement muette : sans cette ligne, un
  /// lancement qui ne fusionne rien ne dit pas s'il s'agit d'un timeout, d'un
  /// quota Drive ou d'un dossier injoignable.
  static void librarySkipped({required String library, required Object error}) {
    warn('$library : écartée du pull cette session (index incomplet) — $error');
  }

  /// La veille a rencontré un delta inexploitable et refuse de rescanner.
  ///
  /// Journalisé **une fois par bibliothèque** : la raison ne change pas d'un
  /// tick à l'autre, et la répéter toutes les quelques minutes rendrait le canal
  /// inutilisable — mais renoncer en silence laisserait croire que la veille
  /// tourne alors qu'elle ne rattrape plus rien.
  static void watchFullScanDeferred({
    required String library,
    required String reason,
  }) {
    info(
      '$library : veille — scan complet requis ($reason), différé au prochain '
      'lancement ou à une actualisation manuelle.',
    );
  }

  /// Échec inattendu d'une passe de synchronisation : l'app bascule hors-ligne.
  ///
  /// [trigger] distingue le lancement, le bouton « Actualiser » et la veille :
  /// une passe de veille qui échoue en boucle ne se diagnostique pas comme un
  /// lancement raté.
  static void syncPassFailed({
    required String trigger,
    required Object error,
    required StackTrace stackTrace,
  }) {
    // Seul cas où l'on passe l'objet d'erreur : la stack trace n'a de sens
    // qu'attachée à lui, et un incident unique ne risque pas de noyer la
    // console.
    severe(
      'Passe de synchronisation ($trigger) interrompue — bascule hors-ligne.',
      error: error,
      stackTrace: stackTrace,
    );
  }

  // ── Indexation ─────────────────────────────────────────────────────────────

  static void indexFinished({
    required String library,
    required int folderCount,
    required int fileCount,
    required int createdCount,
    required int prunedCount,
  }) {
    info(
      '$library : indexé — $fileCount fichier(s) dans $folderCount dossier(s), '
      '$createdCount nouveau(x), $prunedCount élagué(s).',
    );
  }

  /// Jeton de reprise indisponible : le prochain lancement restera en scan
  /// complet. Non bloquant, mais c'est une perte d'optimisation à savoir.
  static void startTokenUnavailable({
    required String library,
    required Object error,
  }) {
    warn(
      '$library : jeton de reprise Drive indisponible, le prochain lancement '
      'rescannera intégralement — $error',
    );
  }

  // ── Pull ───────────────────────────────────────────────────────────────────

  /// Bilan d'une passe de pull groupée. [skippedByProbe] mesure directement
  /// l'efficacité du jeton de sonde du manifest : s'il reste à zéro, la sonde ne
  /// sert pas et le pull retélécharge tous les manifests à chaque lancement.
  static void pullFinished({
    required String library,
    required int probed,
    required int skippedByProbe,
    required int merged,
    required int noRemote,
  }) {
    info(
      '$library : pull — $probed nœud(s) sondé(s), '
      '$skippedByProbe sauté(s) par jeton, $merged fusionné(s), '
      '$noRemote sans snapshot distant.',
    );
  }

  // ── Authentification Drive ─────────────────────────────────────────────────
  //
  // Aucune de ces lignes ne porte de jeton ni d'adresse e-mail : on journalise
  // l'ÉVÉNEMENT (connexion, déconnexion, échec), jamais l'identité.

  static void driveSignedIn() => info('Drive : connexion réussie.');

  static void driveSignInCancelled() =>
      info('Drive : connexion annulée (aucune session obtenue).');

  static void driveSignInFailed(Object error) =>
      warn('Drive : connexion échouée — $error');

  /// Résultat de la reconnexion silencieuse au lancement / à la veille.
  ///
  /// Le cas nominal rejoué (la veille le refait toutes les 5 minutes) passe en
  /// `trace`.
  ///
  /// Plusieurs écrans déclenchent une reconnexion silencieuse (réglages,
  /// téléchargements) : on ne journalise que le **changement** d'issue, pas
  /// chaque appel — sinon la même ligne se répète à chaque ouverture d'écran.
  static bool? _lastSilentRestored;

  static void driveSilentReconnect({required bool restored}) {
    final changed = _lastSilentRestored != restored;
    _lastSilentRestored = restored;
    if (!changed) {
      trace('Drive : reconnexion silencieuse (restaurée=$restored).');
    } else if (restored) {
      info('Drive : session restaurée silencieusement.');
    } else {
      info(
        'Drive : aucune session à restaurer (reconnexion interactive '
        'nécessaire ou hors-ligne).',
      );
    }
  }

  static void driveSilentReconnectFailed(Object error) =>
      warn('Drive : reconnexion silencieuse échouée — $error');

  static void driveSignedOut() => info('Drive : déconnexion.');

  static DateTime? _lastAuthRejectedAt;

  /// Drive a rejeté le jeton (401 / accès refusé). Une rafale d'appels
  /// parallèles échoue d'un seul bloc : une ligne par minute suffit.
  static void driveAuthRejected() {
    final now = DateTime.now();
    final last = _lastAuthRejectedAt;
    if (last != null && now.difference(last) < const Duration(minutes: 1)) {
      return;
    }
    _lastAuthRejectedAt = now;
    warn(
      'Drive : jeton rejeté par l\'API (401) — renouvellement de la session '
      'nécessaire.',
    );
  }

  // ── Cache & téléchargements ────────────────────────────────────────────────

  static void downloadFailed({required String title, required Object error}) {
    warn('Téléchargement échoué — « $title » : $error');
  }

  /// Bilan d'une passe d'éviction (une ligne par passe, jamais par fichier).
  ///
  /// `warn` quand le garde-fou disque ([minFreeBytes], ADR 0016) n'est pas
  /// atteint à l'issue de la passe — tout ce qui restait était épinglé,
  /// protégé ou non supprimable : le disque reste sous pression et la prochaine
  /// écriture risque d'échouer. [freeAfter] est une estimation (libre mesuré +
  /// octets libérés), sans second appel système.
  static void evictionPass({
    required String library,
    required int evicted,
    required int freedBytes,
    required int failed,
    required int pinnedProtected,
    required int freeBefore,
    required int freeAfter,
    required int minFreeBytes,
  }) {
    final message =
        '$library : éviction du cache — $evicted fichier(s) '
        'évincé(s), ${_mb(freedBytes)} libérés, libre ${_mb(freeBefore)} → '
        '≈${_mb(freeAfter)}, $pinnedProtected épinglé(s) protégé(s)'
        '${failed > 0 ? ', $failed suppression(s) échouée(s)' : ''}.';
    if (freeAfter < minFreeBytes) {
      warn(
        '$message Garde-fou disque (${_mb(minFreeBytes)}) non atteint : plus '
        'rien d\'évinçable.',
      );
    } else {
      info(message);
    }
  }

  static String _mb(int bytes) => '${(bytes / (1024 * 1024)).round()} Mo';

  /// Bilan de la file de téléchargement à sa vidange, en plus de
  /// [downloadFailed] (qui dit *lequel* a échoué).
  static void downloadQueueDrained({
    required int succeeded,
    required int failed,
    required int cancelled,
    required Duration elapsed,
  }) {
    final message =
        'File de téléchargement vidée : $succeeded réussi(s), '
        '$failed échec(s), $cancelled annulé(s), '
        '${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s.';
    if (failed > 0) {
      warn(message);
    } else {
      info(message);
    }
  }

  static void evictionFailed({required String path, required Object error}) {
    warn('Éviction du cache impossible — $path : $error');
  }

  /// Ménage best-effort qui a échoué (blob résiduel, fichier temporaire).
  /// N'empêche rien de fonctionner, mais explique un `.stagecue` qui grossit.
  static void cleanupFailed({required String what, required Object error}) {
    warn('Ménage incomplet — $what : $error');
  }

  static void _emit(
    String message, {
    int level = 800,
    required LogLevel sinkLevel,
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: _name,
      level: level,
      error: error,
      stackTrace: stackTrace,
    );
    LogSink.log(
      _channel,
      sinkLevel,
      message,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
