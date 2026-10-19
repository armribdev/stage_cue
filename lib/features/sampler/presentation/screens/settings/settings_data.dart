// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../settings_screen.dart';

/// Chargement des données (base, périphériques cue, version) et défilement.
/// Méthodes de [_SettingsScreenState] extraites via extension dans le même `part`.
extension _SettingsData on _SettingsScreenState {

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _appVersion = packageInfo.version);
  }

  /// Énumère les périphériques de sortie de pré-écoute (cue).
  Future<void> _loadCueDevices() async {
    if (!CueAudioService.isSupported) return;
    setState(() => _isLoadingCueDevices = true);
    final devices = await CueAudioService.instance.refreshDevices();
    if (!mounted) return;
    setState(() {
      _cueDevices = devices;
      _isLoadingCueDevices = false;
    });
  }

  /// Change le device cue : persistance + application immédiate au moteur.
  Future<void> _setCueDevice(String? deviceId) async {
    CueAudioService.instance.setSelectedDevice(deviceId);
    await widget.appPreferences.setCueOutputDeviceId(deviceId);
  }

  Future<void> _startInitialLoad() async {
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) {
      return;
    }
    unawaited(_loadDatabaseInfo());
  }

  void _initializeRepository() {
    _repository = SoundRepository.fromDatabase(widget.database);
  }

  void _scrollToDriveSectionIfNeeded() {
    if (!_shouldScrollToDriveSection) return;
    _shouldScrollToDriveSection = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToDriveSection();
    });
  }

  void _scrollToDriveSection() {
    final sectionContext = _driveSectionContext;
    if (sectionContext == null || !sectionContext.mounted) return;
    Scrollable.ensureVisible(
      sectionContext,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Tap sur la pastille de synchro (barre Paramètres) : résout un conflit s'il
  /// y en a un, sinon défile jusqu'à la section Drive.
  Future<void> _onSyncPillTap() async {
    if (widget.syncController.state.status == SyncStatus.conflict) {
      await resolveSyncConflictFromPill(
        context: context,
        syncController: widget.syncController,
        libraryRepository: widget.libraryRepository,
        onResolved: () async {
          if (!mounted) return;
          await _loadDatabaseInfo();
        },
      );
      return;
    }
    _scrollToDriveSection();
  }

  Future<void> _reloadWatchedPaths() async {
    final watchedPaths = await widget.database
        .select(widget.database.watchedPaths)
        .get();

    if (mounted) {
      setState(() {
        _watchedPaths = watchedPaths;
      });
    }
  }

  Future<void> _loadDatabaseInfo() async {
    if (!mounted) return;
    final showSkeleton = _isInitialLoad;
    if (showSkeleton) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      if (isDriveAuthExpired(widget.syncController.state) ||
          widget.libraryRepository.requiresInteractiveReconnect) {
        await widget.libraryRepository.invalidateAuthSession();
      } else {
        await widget.libraryRepository.reconnectSilently();
      }

      // Charger les dossiers locaux surveillés et les bibliothèques Drive
      final watchedPaths = await widget.database
          .select(widget.database.watchedPaths)
          .get();
      final libraries = await widget.libraryRepository.getLibraries();

      // Charger tous les sons de la base de données
      final sounds = await widget.database.select(widget.database.sounds).get();

      // Obtenir le chemin de la base de données (source de vérité unique)
      final dbFile = await db.resolveDatabaseFile();

      int dbSize = 0;
      if (await dbFile.exists()) {
        dbSize = await dbFile.length();
      }

      if (!mounted) return;
      setState(() {
        _watchedPaths = watchedPaths;
        _libraries = libraries;
        _sounds = sounds;
        _dbPath = dbFile.path;
        _dbSize = dbSize;
        _isLoading = false;
        _isInitialLoad = false;
      });
      _scrollToDriveSectionIfNeeded();
      unawaited(_loadSafFolderInfo());
      unawaited(_loadOfflineCounts());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isInitialLoad = false;
      });
      showCopyableSnackBar(context, 'Erreur lors du chargement: $e');
    }
  }

  /// Rafraîchit uniquement le décompte de sons et la taille de la base
  /// (résumé affiché en pied de section), sans recharger dossiers surveillés,
  /// bibliothèques ou infos SAF — pour rester léger quand appelé en rafale
  /// pendant une indexation.
  Future<void> _refreshDatabaseSummary() async {
    final sounds = await widget.database.select(widget.database.sounds).get();
    final dbFile = await db.resolveDatabaseFile();

    int dbSize = 0;
    if (await dbFile.exists()) {
      dbSize = await dbFile.length();
    }

    if (!mounted) return;
    setState(() {
      _sounds = sounds;
      _dbSize = dbSize;
    });
  }

  /// Déclenche [_refreshDatabaseSummary] pendant une indexation en cours, en
  /// limitant la fréquence des requêtes DB (au plus une toutes les 400 ms),
  /// mais toujours à la fin (`isComplete`) pour garantir un état final exact.
  void _maybeRefreshDatabaseSummaryLive(IndexingProgress progress) {
    final now = DateTime.now();
    final last = _lastLiveSummaryRefresh;
    final shouldRefresh =
        progress.isComplete ||
        last == null ||
        now.difference(last) > const Duration(milliseconds: 400);
    if (!shouldRefresh) return;
    _lastLiveSummaryRefresh = now;
    unawaited(_refreshDatabaseSummary());
  }
}
