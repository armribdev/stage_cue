import 'package:flutter_soloud/flutter_soloud.dart';

import 'audio_load_log.dart';

/// Taille de buffer SoLoud — latence réduite pour un soundboard réactif.
const int kSoLoudBufferSize = 1024;

/// Initialise le moteur SoLoud (appelé au démarrage et sur retry UI).
///
/// Propage toute exception du plugin ; le caller affiche l'échec à l'utilisateur
/// plutôt que de démarrer une régie muette.
Future<void> initSoLoudEngine() async {
  await SoLoud.instance.init(bufferSize: kSoLoudBufferSize);
  AudioLoadLog.engineReady();
}
