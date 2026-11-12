// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../settings_screen.dart';

/// Sections de l'écran : audio, Drive, maintenance, mise à jour.
/// Méthodes de [_SettingsScreenState] extraites via extension dans le même `part`.
/// Squelette, lignes et boutons communs : `widgets/settings_layout.dart`.
extension _SettingsSections on _SettingsScreenState {
  /// Interrupteur de connexion : le mode réseau n'ayant que deux valeurs
  /// ([décision 0037](../../../../../docs/decisions/0037-mode-reseau-binaire-spectacle-masque-les-pads.md)),
  /// c'est un interrupteur, au même rang que les réglages de téléchargement de
  /// la section Drive dont il est le maître. Le sous-titre dit ce que le mode
  /// courant implique.
  Widget _buildConnectionSwitch() {
    final mode = widget.appPreferences.connectivityMode;
    return SettingsRow.toggle(
      title: 'Connexion réseau',
      description: mode.description,
      value: mode == ConnectivityMode.connected,
      onChanged: (connected) => unawaited(
        widget.appPreferences.setConnectivityMode(
          connected ? ConnectivityMode.connected : ConnectivityMode.offline,
        ),
      ),
    );
  }

  /// Section « Audio » : choix du périphérique de sortie de pré-écoute (cue).
  /// Windows uniquement — permet d'auditionner un son sur un casque séparé
  /// pendant que la sortie « salle » reste sur le device système.
  Widget _buildAudioSection() {
    return SettingsSection(
      icon: AppIcons.headphones,
      title: 'Audio',
      trailing: [
        BoxedIconButton(
          icon: _isLoadingCueDevices ? null : AppIcons.refresh,
          tooltip: 'Rafraîchir la liste des périphériques',
          framed: false,
          compact: true,
          onPressed: _isLoadingCueDevices ? null : () => _loadCueDevices(),
          child: _isLoadingCueDevices
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
      ],
      child: ListenableBuilder(
        listenable: widget.appPreferences,
        builder: (context, _) {
          final selectedId = widget.appPreferences.cueOutputDeviceId;
          // Le device persisté peut être absent de la liste (débranché) :
          // `_loadCueDevices` repasse alors la préférence sur « Désactivé ». En
          // attendant (image intermédiaire), le menu affiche déjà « Désactivé »
          // pour garder une valeur valide, sauf pendant la toute première
          // énumération où l'on ne sait encore rien du casque.
          final knownIds = _cueDevices.map((d) => d.id).toSet();
          final searchingSelected =
              selectedId != null &&
              !_cueDevicesLoaded &&
              !knownIds.contains(selectedId);
          final dropdownValue =
              searchingSelected || knownIds.contains(selectedId)
              ? selectedId
              : null;
          // Énumération terminée et rien d'autre que la sortie de la salle :
          // un menu vide serait trompeur, on l'annonce à la place.
          final noExtraOutput = _cueDevicesLoaded && _cueDevices.isEmpty;
          final room = CueAudioService.instance.excludedRoomLabel;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsRow(
                title: 'Sortie de pré-écoute (cue)',
                description: noExtraOutput || dropdownValue == null
                    ? 'Sans casque, les pré-écoutes sortent en salle '
                          '(désactivées en Mode Spectacle).'
                    : 'Les pré-écoutes sortent sur ce casque, jamais en salle.',
              ),
              const SizedBox(height: AppSpacing.xs),
              if (noExtraOutput)
                const SettingsNote(
                  'Aucune sortie supplémentaire détectée. Branchez un casque '
                  'puis actualisez la liste.',
                )
              else
                AppSelect<String?>(
                  value: dropdownValue,
                  leadingIcon: AppIcons.headphones,
                  options: [
                    // « Désactivé » = aucun casque (valeur `null`). Ce n'est
                    // pas la sortie par défaut du système proposée comme
                    // casque : celle-ci est la salle, elle reste exclue.
                    const AppSelectOption<String?>(
                      value: null,
                      label: 'Désactivé',
                    ),
                    for (final device in _cueDevices)
                      AppSelectOption<String?>(
                        value: device.id,
                        label: device.label,
                      ),
                    if (searchingSelected)
                      AppSelectOption<String?>(
                        value: selectedId,
                        label: 'Recherche du périphérique…',
                      ),
                  ],
                  onChanged: (value) => unawaited(_setCueDevice(value)),
                ),
              if (room != null) ...[
                const SizedBox(height: AppSpacing.sm),
                SettingsNote(
                  '« $room » est la sortie par défaut de Windows (la salle) : '
                  'elle n\'est pas proposée comme casque.',
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildDriveSection() {
    return SectionContextAnchor(
      onAttached: (ctx) => _driveSectionContext = ctx,
      onDetached: (ctx) {
        if (identical(_driveSectionContext, ctx)) {
          _driveSectionContext = null;
        }
      },
      child: ListenableBuilder(
        listenable: Listenable.merge([
          widget.libraryRepository,
          widget.syncController,
          widget.appPreferences,
        ]),
        builder: (context, _) {
          final syncState = widget.syncController.state;
          final authExpired = isDriveAuthExpired(syncState);
          return SettingsSection(
            icon: AppIcons.cloud,
            title: 'Drive',
            // Dernière synchro, indexation et conflit vivent sur la ligne de
            // chaque bibliothèque (« Éléments indexés »), avec le bouton
            // d'actualisation ; ici, le compte et les réglages réseau.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDriveAccountHeader(
                  syncState: syncState,
                  authExpired: authExpired,
                ),
                const SizedBox(height: AppSpacing.sm),
                // Interrupteur maître : sans connexion, ni synchro ni
                // téléchargement, quels que soient les réglages ci-dessous.
                _buildConnectionSwitch(),
                SettingsRow.toggle(
                  title: 'Télécharger les sons ajoutés à un pad',
                  description:
                      'Si connecté à Drive, les variantes sont récupérées dès '
                      'l\'ajout.',
                  value: widget.appPreferences.autoDownloadPadSounds,
                  onChanged: (value) => unawaited(
                    widget.appPreferences.setAutoDownloadPadSounds(value),
                  ),
                ),
                SettingsRow.toggle(
                  title: 'Télécharger les nouveaux dossiers Drive',
                  description:
                      'À l\'ajout d\'un dossier, récupère tous ses fichiers '
                      'pour classer correctement chaque son à l\'indexation.',
                  value: widget.appPreferences.autoDownloadDriveByDefault,
                  onChanged: (value) => unawaited(
                    widget.appPreferences.setAutoDownloadDriveByDefault(value),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSettingsBody() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          alignment: Alignment.topCenter,
          children: [...previousChildren, ?currentChild],
        );
      },
      child: _isLoading
          ? const SettingsLoadingView(key: ValueKey('settings-loading'))
          : RefreshIndicator(
              key: const ValueKey('settings-content'),
              onRefresh: _onPullToRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: separatedSettingsSections([
                    _buildDriveSection(),
                    // « Éléments indexés » suit directement Drive : ses lignes
                    // sont les bibliothèques de ce compte, et le réglage de
                    // connexion juste au-dessus décide de leur synchro.
                    ListenableBuilder(
                      listenable: Listenable.merge([
                        widget.syncController,
                        widget.appPreferences,
                      ]),
                      builder: (context, _) {
                        final syncState = widget.syncController.state;
                        return SettingsIndexedFoldersSection(
                          items: _indexedFolderItems(),
                          labelsForItem: _labelsForItem,
                          progressForItem: _progressForItem,
                          offlineCounts: _offlineCounts,
                          libraryRepository: widget.libraryRepository,
                          soundCount: _sounds.length,
                          dbSizeLabel: _formatBytes(_dbSize),
                          networkAllowed:
                              widget.appPreferences.allowsNetworkSync,
                          autoSyncPaused:
                              widget.syncController.isAutoSyncPaused,
                          refreshingLibraryIds: _refreshingLibraryIds,
                          passOutcomes: _passOutcomes,
                          passStages: _passStages,
                          conflictLibraryId:
                              syncState.status == SyncStatus.conflict
                              ? syncState.conflictLibraryId
                              : null,
                          onRefresh: () => unawaited(_refreshFromDrive()),
                          onRefreshLibrary: (library) =>
                              unawaited(_refreshFromDrive(only: library)),
                          onResolveConflict: (library) =>
                              unawaited(_resolveSyncConflict(library)),
                          onAddFolder: _onAddFolderPressed,
                          onShowDatabaseState: () =>
                              unawaited(_showDatabaseStateDialog()),
                          onRemoveLocal: (path) =>
                              unawaited(_confirmRemoveWatchedPath(path)),
                          onRemoveDrive: (library) =>
                              unawaited(_confirmRemoveDriveLibrary(library)),
                          onDownloadAll: (library) =>
                              unawaited(_downloadAllLibraryAudio(library)),
                          onToggleAutoDownload: (library) =>
                              unawaited(_toggleAutoDownload(library)),
                        );
                      },
                    ),
                    if (CueAudioService.isSupported) _buildAudioSection(),
                    if (widget.autoTagPack != null)
                      _buildAutoTagSection(widget.autoTagPack!),
                    _buildMaintenanceSection(),
                  ]),
                ),
              ),
            ),
    );
  }

  /// Section « Maintenance », repliée par défaut : les outils qu'on ouvre
  /// rarement (recalcul des volumes auto, journal) ne chargent pas l'écran.
  Widget _buildMaintenanceSection() {
    final scheme = Theme.of(context).colorScheme;
    final expanded = _maintenanceExpanded;
    // Replié, un travail long en cours (recalcul, export) reste signalé.
    final busy = _isAutoVolumeBusy || _isDiagnosticBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          child: InkWell(
            borderRadius: AppRadius.radiusSm,
            onTap: _toggleMaintenance,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: SettingsSectionHeader(
                icon: AppIcons.tune,
                title: 'Maintenance',
                trailing: [
                  if (busy && !expanded) ...[
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Icon(
                    expanded ? AppIcons.chevronUp : AppIcons.chevronDown,
                    size: AppIconSize.sm,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildVolumeRow(),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                        child: Divider(height: 1),
                      ),
                      _buildDiagnosticRows(),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  void _toggleMaintenance() {
    setState(() => _maintenanceExpanded = !_maintenanceExpanded);
    // La taille du journal grossit pendant la session : relue à chaque
    // ouverture, pas à chaque redessin.
    if (_maintenanceExpanded) unawaited(_loadLogDiskSize());
  }

  /// Libellé muet + valeur : état de l'appareil, dialogue de la base,
  /// journal. Un chemin est copiable d'un clic et en police technique.
  Widget _buildInfoRow(String label, String value, {bool isPath = false}) {
    final scheme = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.bodySmall ?? const TextStyle();
    final valueStyle = isPath
        ? AppFonts.monoStyle(base.copyWith(color: scheme.onSurfaceVariant))
        : base.copyWith(color: scheme.onSurface);

    Widget valueWidget = Text(value, style: valueStyle);
    if (isPath && value.isNotEmpty) {
      final copied = _confirmedAction == 'copy-path:$value';
      valueWidget = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (!mounted) return;
            _flashConfirmation('copy-path:$value');
          },
          child: Text(copied ? 'Chemin copié ✓' : value, style: valueStyle),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 180,
          child: Text(
            label,
            style: base.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(child: valueWidget),
      ],
    );
  }
}
