import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path/path.dart' as p;

/// Journalisation audio via DevTools et la Debug Console (`developer.log`).
///
/// Messages concis : une ligne par problème, sans stack trace pour les
/// échecs de chargement attendus (fichier corrompu, cache tronqué, etc.).
class AudioLoadLog {
  AudioLoadLog._();

  static const _name = 'StageCue.Audio';
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
  static const bool traceEnabled =
      bool.fromEnvironment('STAGE_CUE_AUDIO_TRACE');

  static void trace(String message) {
    if (traceEnabled) debugPrint(message);
  }

  static void info(String message) => _emit(message);

  static void warn(String message) => _emit(message, level: 900);

  static void severe(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _emit(
        message,
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );

  static void engineReady() => info('Moteur SoLoud initialisé.');

  static void engineInitFailed(Object error, StackTrace stackTrace) {
    severe(
      'Impossible d\'initialiser SoLoud — l\'app démarre sans audio : $error',
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Doublon asynchrone du plugin flutter_soloud — déjà journalisé au chargement.
  static void benignSoLoudSideEffect(Object error, StackTrace stackTrace) {}

  static void uncaughtZoneError(Object error, StackTrace stackTrace) {
    severe(
      'Erreur non gérée dans la zone audio : $error',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void preloadStarted({required int boardId, required int padCount}) {}

  static void preloadCancelled({required int boardId}) {}

  static void preloadFinished({required int boardId, required int padCount}) {}

  static void padPlayersFailed({
    required int padId,
    required String padLabel,
    required Object error,
    StackTrace? stackTrace,
  }) {
    _once(
      'pad:$padId',
      () => warn('Pad « $padLabel » (id=$padId) : $error'),
    );
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

  static void corruptCacheFile({
    required String path,
    required int bytes,
  }) {
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
