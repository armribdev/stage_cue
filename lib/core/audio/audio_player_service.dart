import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Service de gestion des lecteurs audio
class AudioPlayerService {
  final AudioPlayer _player;

  AudioPlayerService() : _player = AudioPlayer() {
    // just_audio permet naturellement la lecture simultanée
    // Chaque instance peut jouer indépendamment
  }

  /// Joue un fichier audio
  Future<void> play(String filePath) async {
    try {
      // Si un son est déjà en cours, on le relance depuis le début
      if (_player.playing) {
        await _player.stop();
      }
      await _player.setFilePath(filePath);
      // Attendre que la durée soit disponible (avec un timeout de sécurité)
      try {
        await _player.durationStream
            .where((d) => d != null && d.inMilliseconds > 0)
            .timeout(const Duration(seconds: 2))
            .first;
      } catch (e) {
        // Si le timeout est atteint, continuer quand même (la durée sera disponible plus tard)
        // C'est juste pour éviter d'attendre indéfiniment
      }
      // S'assurer que la position est à zéro avant de jouer
      await _player.seek(Duration.zero);
      await _player.play();
    } catch (e) {
      // Gérer les erreurs silencieusement ou les logger
      debugPrint('Erreur lors de la lecture: $e');
    }
  }

  /// Arrête la lecture
  Future<void> stop() async {
    await _player.stop();
  }

  /// Écoute les changements d'état du lecteur (true = en cours, false = arrêté)
  /// Utilise playerStateStream pour détecter correctement la fin de la lecture
  Stream<bool> get onPlayerStateChanged => _player.playerStateStream.map((state) {
    return state.playing && state.processingState != ProcessingState.completed;
  });

  /// Obtient la durée du fichier audio (peut être null si pas encore chargé)
  Duration? get duration => _player.duration;

  /// Dispose les ressources
  void dispose() {
    _player.dispose();
  }
}


