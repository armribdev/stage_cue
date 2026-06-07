import '../../../../core/audio/audio_player_service.dart';

/// Disponibilité locale d'un son dans un pad multi-variantes.
enum PadSoundAvailability {
  ready,
  needsDownload,
  offline,
  missingFile,
}

/// Lecteur audio aligné sur un son du pad (même index que [Pad.sounds]).
class PadSoundSlot {
  PadSoundAvailability availability;
  AudioPlayerService? player;

  PadSoundSlot({
    this.availability = PadSoundAvailability.needsDownload,
    this.player,
  });

  bool get isReady =>
      availability == PadSoundAvailability.ready && player != null;

  void dispose() {
    try {
      player?.dispose();
    } catch (_) {
      // Best-effort : source SoLoud peut déjà être invalidée.
    }
    player = null;
  }
}
