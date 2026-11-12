// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../settings_screen.dart';

/// Actions sur les bibliothèques : retrait, actualisation Drive, mises à jour.
/// Méthodes de [_SettingsScreenState] extraites via extension dans le même `part`.
extension _SettingsLibraryActions on _SettingsScreenState {
  Future<void> _confirmRemoveWatchedPath(db.WatchedPath watchedPath) async {
    final label = _labelsForWatchedPath(watchedPath).title;
    final type = SafDirectoryBridge.isSafTreeUri(watchedPath.path)
        ? 'dossier cloud'
        : 'dossier local';

    final confirmed = await showAppDialog<bool>(
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

  /// Geste « tirer pour actualiser » de la page. Sur mobile, avec une
  /// bibliothèque Drive, il fait la même chose que le bouton de la section
  /// (`_refreshFromDrive`, donc la même séquence du coordinateur). Ailleurs
  /// — desktop, ou rien à synchroniser — il garde son rôle d'origine : relire
  /// l'état de la base.
  Future<void> _onPullToRefresh() {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final hasDriveLibrary = _libraries.any(
      (library) => library.isConnectedToDrive,
    );
    if (!isMobile || !hasDriveLibrary) return _loadDatabaseInfo();
    // Une passe est déjà en cours (le bouton est grisé pour la même raison) :
    // `refreshNow` la rejoindrait, mais le geste n'a alors rien à lancer.
    if (_refreshingLibraryIds.isNotEmpty) return Future<void>.value();
    return _refreshFromDrive();
  }

  /// Actualisation manuelle : délègue au coordinateur, qui rejoue exactement la
  /// séquence de lancement (delta d'abord, scan complet en repli, indexation
  /// AVANT le pull). Cet écran n'orchestre plus rien lui-même — deux séquences
  /// de synchronisation en parallèle finiraient par diverger, et c'est ici que
  /// la divergence était déjà réelle : le bouton tirait avant d'indexer et
  /// rescannait systématiquement.
  ///
  /// [only] limite la passe à une bibliothèque (clic sur sa ligne) ; sans lui,
  /// toutes les bibliothèques Drive sont actualisées.
  Future<void> _refreshFromDrive({domain.Library? only}) async {
    // Gestes grisés pendant une passe : ce garde couvre les appels qui ne
    // passent pas par un widget désactivé.
    if (_refreshingLibraryIds.isNotEmpty) return;
    final targets = {
      for (final library in _libraries)
        if (library.isConnectedToDrive &&
            (only == null || library.id == only.id))
          library.id,
    };
    if (targets.isEmpty) {
      if (mounted) {
        AppSnackBar.show(context, 'Aucun dossier Drive indexé');
      }
      return;
    }

    _passOutcomesTimer?.cancel();
    setState(() {
      _refreshingLibraryIds = targets;
      // Seuls les bilans des bibliothèques visées sont remplacés : l'échec d'une
      // autre, resté affiché pour être lu, ne disparaît pas.
      _passOutcomes = {
        for (final entry in _passOutcomes.entries)
          if (!targets.contains(entry.key)) entry.key: entry.value,
      };
      _passStages.clear();
    });
    try {
      final report = await widget.autoSyncCoordinator.refreshNow(
        only: only,
        onStage: (library, stage) {
          if (!mounted) return;
          setState(() => _passStages[library.id] = stage);
        },
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

      _showPassOutcomes(report);
      _showRefreshOutcome(report);
    } catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, 'Erreur lors de l\'actualisation : $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _refreshingLibraryIds = const {};
          _passStages.clear();
        });
      }
    }
  }

  /// Affiche le bilan de chaque bibliothèque sur sa ligne. Les changements
  /// s'effacent au bout de quelques secondes (la ligne revient à « Synchronisé
  /// à… ») ; un échec reste jusqu'à la passe suivante, sans quoi il
  /// disparaîtrait avant d'avoir été lu.
  void _showPassOutcomes(SyncPassReport report) {
    setState(() => _passOutcomes = {..._passOutcomes, ...report.libraries});
    _passOutcomesTimer?.cancel();
    _passOutcomesTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      setState(() {
        _passOutcomes = {
          for (final entry in _passOutcomes.entries)
            if (entry.value.failed) entry.key: entry.value,
        };
      });
    });
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
        'Mode hors ligne — passez en mode Connecté pour actualiser',
      );
      return;
    }
    if (report.offline) {
      AppSnackBar.show(context, 'Hors ligne — actualisation impossible');
      return;
    }
    // Bibliothèque non actualisée : le message vit sur sa ligne (voir
    // [_showPassOutcomes]), avec « Réessayer » — un toast global ne dirait pas
    // laquelle. Succès : la ligne affiche ce qui a changé puis sa nouvelle date.
  }

  Future<void> _resolveSyncConflict(domain.Library library) async {
    await showSyncConflictDialog(
      context: context,
      syncController: widget.syncController,
      library: library,
      onResolved: _loadDatabaseInfo,
    );
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
    final confirmed = await showAppDialog<bool>(
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
      // Ses sons disparaissent et ses scènes deviennent locales : l'index de
      // recherche et les scènes en mémoire doivent être relus.
      widget.syncController.onLibraryMerged?.call();

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
    await showAppDialog<void>(
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
