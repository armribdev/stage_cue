// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../settings_screen.dart';

/// Actions sur les bibliothèques : retrait, actualisation Drive, maintenance.
/// Méthodes de [_SettingsScreenState] extraites via extension dans le même `part`.
extension _SettingsLibraryActions on _SettingsScreenState {
  /// Vérification manuelle : ignore le throttle 6h du check automatique
  /// (voir `SoundboardApp._maybeCheckForUpdateOnLaunch`).
  Future<void> _checkForUpdatesManually() async {
    if (_isCheckingForUpdate) return;
    setState(() => _isCheckingForUpdate = true);
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final update = await AppUpdateChecker().checkForUpdate(
        currentVersion: packageInfo.version,
      );
      if (!mounted) return;
      if (update == null) {
        AppSnackBar.show(
          context,
          'Vous avez déjà la dernière version',
          duration: const Duration(seconds: 2),
        );
        return;
      }
      await runUpdateFlow(context, update);
    } catch (e) {
      UpdateLog.checkFailed(e);
      if (mounted) {
        showCopyableSnackBar(context, 'Échec de la vérification : $e');
      }
    } finally {
      if (mounted) setState(() => _isCheckingForUpdate = false);
    }
  }

  Future<void> _confirmRemoveWatchedPath(db.WatchedPath watchedPath) async {
    final label = _labelsForWatchedPath(watchedPath).title;
    final type = SafDirectoryBridge.isSafTreeUri(watchedPath.path)
        ? 'dossier cloud'
        : 'dossier local';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Retirer l\'élément indexé'),
          content: Text(
            'Retirer le $type "$label" ? '
            'Les sons importés depuis cet élément seront supprimés '
            'de la bibliothèque et retirés des scènes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Retirer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await _removeWatchedPath(watchedPath);
  }

  /// Actualisation manuelle : délègue au coordinateur, qui rejoue exactement la
  /// séquence de lancement (delta d'abord, scan complet en repli, indexation
  /// AVANT le pull). Cet écran n'orchestre plus rien lui-même — deux séquences
  /// de synchronisation en parallèle finiraient par diverger, et c'est ici que
  /// la divergence était déjà réelle : le bouton tirait avant d'indexer et
  /// rescannait systématiquement.
  Future<void> _refreshAllFromDrive() async {
    final hasDriveLibrary = _libraries.any(
      (library) => library.isConnectedToDrive,
    );
    if (!hasDriveLibrary) {
      if (mounted) {
        AppSnackBar.show(context, 'Aucun dossier Drive indexé');
      }
      return;
    }

    setState(() => _isSyncBusy = true);
    try {
      final report = await widget.autoSyncCoordinator.refreshNow(
        onIndexProgress: (library, progress) {
          if (!mounted) return;
          setState(() {
            _indexingProgress[_driveProgressKey(library.id)] = progress;
          });
        },
      );
      if (!mounted) return;

      await _loadDatabaseInfo();
      if (!mounted) return;

      _showRefreshOutcome(report);
    } catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, 'Erreur lors de l\'actualisation : $e');
      }
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  /// Traduit le bilan d'une passe en un message. Une passe partielle ne doit
  /// jamais s'annoncer comme un succès : c'est le cas où l'utilisateur cherche
  /// un son qu'il vient d'ajouter et ne le trouve pas.
  void _showRefreshOutcome(SyncPassReport report) {
    if (report.authExpired) {
      showCopyableSnackBar(
        context,
        'Session Google expirée — utilisez « Renouveler » ci-dessus.',
      );
      return;
    }
    if (report.error != null) {
      showCopyableSnackBar(
        context,
        'Erreur lors de l\'actualisation : ${report.error}',
      );
      return;
    }
    if (report.localMode) {
      AppSnackBar.show(
        context,
        'Mode local — passez en mode connecté pour actualiser',
      );
      return;
    }
    if (report.offline) {
      AppSnackBar.show(context, 'Hors ligne — actualisation impossible');
      return;
    }
    if (report.skipped > 0) {
      showCopyableSnackBar(
        context,
        '${report.skipped} bibliothèque(s) non actualisée(s) — '
        'réessayez ou consultez les journaux.',
      );
      return;
    }
    AppSnackBar.show(
      context,
      'Bibliothèque(s) Drive actualisée(s)',
      duration: const Duration(seconds: 2),
    );
  }

  /// Régénère l'enveloppe waveform de tous les sons déjà en cache
  /// local (aucun téléchargement Drive forcé — un son non encore mis en
  /// cache est simplement ignoré). Utile après une amélioration de
  /// l'algorithme d'extraction (cf. `kWaveformOversample`) : les enveloppes
  /// déjà stockées ne sont jamais re-calculées automatiquement, seuls les
  /// nouveaux imports en bénéficient sans action explicite.
  Future<void> _regenerateCachedWaveforms() async {
    if (_isRegeneratingWaveforms) return;

    final sounds = await _repository.getAllSounds();
    if (sounds.isEmpty) {
      if (mounted) {
        AppSnackBar.show(context, 'Aucun son dans la bibliothèque');
      }
      return;
    }

    setState(() {
      _isRegeneratingWaveforms = true;
      _waveformRegenDone = 0;
      _waveformRegenTotal = sounds.length;
    });

    var regenerated = 0;
    var skipped = 0;
    var failed = 0;
    var aborted = false;

    for (final sound in sounds) {
      if (!mounted) return;
      try {
        final path = await widget.libraryRepository.resolvePlayablePath(
          sound,
          downloadIfNeeded: false,
        );
        final probe = await extractWaveform(path);
        switch (probe.status) {
          case WaveformProbeStatus.success:
            await _repository.persistWaveformProbe(sound.id, probe);
            regenerated++;
          case WaveformProbeStatus.unsupported:
            await _repository.persistWaveformProbe(sound.id, probe);
            failed++;
          case WaveformProbeStatus.transient:
            // Moteur audio non initialisé : tous les sons suivants
            // échoueraient pareil, inutile de continuer la passe.
            aborted = true;
        }
      } catch (_) {
        // Hors cache local (ou fichier illisible) : ignoré sans mémoriser
        // d'échec « format » — on ne force pas de téléchargement Drive ici.
        skipped++;
      }
      if (aborted) break;
      if (mounted) setState(() => _waveformRegenDone++);
    }

    if (!mounted) return;
    setState(() => _isRegeneratingWaveforms = false);
    final summary = aborted
        ? 'Moteur audio non prêt — $regenerated régénérée(s) avant interruption.'
        : '$regenerated régénérée(s), $skipped ignorée(s) (hors cache), '
              '$failed échec(s) de format.';
    AppSnackBar.show(context, summary);
  }

  Future<void> _resolveSyncConflict(domain.Library library) async {
    setState(() => _isSyncBusy = true);
    try {
      await showSyncConflictDialog(
        context: context,
        syncController: widget.syncController,
        library: library,
        onResolved: _loadDatabaseInfo,
      );
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  Future<void> _toggleAutoDownload(domain.Library library) async {
    await widget.libraryRepository.setAutoDownload(
      library,
      value: !library.autoDownload,
    );
    if (mounted) await _loadDatabaseInfo();
  }

  Future<void> _downloadAllLibraryAudio(domain.Library library) async {
    // La progression et l'annulation vivent dans le repository : l'écran ne fait
    // que déclencher la passe et se rafraîchit via [_onLibraryRepositoryChanged].
    // Le téléchargement continue même si l'écran est fermé entre-temps.
    try {
      await widget.libraryRepository.downloadAllLibraryAudio(library: library);
    } finally {
      // Rafraîchit l'indicateur hors-ligne (téléchargement complet ou annulé).
      await _refreshOfflineCount(library);
    }
  }

  Future<void> _confirmRemoveDriveLibrary(domain.Library library) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Retirer l\'élément indexé'),
          content: Text(
            'Retirer le dossier Drive « ${library.name} » ? '
            'Les sons importés depuis cet élément seront supprimés '
            'de la bibliothèque et retirés des scènes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Retirer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await widget.libraryRepository.removeLibrary(library);
      _indexingProgress.remove(_driveProgressKey(library.id));

      if (mounted) {
        AppSnackBar.show(
          context,
          'Dossier Drive retiré avec succès',
          duration: const Duration(seconds: 2),
        );
      }

      await _loadDatabaseInfo();
    } catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, 'Erreur lors de la suppression : $e');
      }
    }
  }

  Future<void> _removeWatchedPath(db.WatchedPath watchedPath) async {
    try {
      final watchedPathEntity = domain.WatchedPath(
        id: watchedPath.id,
        path: watchedPath.path,
        isDirectory: watchedPath.isDirectory,
        addedAt: watchedPath.addedAt,
      );

      await _repository.removeWatchedPath(watchedPathEntity);

      _indexingProgress.remove(_normalizeWatchedPath(watchedPath.path));

      if (mounted) {
        AppSnackBar.show(
          context,
          'Chemin retiré avec succès',
          duration: const Duration(seconds: 2),
        );
      }

      await _loadDatabaseInfo();
    } catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, 'Erreur lors de la suppression: $e');
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  /// Détail complet de l'état de la base, dont le chemin copiable — ouvert au
  /// tap sur l'icône « i » des éléments indexés.
  Future<void> _showDatabaseStateDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AppFormDialog(
          title: 'État de la base de données',
          width: 460,
          onClose: () => Navigator.of(dialogContext).pop(),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Nombre total de sons', '${_sounds.length}'),
              const SizedBox(height: 8),
              _buildInfoRow(
                'Taille de la base de données',
                _formatBytes(_dbSize),
              ),
              const SizedBox(height: 8),
              _buildInfoRow(
                'Chemin de la base de données',
                _dbPath,
                isPath: true,
              ),
            ],
          ),
        );
      },
    );
  }
}
