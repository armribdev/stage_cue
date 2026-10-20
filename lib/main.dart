import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'core/app/app.dart';
import 'core/app/app_services.dart';
import 'core/audio/audio_load_log.dart';
import 'core/audio/cue_audio_service.dart';
import 'core/audio/soloud_engine.dart';
import 'core/logging/app_log.dart';
import 'core/logging/log_session.dart';
import 'core/logging/log_sink.dart';
import 'core/sync/google_oauth_config.dart';
import 'core/update/app_mutex_windows.dart';
import 'core/utils/disk_space.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // Le journal fichier démarre avant tout le reste : un échec d'init audio
      // ou de plugin doit déjà y laisser une trace. Les événements émis avant
      // que l'en-tête de session soit prêt restent en buffer mémoire.
      final previousSessionUnclean = await _startFileLog();
      _installGlobalErrorHandlers();

      // Moteur de pré-écoute (cue) séparé, Windows uniquement : n'initialise
      // media_kit que là où la sortie cue est supportée.
      if (CueAudioService.isSupported) {
        MediaKit.ensureInitialized();
      }

      if (!kIsWeb && Platform.isWindows) {
        await windowManager.ensureInitialized();
        // Maintenu ouvert toute la durée du process : signale l'instance en
        // cours à l'installeur Inno Setup lors d'une mise à jour silencieuse.
        holdAppMutexForUpdateDetection();
      }

      // En cas d'échec : on démarre quand même pour afficher l'écran de retry
      // (pas de régie muette avec pads cliquables).
      Object? audioEngineInitError;
      try {
        await initSoLoudEngine();
      } catch (e, stack) {
        AudioLoadLog.engineInitFailed(e, stack);
        audioEngineInitError = e;
      }

      // Credentials OAuth saisis au runtime (Windows/Linux) — avant tout
      // démarrage de sync Drive (AutoSyncCoordinator démarre dans create).
      await GoogleOAuthConfig.load();

      final services = AppServices.create();
      await services.appPreferences.load();
      // Applique le device cue persisté (aucun effet si non configuré).
      CueAudioService.instance.init(
        selectedDeviceId: services.appPreferences.cueOutputDeviceId,
      );
      await _writeSessionHeader(
        services,
        previousSessionUnclean: previousSessionUnclean,
      );
      runApp(
        SoundboardApp(
          services: services,
          audioEngineInitError: audioEngineInitError,
        ),
      );
    },
    (error, stack) {
      if (isBenignSoLoudLoadSideEffect(error)) {
        AudioLoadLog.benignSoLoudSideEffect(error, stack);
        return;
      }
      _reportUncaught('zone', error, stack);
    },
  );
}

/// Dernière erreur journalisée : une même exception peut remonter par deux
/// handlers (zone + plateforme) — une seule ligne suffit.
Object? _lastReportedError;

void _reportUncaught(String source, Object error, StackTrace? stack) {
  if (identical(_lastReportedError, error)) return;
  _lastReportedError = error;
  AppLog.uncaughtError(source, error, stack);
}

/// Démarre le journal fichier. Retourne `true` si la session précédente ne
/// s'est pas terminée proprement. Ne lève jamais : sans journal, l'app démarre
/// quand même.
Future<bool> _startFileLog() async {
  try {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'logs'));
    await LogSink.init(directory: directory);
    // En debug, un hot restart relance `main` sans fermeture propre : le
    // marqueur y produirait un faux positif à chaque itération.
    if (kDebugMode) return false;
    return LogSession.markStarted(directory);
  } catch (e) {
    AppLog.warn('Journal fichier indisponible : $e');
    return false;
  }
}

/// En-tête de session : version, système, schéma, cue, espace disque. Rien de
/// plus — pas de chemin utilisateur, pas d'identité.
Future<void> _writeSessionHeader(
  AppServices services, {
  required bool previousSessionUnclean,
}) async {
  try {
    final package = await PackageInfo.fromPlatform();
    final cacheRoot = await _cacheVolumePath(services);
    final free = await availableDiskBytes(cacheRoot);
    LogSink.writeSessionHeader(
      buildSessionHeader(
        startedAt: LogSink.sessionStart,
        appVersion: package.version,
        buildNumber: package.buildNumber,
        operatingSystem: Platform.operatingSystem,
        operatingSystemVersion: Platform.operatingSystemVersion,
        locale: Platform.localeName,
        schemaVersion: services.database.schemaVersion,
        cueConfigured: services.appPreferences.cueOutputDeviceId != null,
        freeDiskBytes: free,
        previousSessionUnclean: previousSessionUnclean,
      ),
    );
  } catch (e) {
    AppLog.warn('En-tête de session incomplet : $e');
  }
}

/// Racine de cache de la première bibliothèque, à défaut le dossier de support
/// de l'app (même volume que la base).
Future<String> _cacheVolumePath(AppServices services) async {
  try {
    final libraries = await services.libraryRepository.getLibraries();
    for (final library in libraries) {
      if (library.localRootPath.isNotEmpty) return library.localRootPath;
    }
  } catch (_) {}
  return (await getApplicationSupportDirectory()).path;
}

void _installGlobalErrorHandlers() {
  PlatformDispatcher.instance.onError = (error, stack) {
    if (isBenignSoLoudLoadSideEffect(error)) {
      AudioLoadLog.benignSoLoudSideEffect(error, stack);
      return true;
    }
    _reportUncaught('platform', error, stack);
    // Non géré au sens du moteur : le comportement par défaut (console) reste.
    return false;
  };

  final previousFlutterErrorHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    if (isBenignSoLoudLoadSideEffect(details.exception)) {
      AudioLoadLog.benignSoLoudSideEffect(
        details.exception,
        details.stack ?? StackTrace.current,
      );
      return;
    }
    _reportUncaught('flutter', details.exception, details.stack);
    previousFlutterErrorHandler?.call(details);
  };
}
