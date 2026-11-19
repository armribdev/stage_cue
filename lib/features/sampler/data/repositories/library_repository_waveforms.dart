part of 'library_repository.dart';

/// Bilan d'une passe de waveforms.
typedef WaveformPassResult = ({
  int updated,
  int unsupported,
  int unavailable,
  bool cancelled,
});

/// Waveforms de masse : rattrapage automatique des sons dont l'enveloppe manque
/// ou date d'une génération obsolète, et recalcul de maintenance (décision 0049).
/// Méthodes de [LibraryRepository] extraites via extension dans le même `part`.
extension LibraryRepositoryWaveforms on LibraryRepository {
  /// Sons de [sounds] dont l'enveloppe est à (re)faire : jamais sondés ou sondés
  /// sous une génération d'extraction antérieure (`waveformNeedsProbe`).
  List<Sound> soundsWithStaleWaveform(Iterable<Sound> sounds) => [
    for (final sound in sounds)
      if (waveformNeedsProbe(sound.waveformProbeGeneration)) sound,
  ];

  /// Rattrape les waveforms manquantes ou obsolètes des sons **déjà sur
  /// l'appareil** : ne télécharge rien et n'écrit **aucun gain** (décision 0048).
  /// [shouldStop] est interrogée entre deux sons (Mode Spectacle, arrière-plan,
  /// synchro…) : une valeur non nulle arrête la passe, relancée au prochain tick.
  /// Ne lève jamais.
  Future<WaveformPassResult> _backfillStaleWaveforms({
    required String? Function() shouldStop,
  }) async {
    var stoppedBy = shouldStop();
    if (stoppedBy != null) {
      return (updated: 0, unsupported: 0, unavailable: 0, cancelled: true);
    }
    try {
      final stale = soundsWithStaleWaveform(
        await _soundDataSource.getAllSounds(),
      );
      if (stale.isEmpty) {
        return (updated: 0, unsupported: 0, unavailable: 0, cancelled: false);
      }
      final available = await probeLocallyAvailableSoundIds(stale);
      final local = [
        for (final sound in stale)
          if (available.contains(sound.id)) sound,
      ];
      if (local.isEmpty) {
        return (updated: 0, unsupported: 0, unavailable: 0, cancelled: false);
      }
      AudioLoadLog.info(
        'Waveforms : rattrapage de ${local.length} son(s) à (re)calculer'
        '${stale.length > local.length ? ' (${stale.length - local.length} '
                  'pas encore téléchargé(s))' : ''}.',
      );
      final result = await recomputeWaveforms(
        local,
        isCancelled: () => (stoppedBy = shouldStop()) != null,
      );
      AudioLoadLog.info(
        'Waveforms : bilan — ${result.updated} calculée(s), '
        '${result.unsupported} format(s) refusé(s), ${result.unavailable} '
        'fichier(s) indisponible(s)'
        '${result.cancelled ? ' — interrompu : ${stoppedBy ?? 'moteur audio pas prêt'}' : ''}.',
      );
      return result;
    } catch (e, stackTrace) {
      AudioLoadLog.warn('Waveforms : rattrapage abandonné — $e\n$stackTrace');
      return (updated: 0, unsupported: 0, unavailable: 0, cancelled: true);
    }
  }

  /// Recalcule l'enveloppe de chaque son de [sounds] depuis son fichier local,
  /// **sans écrire de gain** (le gain a son propre recalcul).
  ///
  /// Séquentiel, sur la file de décodage native partagée avec le chargement des
  /// pads (décision 0001). Chaque enveloppe est écrite dès qu'elle est calculée :
  /// annuler ne perd rien. Une enveloppe qui échoue ne remplace jamais une
  /// enveloppe valable (`persistWaveformProbe`). Moteur audio pas prêt : la passe
  /// s'arrête (`cancelled`), rien n'est mémorisé.
  Future<WaveformPassResult> recomputeWaveforms(
    List<Sound> sounds, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    var updated = 0, unsupported = 0, unavailable = 0;
    var cancelled = false;
    final total = sounds.length;
    for (var i = 0; i < total; i++) {
      if (isCancelled?.call() == true) {
        cancelled = true;
        break;
      }
      final sound = sounds[i];
      try {
        final file = await _existingLocalFile(sound);
        if (file == null) {
          unavailable++;
        } else {
          final probe = await extractWaveform(file.path);
          if (probe.status == WaveformProbeStatus.transient) {
            cancelled = true;
            break;
          }
          await _soundDataSource.persistWaveformProbe(
            sound.id,
            probe,
            file: file,
            measureGain: false,
          );
          if (probe.status == WaveformProbeStatus.success) {
            updated++;
          } else {
            unsupported++;
          }
        }
      } catch (e) {
        AudioLoadLog.trace('recomputeWaveforms: son ${sound.id} — $e');
        unavailable++;
      }
      onProgress?.call(i + 1, total);
    }
    return (
      updated: updated,
      unsupported: unsupported,
      unavailable: unavailable,
      cancelled: cancelled,
    );
  }

  /// Fichier local d'un son, ou `null` s'il n'est pas (ou plus) utilisable.
  ///
  /// Volontairement **pas** `resolvePlayablePath` : il lance en tâche de fond
  /// `materializeSoundFileMetadata`, qui mesure le gain d'un son encore à 1.0 —
  /// une passe de masse changerait ainsi des niveaux sans qu'on l'ait demandé
  /// (décision 0048). Ici : lecture seule, rien n'est écrit ni téléchargé.
  Future<File?> _existingLocalFile(Sound sound) async {
    final String expected;
    final libraryId = sound.libraryId;
    final relative = sound.relativePath;
    if (libraryId != null) {
      if (relative == null || relative.isEmpty) return null;
      final library = await _dataSource.getLibraryById(libraryId);
      if (library == null) return null;
      expected = _cacheManager.localPathFor(
        library,
        LibrarySoundPaths.normalizeRelativePath(relative),
      );
    } else {
      expected = sound.filePath;
    }
    final canonical = await PathUnicode.canonicalizeLocalPath(expected);
    if (canonical == null) return null;
    final file = File(p.normalize(canonical));
    return await isPlausibleAudioFile(file) ? file : null;
  }
}
