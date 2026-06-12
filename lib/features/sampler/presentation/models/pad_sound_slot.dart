import 'dart:async';

import '../../../../core/audio/audio_player_service.dart';

/// Disponibilité locale d'un son dans un pad multi-variantes.
enum PadSoundAvailability {
  ready,
  /// Fichier local vérifié — affichage PRÊT, lecteur SoLoud pas encore chargé.
  cached,
  needsDownload,
  offline,
  missingFile,
  /// Fichier présent mais format non décodable par SoLoud sur cette plateforme.
  unsupportedFormat,
}

/// Lecteur audio aligné sur un son du pad (même index que [Pad.sounds]).
class PadSoundSlot {
  PadSoundAvailability availability;
  AudioPlayerService? player;
  StreamSubscription<bool>? _playerSubscription;

  PadSoundSlot({
    this.availability = PadSoundAvailability.needsDownload,
    this.player,
  });

  bool get isReady =>
      availability == PadSoundAvailability.ready && player != null;

  bool get isCached => availability == PadSoundAvailability.cached;

  /// Prêt à jouer ou fichier local déjà validé (phase 0).
  bool get appearsReady => isReady || isCached;

  /// Attache [handler] sur [player.onPlayerStateChanged].
  /// Annule le listener précédent s'il existait — garantit qu'un seul listener
  /// actif existe à tout moment, même si appelé plusieurs fois sur le même slot.
  void attachListener(void Function(bool) handler) {
    _playerSubscription?.cancel();
    _playerSubscription = null;
    final p = player;
    if (p != null) {
      _playerSubscription = p.onPlayerStateChanged.listen(handler);
    }
  }

  void dispose() {
    _playerSubscription?.cancel();
    _playerSubscription = null;
    try {
      player?.dispose();
    } catch (_) {
      // Best-effort : source SoLoud peut déjà être invalidée.
    }
    player = null;
  }
}
