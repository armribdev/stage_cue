import 'dart:developer' as developer;

import 'package:flutter_soloud/flutter_soloud.dart';

import 'audio_file_validation.dart';

/// Journalisation audio via DevTools et la Debug Console (`developer.log`).
class AudioLoadLog {
  AudioLoadLog._();

  static const _name = 'StageCue.Audio';
  static final Set<String> _loggedOnce = {};

  static void _once(String key, void Function() log) {
    if (_loggedOnce.add(key)) log();
  }

  static void info(String message) => _emit(message);

  static void warn(String message, {Object? error, StackTrace? stackTrace}) =>
      _emit(message, level: 900, error: error, stackTrace: stackTrace);

  static void severe(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _emit(message, level: 1000, error: error, stackTrace: stackTrace);

  static void engineReady() => info('Moteur SoLoud initialisé.');

  static void engineInitFailed(Object error, StackTrace stackTrace) {
    severe(
      'Impossible d\'initialiser SoLoud — l\'app démarre sans audio.',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void benignSoLoudSideEffect(Object error, StackTrace stackTrace) {
    _once(
      'soloud-side-effect:${error.runtimeType}',
      () => warn(
        'Erreur SoLoud absorbée (effet de bord du plugin) : $error',
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  static void uncaughtZoneError(Object error, StackTrace stackTrace) {
    severe(
      'Erreur non gérée dans la zone audio',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void preloadStarted({required int boardId, required int padCount}) {
    info('Préchargement audio plateau #$boardId — $padCount pad(s).');
  }

  static void preloadCancelled({required int boardId}) {
    info('Préchargement audio annulé (plateau #$boardId remplacé).');
  }

  static void preloadFinished({required int boardId, required int padCount}) {
    info('Préchargement audio terminé plateau #$boardId — $padCount pad(s).');
  }

  static void padPlayersFailed({
    required int padId,
    required String padLabel,
    required Object error,
    StackTrace? stackTrace,
  }) {
    severe(
      'Échec lecteurs pad id=$padId « $padLabel »',
      error: error,
      stackTrace: stackTrace,
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
    final path = resolvedPath ?? legacyPath ?? '?';
    _once(
      'sound:$soundId:$path',
      () => severe(
        'Échec son id=$soundId « $title » pad=$padId path=$path — $error',
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  static void loadMemFailed({
    required String path,
    required Object error,
    StackTrace? stackTrace,
  }) {
    _once(
      'loadMem:$path',
      () => severe(
        'Échec loadMem : $path — $error',
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  static void corruptCacheFile({
    required String path,
    required int bytes,
  }) {
    _once(
      'corrupt:$path',
      () => warn(
        'Cache audio invalide ($bytes o, min $kMinimumValidAudioFileBytes o) '
        '— suppression et nouveau téléchargement si possible : $path',
      ),
    );
  }

  static void metadataProbeFailed({
    required String path,
    required Object error,
  }) {
    _once(
      'metadata:$path',
      () => warn(
        'Durée audio illisible (type par défaut) : $path — $error',
      ),
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
