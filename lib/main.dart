import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:media_kit/media_kit.dart';
import 'core/app/app.dart';
import 'core/app/app_services.dart';
import 'core/audio/audio_load_log.dart';
import 'core/audio/cue_audio_service.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      _installGlobalErrorHandlers();

      // Moteur de pré-écoute (cue) séparé, desktop uniquement : n'initialise
      // media_kit que là où la sortie cue est supportée (Windows).
      if (CueAudioService.isSupported) {
        MediaKit.ensureInitialized();
      }

      try {
        await SoLoud.instance.init(
          bufferSize: 1024, // Latence réduite pour soundboard réactif
        );
        AudioLoadLog.engineReady();
      } catch (e, stack) {
        AudioLoadLog.engineInitFailed(e, stack);
      }

      final services = AppServices.create();
      await services.appPreferences.load();
      // Applique le device cue persisté (aucun effet si non configuré).
      CueAudioService.instance.init(
        selectedDeviceId: services.appPreferences.cueOutputDeviceId,
      );
      runApp(SoundboardApp(services: services));
    },
    (error, stack) {
      if (isBenignSoLoudLoadSideEffect(error)) {
        AudioLoadLog.benignSoLoudSideEffect(error, stack);
        return;
      }
      AudioLoadLog.uncaughtZoneError(error, stack);
    },
  );
}

void _installGlobalErrorHandlers() {
  PlatformDispatcher.instance.onError = (error, stack) {
    if (isBenignSoLoudLoadSideEffect(error)) {
      AudioLoadLog.benignSoLoudSideEffect(error, stack);
      return true;
    }
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
    previousFlutterErrorHandler?.call(details);
  };
}
