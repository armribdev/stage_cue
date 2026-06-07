import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'core/app/app.dart';
import 'core/app/app_services.dart';
import 'core/audio/soloud_file_loader.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // flutter_soloud relance certaines erreurs de chargement dans son listener
  // interne en plus de completeError sur le Future — filtrer pour éviter un crash.
  PlatformDispatcher.instance.onError = (error, stack) {
    if (isBenignSoLoudLoadSideEffect(error)) {
      debugPrint('SoLoud (erreur déjà gérée par l\'app): $error');
      return true;
    }
    return false;
  };

  await SoLoud.instance.init(
    bufferSize: 1024, // Latence réduite pour soundboard réactif
  );
  final services = AppServices.create();
  runApp(SoundboardApp(services: services));
}
