import 'dart:developer' as developer;

import '../logging/log_sink.dart';

/// Journalisation du check de mise à jour et de l'installation, via DevTools
/// et la Debug Console (`developer.log`).
///
/// Pendant de [SyncLog] pour le sous-système de mise à jour. Canal distinct
/// (`StageCue.Update`) : un check de version qui échoue silencieusement se
/// confondrait sinon avec le bruit de la synchro Drive.
class UpdateLog {
  UpdateLog._();

  static const _name = 'StageCue.Update';
  static const _channel = 'Update';

  static void info(String message) => _emit(message, LogLevel.info);

  static void warn(String message) => _emit(message, LogLevel.warn, level: 900);

  static void checkStarted() => info('Vérification de mise à jour…');

  static void upToDate(String currentVersion) =>
      info('Déjà à jour (version $currentVersion).');

  static void newVersionFound({
    required String version,
    required String assetName,
  }) => info('Nouvelle version disponible : $version ($assetName).');

  static void checkFailed(Object error) =>
      warn('Vérification de mise à jour échouée — $error');

  static void downloadStarted(String url) =>
      info('Téléchargement de l\'installeur — $url');

  static void downloadFailed(Object error) =>
      warn('Téléchargement de l\'installeur échoué — $error');

  static void installLaunched(String path) => info('Installeur lancé — $path');

  static void installLaunchFailed(Object error) =>
      warn('Lancement de l\'installeur échoué — $error');

  static void _emit(String message, LogLevel sinkLevel, {int level = 800}) {
    developer.log(message, name: _name, level: level);
    LogSink.log(_channel, sinkLevel, message);
  }
}
