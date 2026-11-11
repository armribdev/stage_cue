part of 'library_repository.dart';

/// Sons mesurables par un recalcul en masse du volume « auto », et ce que ce
/// recalcul écraserait : sert à demander confirmation avant d'écrire.
class AutoVolumePlan {
  /// Sons dont le fichier est déjà présent sur cet appareil.
  final List<Sound> sounds;

  /// Sons ignorés faute de fichier local (un recalcul ne télécharge rien).
  final int unavailable;

  const AutoVolumePlan({required this.sounds, required this.unavailable});

  /// Sons dont le volume a déjà été réglé (≠ 1.0) : le recalcul le remplace.
  int get customized => sounds.where((s) => s.volume != 1.0).length;
}

/// Bilan d'un recalcul en masse.
typedef AutoVolumeResult = ({
  int updated,
  int unmeasurable,
  int skipped,
  bool cancelled,
});

/// Recalcul en masse du volume « auto » ([décision 0036]).
/// Méthodes de [LibraryRepository] extraites via extension dans le même `part`.
extension LibraryRepositoryAutoVolume on LibraryRepository {
  /// Dresse le plan d'un recalcul : sons disponibles localement et sons ignorés.
  /// Une seule sonde de masse, pas un `resolvePlayablePath` par son.
  Future<AutoVolumePlan> planAutoVolumeRecompute() async {
    final all = await _soundDataSource.getAllSounds();
    final available = await probeLocallyAvailableSoundIds(all);
    final local = [
      for (final sound in all)
        if (available.contains(sound.id)) sound,
    ];
    return AutoVolumePlan(
      sounds: local,
      unavailable: all.length - local.length,
    );
  }

  /// Mesure chaque son de [plan] et écrit son volume « auto ».
  ///
  /// Séquentiel, sur la file de décodage native partagée avec le chargement des
  /// pads ([décision 0001]). Chaque volume est écrit dès qu'il est mesuré :
  /// annuler ([isCancelled]) ou fermer l'écran ne perd rien de ce qui est fait,
  /// et relancer reprend sans dommage. Un son illisible ou silencieux garde son
  /// volume. Ne touche ni aux overrides par pad (`pad_sounds.volume`) ni au
  /// téléchargement.
  Future<AutoVolumeResult> recomputeAutoVolumes(
    AutoVolumePlan plan, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    var updated = 0, unmeasurable = 0, skipped = 0;
    var cancelled = false;
    final total = plan.sounds.length;
    for (var i = 0; i < total; i++) {
      if (isCancelled?.call() == true) {
        cancelled = true;
        break;
      }
      final sound = plan.sounds[i];
      try {
        final path = await resolvePlayablePath(sound, downloadIfNeeded: false);
        final volume = await measureAutoVolume(
          File(path),
          loudnessProfileOf(sound.type),
        );
        if (volume == null) {
          unmeasurable++;
        } else {
          await _soundDataSource.updateSoundSettings(
            id: sound.id,
            volume: volume,
          );
          updated++;
        }
      } on SoundNotAvailableLocallyException {
        // Fichier disparu du cache, ou rejeté par la validation d'en-tête.
        skipped++;
      } catch (e) {
        AudioLoadLog.trace('recomputeAutoVolumes: son ${sound.id} — $e');
        unmeasurable++;
      }
      onProgress?.call(i + 1, total);
    }
    AudioLoadLog.info(
      'Volume auto en masse : $updated mis à jour, $unmeasurable non '
      'mesurables, $skipped fichiers indisponibles, ${plan.unavailable} sans '
      'fichier local${cancelled ? ', annulé' : ''}.',
    );
    return (
      updated: updated,
      unmeasurable: unmeasurable,
      skipped: skipped,
      cancelled: cancelled,
    );
  }
}
