import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path/path.dart' as p;

import '../logging/log_sink.dart';

/// Journalisation audio via DevTools et la Debug Console (`developer.log`).
///
/// Messages concis : une ligne par problème, sans stack trace pour les
/// échecs de chargement attendus (fichier corrompu, cache tronqué, etc.).
class AudioLoadLog {
  AudioLoadLog._();

  static const _name = 'StageCue.Audio';
  static const _channel = 'Audio';
  static final Set<String> _loggedOnce = {};

  static void _once(String key, void Function() log) {
    if (_loggedOnce.add(key)) log();
  }

  static String _shortPath(String path) => p.basename(path);

  /// Traces de diagnostic à **haute fréquence** (chargement de pad, listeners de
  /// lecture, sélection de variante). Muettes par défaut — sinon elles polluent
  /// la console en debug/profile (le listener de lecture émet à chaque
  /// changement d'état). Activer pour investiguer :
  /// `--dart-define=STAGE_CUE_AUDIO_TRACE=true`.
  static const bool traceEnabled = bool.fromEnvironment(
    'STAGE_CUE_AUDIO_TRACE',
  );

  static void trace(String message) {
    if (!traceEnabled) return;
    debugPrint(message);
    LogSink.log(_channel, LogLevel.trace, message);
  }

  /// Avertissement journalisé **une seule fois par clé** pour la session : à
  /// utiliser quand une même cause peut se répéter en boucle.
  static void warnOnce(String key, String message) =>
      _once('once:$key', () => warn(message));

  static void info(String message) => _emit(message, sinkLevel: LogLevel.info);

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

  static void engineReady() => info('Moteur SoLoud initialisé.');

