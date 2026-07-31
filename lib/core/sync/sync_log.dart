import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

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

  /// Traces à **haute fréquence** (une ligne par dossier, par lot, par fichier).
  /// Muettes par défaut : sur une bibliothèque de milliers de sons, elles
  /// noieraient la console. Activer pour investiguer :
  /// `--dart-define=STAGE_CUE_SYNC_TRACE=true`.
  static const bool traceEnabled =
      bool.fromEnvironment('STAGE_CUE_SYNC_TRACE');

  static void trace(String message) {
    if (traceEnabled) debugPrint('[sync] $message');
  }

  static void info(String message) => _emit(message);

  /// Un avertissement porte TOUT dans son message — pas d'objet d'erreur.
  ///
  /// `developer.log` imprime le message ET l'erreur qu'on lui passe : accepter
  /// les deux, c'est garantir qu'un appelant finira par interpoler `$e` dans son
  /// message tout en le passant aussi ici, et doubler le volume de la console
  /// pile au moment où elle sert — pendant une rafale d'échecs. Le seul endroit
  /// qui justifie l'objet est [severe], où la stack trace doit lui être
  /// attachée.
  static void warn(String message) => _emit(message, level: 900);

  static void severe(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _emit(message, level: 1000, error: error, stackTrace: stackTrace);

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
  static void librarySkipped({
    required String library,
    required Object error,
  }) {
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

  // ── Cache & téléchargements ────────────────────────────────────────────────

  static void downloadFailed({
    required String title,
    required Object error,
  }) {
    warn('Téléchargement échoué — « $title » : $error');
  }

  static void evictionFailed({
    required String path,
    required Object error,
  }) {
    warn('Éviction du cache impossible — $path : $error');
  }

  /// Ménage best-effort qui a échoué (blob résiduel, fichier temporaire).
  /// N'empêche rien de fonctionner, mais explique un `.stagecue` qui grossit.
  static void cleanupFailed({
    required String what,
    required Object error,
  }) {
    warn('Ménage incomplet — $what : $error');
  }

  static void _emit(
    String message, {
    int level = 800,
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
  }
}
