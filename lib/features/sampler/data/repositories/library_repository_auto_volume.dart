part of 'library_repository.dart';

/// Sons mesurables par un recalcul en masse du gain « auto », et ce que ce
/// recalcul écraserait : sert à demander confirmation avant d'écrire.
class AutoVolumePlan {
  /// Sons dont le fichier est déjà présent sur cet appareil.
  final List<Sound> sounds;

  /// Sons ignorés faute de fichier local (un recalcul ne télécharge rien).
  final int unavailable;

  /// Identités des sons dont l'app n'a jamais mesuré le gain (au gain par
  /// défaut, sans génération de mesure) : ceux qu'un recalcul « sans toucher aux
  /// réglages » peut mesurer.
  final Set<int> _unmeasuredIds;

  const AutoVolumePlan({
    required this.sounds,
    required this.unavailable,
    Set<int> unmeasuredIds = const {},
  }) : _unmeasuredIds = unmeasuredIds;

  /// Sons dont le gain a déjà été réglé (≠ 1.0, à la main ou par un « Auto »
  /// précédent) : le recalcul le remplace.
  int get customized => sounds.where((s) => s.gain != 1.0).length;

  /// Sons disponibles dont le gain n'a jamais été mesuré.
  int get unmeasured =>
      sounds.where((s) => _unmeasuredIds.contains(s.id)).length;

  /// Le même plan restreint aux sons jamais mesurés : aucun gain réglé n'y est
  /// remplacé.
  AutoVolumePlan onlyUnmeasured() => AutoVolumePlan(
    sounds: [
      for (final sound in sounds)
        if (_unmeasuredIds.contains(sound.id)) sound,
    ],
    unavailable: unavailable,
    unmeasuredIds: _unmeasuredIds,
  );
}

/// Bilan d'un recalcul en masse.
typedef AutoVolumeResult = ({
  int updated,
  int unmeasurable,
  int skipped,
  bool cancelled,
});

/// Recalcul en masse du gain « auto » ([décision 0036], amendée par
/// [décision 0044]) : écrit le gain mesuré de chaque son ([décision 0045]).
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
      unmeasuredIds: await _soundDataSource.getUnmeasuredGainSoundIds(),
    );
  }

  /// Mesure chaque son de [plan] et écrit son gain « auto ».
  ///
  /// Séquentiel, sur la file de décodage native partagée avec le chargement des
  /// pads ([décision 0001]). Chaque gain est écrit dès qu'il est mesuré :
  /// annuler ([isCancelled]) ou fermer l'écran ne perd rien de ce qui est fait,
  /// et relancer reprend sans dommage. Un son illisible ou silencieux garde son
  /// gain. Ne touche pas au téléchargement.
  Future<AutoVolumeResult> recomputeAutoVolumes(
    AutoVolumePlan plan, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    var updated = 0, unmeasurable = 0, skipped = 0, boosted = 0;
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
        final profile = loudnessProfileOf(sound.type);
        final measurement = await measureAutoVolume(File(path), profile);
        if (measurement == null) {
          unmeasurable++;
        } else {
          final gain = autoLoudnessGain(measurement, profile);
          await _soundDataSource.updateSoundSettings(
            id: sound.id,
            gain: gain,
            gainMeasured: true,
          );
          updated++;
          if (gain > 1.0) boosted++;
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
      'Gain auto en masse : $updated mis à jour ($boosted relevés), '
      '$unmeasurable non '
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