  static void engineInitFailed(Object error, StackTrace stackTrace) {
    severe(
      'Impossible d\'initialiser SoLoud — écran de retry affiché : $error',
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Doublon asynchrone du plugin flutter_soloud — déjà journalisé au chargement.
  static void benignSoLoudSideEffect(Object error, StackTrace stackTrace) {}

  // ── Préchargement d'un plateau ─────────────────────────────────────────────

  static void preloadStarted({required int boardId, required int padCount}) =>
      trace('[PRELOAD] plateau #$boardId : $padCount pad(s) à charger');

  static void preloadCancelled({required int boardId}) =>
      trace('[PRELOAD] plateau #$boardId : annulé (changement de plateau)');

  /// Bilan d'un préchargement mené jusqu'au bout : une ligne par plateau, `warn`
  /// si au moins un pad est resté indisponible (c'est le « pourquoi mon pad est
  /// grisé ? » du lendemain).
  static void preloadFinished({
    required int boardId,
    required int padCount,
    int unavailableCount = 0,
    Duration elapsed = Duration.zero,
  }) {
    final message =
        'Plateau #$boardId préchargé : $padCount pad(s), '
        '$unavailableCount indisponible(s), ${elapsed.inMilliseconds} ms.';
    if (unavailableCount > 0) {
      warn(message);
    } else {
      info(message);
    }
  }

  // ── Déclenchement d'un pad ─────────────────────────────────────────────────

  static final Map<String, DateTime> _triggerFailureAt = {};

  /// Fenêtre dans laquelle un même échec (pad + raison) n'est journalisé
  /// qu'une fois : un opérateur qui retape trois fois un pad muet est une seule
  /// information, pas trois.
  static const Duration _triggerFailureWindow = Duration(seconds: 2);

  /// Un pad déclenché n'a rien joué. C'est LA question post-incident ; elle ne
  /// doit jamais rester muette (cf. `toggleSound`, qui retournait sans un mot).
  static void padTriggerFailed({
    required int padId,
    required String padLabel,
    required String reason,
  }) {
    final key = '$padId|$reason';
    final now = DateTime.now();
    final last = _triggerFailureAt[key];
    if (last != null && now.difference(last) < _triggerFailureWindow) return;
    _triggerFailureAt[key] = now;
    warn('Pad « $padLabel » (id=$padId) n\'a rien joué : $reason');
  }

  // ── Voies à faible fréquence ───────────────────────────────────────────────

  static void musicStarted({required String padLabel, required int padId}) =>
      info('Musique démarrée : « $padLabel » (pad $padId).');

  static void musicStopped({
    required String padLabel,
    required int padId,
    bool paused = false,
  }) => info(
    'Musique ${paused ? 'mise en pause' : 'arrêtée'} : '
    '« $padLabel » (pad $padId).',
  );

  static void ambianceStarted({required String padLabel, required int padId}) =>
      info('Ambiance démarrée : « $padLabel » (pad $padId).');

  static void ambianceReplaced({
    required String fromLabel,
    required String toLabel,
    required int toPadId,
  }) => info(
    'Ambiance remplacée (fondu enchaîné) : « $fromLabel » → '
    '« $toLabel » (pad $toPadId).',
  );

  static void ambianceStopped({required String padLabel, required int padId}) =>
      info('Ambiance arrêtée : « $padLabel » (pad $padId).');

  /// Bouton panique : coupe les bruitages, laisse musique et ambiance.
  static void panic({
    required int stoppedPads,
    required bool musicStillPlaying,
    required bool ambianceStillPlaying,
  }) => info(
    'Panique : $stoppedPads pad(s) de bruitage coupé(s) — musique '
    '${musicStillPlaying ? 'laissée' : 'absente'}, ambiance '
    '${ambianceStillPlaying ? 'laissée' : 'absente'}.',
  );

  // ── Périphériques de sortie (cue) ──────────────────────────────────────────

  static void cueDevicesEnumerationFailed(Object error) =>
      warn('Énumération des périphériques de sortie cue échouée — $error');

  static void cueFallbackToSoLoud(Object error) => warn(
    'Pré-écoute cue (media_kit) indisponible, repli sur la sortie '
    'principale — $error',
  );

  static void cueOutputChanged({required bool configured}) => info(
    configured
        ? 'Sortie cue : périphérique dédié configuré.'
        : 'Sortie cue : retour à la sortie principale (SoLoud).',
  );

  static void padPlayersFailed({
    required int padId,
    required String padLabel,
    required Object error,
    StackTrace? stackTrace,
  }) {
    _once('pad:$padId', () => warn('Pad « $padLabel » (id=$padId) : $error'));
  }

  static void soundLoadFailed({
    required int soundId,
    required String title,
    required int padId,
    String? resolvedPath,
    String? legacyPath,
    required Object error,
    StackTrace? stackTrace,
  }) {
    final path = resolvedPath ?? legacyPath;
    if (path != null) {
      _fileFailed(path, error);
      return;
    }
    _once(
      'sound:$soundId',
      () => warn('Son « $title » (pad $padId) indisponible — $error'),
    );
  }

  static void loadMemFailed({
    required String path,
    required Object error,
    StackTrace? stackTrace,
  }) {
    _fileFailed(path, error);
  }

  static void corruptCacheFile({required String path, required int bytes}) {
    _once(
      'corrupt:$path',
      () => warn(
        'Cache audio invalide (${_shortPath(path)}, $bytes o) '
        '— re-téléchargement si possible',
      ),
    );
  }

  static void metadataProbeFailed({
    required String path,
    required Object error,
  }) {
    _fileFailed(path, error);
  }

  static void _fileFailed(String path, Object error) {
    _once(
      'file:$path',
      () => warn('Fichier audio illisible : ${_shortPath(path)} — $error'),
    );
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

/// Erreurs SoLoud émises en double par le listener interne de flutter_soloud
/// (completeError sur le Future + throw dans le stream), ou erreurs de décodage
/// déjà converties en indisponibilité pad.
bool isBenignSoLoudLoadSideEffect(Object error) {
  if (error is SoLoudNotInitializedException) return true;
  if (error is SoLoudCppException) {
    return error is! SoLoudDllNotFoundException &&
        error is! SoLoudBackendNotInitedException;
  }
  return false;
}
