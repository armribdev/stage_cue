// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../settings_screen.dart';

/// Sections de l'écran : audio, Drive, maintenance, mise à jour.
/// Méthodes de [_SettingsScreenState] extraites via extension dans le même `part`.
extension _SettingsSections on _SettingsScreenState {

  // Pas de Card : la direction "Console Linear" pose les sections à plat
  // (label + séparateur) plutôt qu'en cartes empilées façon Material.
  Widget _buildSettingsSectionCard({
    required Widget title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [title, const SizedBox(height: 14), child],
    );
  }

  Widget _sectionDivider() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Divider(height: 1),
  );

  Widget _buildSectionTitleRow({
    required IconData icon,
    required String title,
    List<Widget>? trailing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(title.toUpperCase(), style: AppTextStyles.sectionLabel(context)),
        if (trailing != null) ...[const Spacer(), ...trailing],
      ],
    );
  }

  /// Sélecteur du mode réseau : boutons segmentés (3 choix) + description du
  /// mode courant. Plus léger qu'un dropdown pour un réglage à faible cardinalité.
  Widget _buildConnectivityModeSelector() {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.appPreferences.connectivityMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mode réseau',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ConnectivityMode>(
            // Ordre d'affichage : « Live » (mode par défaut, cas d'usage
            // principal en scène) en premier, puis Connecté et Hors ligne.
            segments:
                const [
                      ConnectivityMode.liveOffline,
                      ConnectivityMode.connected,
                      ConnectivityMode.offline,
                    ]
                    .map(
                      (mode) => ButtonSegment<ConnectivityMode>(
                        value: mode,
                        label: Text(mode.label),
                      ),
                    )
                    .toList(),
            selected: {selected},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (selection) => unawaited(
              widget.appPreferences.setConnectivityMode(selection.first),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          selected.description,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// Section « Audio » : choix du périphérique de sortie de pré-écoute (cue).
  /// Windows uniquement — permet d'auditionner un son sur un casque séparé
  /// pendant que la sortie « salle » reste sur le device système.
  Widget _buildAudioSection() {
    final scheme = Theme.of(context).colorScheme;
    return _buildSettingsSectionCard(
      title: _buildSectionTitleRow(
        icon: Icons.headphones_outlined,
        title: 'Audio',
        trailing: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            visualDensity: VisualDensity.compact,
            tooltip: 'Rafraîchir la liste des périphériques',
            icon: _isLoadingCueDevices
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isLoadingCueDevices ? null : () => _loadCueDevices(),
          ),
        ],
      ),
      child: ListenableBuilder(
        listenable: widget.appPreferences,
        builder: (context, _) {
          final selectedId = widget.appPreferences.cueOutputDeviceId;
          // Le device persisté peut être absent de la liste (débranché) : on
          // l'ajoute pour que le Dropdown ait toujours une valeur valide.
          final knownIds = _cueDevices.map((d) => d.id).toSet();
          final missingSelected =
              selectedId != null && !knownIds.contains(selectedId);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sortie de pré-écoute (cue)',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: DropdownButtonFormField<String?>(
                  initialValue: selectedId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Défaut système'),
                    ),
                    for (final device in _cueDevices)
                      DropdownMenuItem<String?>(
                        value: device.id,
                        child: Text(
                          device.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (missingSelected)
                      DropdownMenuItem<String?>(
                        value: selectedId,
                        child: const Text(
                          'Périphérique indisponible',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => unawaited(_setCueDevice(value)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                selectedId == null
                    ? 'Les pré-écoutes sortent sur le périphérique par défaut, '
                          'comme le reste de l\'application.'
                    : 'Les pré-écoutes sortent sur ce périphérique, tandis que '
                          'les pads et la régie restent sur la sortie système.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
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
          final scheme = Theme.of(context).colorScheme;
          final syncState = widget.syncController.state;
          final authExpired = isDriveAuthExpired(syncState);
          return _buildSettingsSectionCard(
            title: _buildSectionTitleRow(
              icon: Icons.cloud_outlined,
              title: 'Drive',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDriveAccountHeader(
                  syncState: syncState,
                  authExpired: authExpired,
                ),
                // L'activité de synchro (syncing / synced / conflit / erreur)
                // est désormais portée par la pastille de la barre de cette
                // page ; inutile de la redoubler ici sous le compte.
                const SizedBox(height: 12),
                Text(
                  'Téléchargement automatique',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                CompactSwitchListTile(
                  title: const Text('Sons ajoutés à un pad'),
                  subtitle: Text(
                    'Si connecté à Drive, les variantes sont récupérées dès l\'ajout.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  value: widget.appPreferences.autoDownloadPadSounds,
                  onChanged: (value) => unawaited(
                    widget.appPreferences.setAutoDownloadPadSounds(value),
                  ),
                ),
                CompactSwitchListTile(
                  title: const Text(
                    'Nouveaux dossiers Drive (tout le contenu)',
                  ),
                  subtitle: Text(
                    'À l\'ajout d\'un dossier Drive, télécharge les fichiers pour '
                    'classer correctement chaque son à l\'indexation.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  value: widget.appPreferences.autoDownloadDriveByDefault,
                  onChanged: (value) => unawaited(
                    widget.appPreferences.setAutoDownloadDriveByDefault(value),
                  ),
                ),
                const Divider(height: 24),
                _buildConnectivityModeSelector(),
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
              onRefresh: _loadDatabaseInfo,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDriveSection(),
                    _sectionDivider(),
                    if (CueAudioService.isSupported) ...[
                      _buildAudioSection(),
                      _sectionDivider(),
                    ],
                    SettingsIndexedFoldersSection(
                      items: _indexedFolderItems(),
                      labelsForItem: _labelsForItem,
                      progressForItem: _progressForItem,
                      offlineCounts: _offlineCounts,
                      libraryRepository: widget.libraryRepository,
                      soundCount: _sounds.length,
                      dbSizeLabel: _formatBytes(_dbSize),
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
                    ),
                    _sectionDivider(),
                    _buildMaintenanceCard(),
                    if (Platform.isWindows) ...[
                      _sectionDivider(),
                      _buildUpdateCard(),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  /// Carte « Maintenance » : actions ponctuelles sur les données déjà
  /// indexées, distinctes du scan de nouveaux dossiers (section Éléments indexés).
  Widget _buildMaintenanceCard() {
    final scheme = Theme.of(context).colorScheme;
    return _buildSettingsSectionCard(
      title: _buildSectionTitleRow(
        icon: Icons.build_outlined,
        title: 'Maintenance',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Régénérer les waveforms des sons déjà en cache local, '
            'avec l\'algorithme d\'extraction courant. N\'affecte pas les sons '
            'non encore téléchargés.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          if (_isRegeneratingWaveforms) ...[
            const SizedBox(height: 8),
            Text(
              'En cours… $_waveformRegenDone / $_waveformRegenTotal',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed:
                _isRegeneratingWaveforms ? null : _regenerateCachedWaveforms,
            icon: _isRegeneratingWaveforms
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 18),
            label: const Text('Régénérer les waveforms en cache'),
          ),
        ],
      ),
    );
  }

  /// Carte « Mise à jour » : version courante + vérification manuelle.
  /// Windows uniquement — seule plateforme avec un installeur auto-updatable
  /// (voir `windows/installer/stage_cue.iss`).
  Widget _buildUpdateCard() {
    final scheme = Theme.of(context).colorScheme;
    return _buildSettingsSectionCard(
      title: _buildSectionTitleRow(
        icon: Icons.system_update_outlined,
        title: 'Mise à jour',
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _appVersion == null
                  ? 'Version…'
                  : 'Version installée : $_appVersion',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _isCheckingForUpdate ? null : _checkForUpdatesManually,
            icon: _isCheckingForUpdate
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 18),
            label: const Text('Vérifier les mises à jour'),
          ),
        ],
      ),
    );
  }


  /// Bouton « Actualiser depuis Drive » : relit les dossiers Drive liés et
  /// indexe les fichiers ajoutés directement sur Drive. Absent tant qu'aucune
  /// bibliothèque Drive n'est connectée ; devient un indicateur d'activité
  /// pendant l'actualisation.
  Widget? _buildDriveRefreshAction() {
    final hasDriveLibrary =
        _libraries.any((library) => library.isConnectedToDrive);
    if (!hasDriveLibrary) return null;

    if (_isSyncBusy) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return BoxedIconButton(
      icon: Icons.refresh,
      tooltip: 'Actualiser depuis Drive',
      onPressed: _refreshAllFromDrive,
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isPath = false}) {
    final valueStyle = TextStyle(
      color: isPath ? Theme.of(context).colorScheme.onSurfaceVariant : null,
      fontSize: isPath ? 12 : null,
    );

    Widget valueWidget = Text(value, style: valueStyle);
    if (isPath && value.isNotEmpty) {
      valueWidget = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (!mounted) return;
            AppSnackBar.show(
              context,
              'Chemin copié',
              duration: const Duration(seconds: 2),
            );
          },
          child: Text(value, style: valueStyle),
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
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(child: valueWidget),
      ],
    );
  }
}
