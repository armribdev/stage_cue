import 'dart:developer' as developer;

import 'log_sink.dart';

/// Journalisation transverse de l'application (cycle de vie, Mode Spectacle,
/// base de données, erreurs non gérées), canal `StageCue.App`.
///
/// Pendant de [SyncLog], `AudioLoadLog` et `UpdateLog` pour ce qui n'appartient
/// à aucun sous-système. Mêmes règles : `developer.log` pour DevTools, plus le
/// journal fichier ([LogSink]) pour les builds release.
class AppLog {
  AppLog._();

  static const _name = 'StageCue.App';
  static const _channel = 'App';

  static void info(String message) => _emit(LogLevel.info, message);

  static void warn(String message) => _emit(LogLevel.warn, message);

  static void severe(String message, {Object? error, StackTrace? stackTrace}) =>
      _emit(LogLevel.severe, message, error: error, stackTrace: stackTrace);

  /// Erreur non gérée, toutes origines confondues. [source] dit par quel
  /// handler elle est remontée (`zone`, `platform`, `flutter`) : c'est ce qui
  /// permet de distinguer une exception de rendu d'un `Future` oublié.
  static void uncaughtError(
    String source,
    Object error,
    StackTrace? stackTrace,
  ) {
    severe('Erreur non gérée ($source)', error: error, stackTrace: stackTrace);
  }

  static void _emit(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: _name,
      level: _developerLevel(level),
      error: error,
      stackTrace: stackTrace,
    );
    LogSink.log(_channel, level, message, error: error, stackTrace: stackTrace);
  }

  static int _developerLevel(LogLevel level) => switch (level) {
    LogLevel.trace || LogLevel.info => 800,
    LogLevel.warn => 900,
    LogLevel.severe => 1000,
  };
}
