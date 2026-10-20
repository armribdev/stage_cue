part of 'music_preview_panel.dart';

class _MusicRegieDrawer extends StatefulWidget {
  /// Espacements de la barre réduite (bandeau plat, une seule ligne) et du
  /// panneau avancé (queue + à l'antenne détaillé).
  ///
  /// Le chevron (ouvrir/fermer) n'a jamais de ligne à lui : il se glisse
  /// toujours dans une rangée de contrôles déjà plus haute que lui (la barre
  /// réduite, la rangée « à l'antenne » en colonne unique, ou sa propre
  /// colonne centrale en deux colonnes — voir _buildCompactBar et
  /// _buildModeBody), donc ces paddings n'ont pas à lui réserver de place.
  static const _compactDrawerPadding = EdgeInsets.fromLTRB(16, 10, 16, 10);
  static const _advancedDrawerPadding = EdgeInsets.fromLTRB(16, 14, 16, 16);

  /// Largeurs minimales de chaque moitié du panneau avancé (contrôles à
  /// gauche, file de passage à droite) — en dessous du total, on repasse en
  /// colonne unique (contrôles puis file, empilés).
  static const _onAirColumnMinWidth = 260.0;
  static const _queueColumnMinWidth = 260.0;
  static const _advancedColumnGap = 16.0;
  static const _centerChevronColumnWidth = 32.0;
  static const _twoColumnMinWidth =
      _onAirColumnMinWidth +
      _advancedColumnGap +
      _centerChevronColumnWidth +
      _advancedColumnGap +
      _queueColumnMinWidth;

  final SamplerState state;
  final double musicVolume;
  final PadItem? Function(int padId) resolveMusicPad;
  final bool isAdvanced;
  final bool isDesktop;
  final VoidCallback onModeToggle;
  final VoidCallback onChooseMusic;
  final VoidCallback onChooseMusicToPlay;
  final void Function({required bool isPlaying, required bool hasCurrent})
  onPauseToggle;
  final void Function({required bool isPlaying, required bool hasQueue})
  onSkipNext;
  final VoidCallback? onEjectMusic;
  final ValueChanged<int>? onRemoveFromQueue;
  final void Function(int oldIndex, int newIndex)? onReorderMusicQueue;
  final ValueChanged<double>? onMusicVolumeChanged;
  final ValueChanged<Duration>? onSeekMusic;
  final double ambianceVolume;
  final VoidCallback? onChooseAmbiance;
  final VoidCallback? onStopAmbiance;
  final ValueChanged<double>? onAmbianceVolumeChanged;
  final Duration? selectedTransitionDuration;
  final bool transitionDurationLocked;
  final ValueChanged<Duration> onTransitionOptionTapped;
  final ValueChanged<Duration> onTransitionOptionLongPressed;
  final _MusicTransitionKind? activeTransitionKind;
  final Animation<double>? transitionProgress;
  final Animation<double>? transitionBlinkOpacity;
  final double? expandProgress;
  final VoidCallback? onVerticalDragStart;
  final ValueChanged<DragUpdateDetails>? onVerticalDragUpdate;
  final ValueChanged<DragEndDetails>? onVerticalDragEnd;
  final VoidCallback? onVerticalDragCancel;

  const _MusicRegieDrawer({
    required this.state,
    required this.musicVolume,
    required this.resolveMusicPad,
    required this.isAdvanced,
    this.isDesktop = false,
    required this.onModeToggle,
    required this.onChooseMusic,
    required this.onChooseMusicToPlay,
    required this.onPauseToggle,
    required this.onSkipNext,
    this.onEjectMusic,
    this.onRemoveFromQueue,
    this.onReorderMusicQueue,
    this.onMusicVolumeChanged,
    this.onSeekMusic,
    this.ambianceVolume = 1.0,
    this.onChooseAmbiance,
    this.onStopAmbiance,
    this.onAmbianceVolumeChanged,
    required this.selectedTransitionDuration,
    required this.transitionDurationLocked,
    required this.onTransitionOptionTapped,
    required this.onTransitionOptionLongPressed,
    this.activeTransitionKind,
    this.transitionProgress,
    this.transitionBlinkOpacity,
    this.expandProgress,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
    this.onVerticalDragCancel,
  });

  @override
  State<_MusicRegieDrawer> createState() => _MusicRegieDrawerState();
}

class _MusicRegieDrawerState extends State<_MusicRegieDrawer> {
  /// Hauteur mesurée de la colonne « à l'antenne » en mode deux colonnes —
  /// reportée à la file de passage (voir _buildModeBody) pour qu'elle
  /// s'étire à la même hauteur plutôt que de ne prendre que celle de son
  /// contenu. Une vraie contrainte de hauteur (via Row.stretch ou
  /// IntrinsicHeight) est hors jeu ici : le tiroir s'auto-dimensionne sur
  /// tout le rail (aucun plafond ambiant), et IntrinsicHeight casse la file
  /// (ReorderableListView est un viewport, qui ne sait pas répondre à une
  /// mesure intrinsèque).
  double? _onAirColumnHeight;

  void _reportOnAirColumnHeight(Size size) {
    if (_onAirColumnHeight != null &&
        (size.height - _onAirColumnHeight!).abs() < 0.5) {
      return;
    }
    setState(() => _onAirColumnHeight = size.height);
  }

  bool get _isInteractive => widget.expandProgress != null && !widget.isDesktop;

  bool get _canTapToExpand {
    final progress = widget.expandProgress;
    if (progress != null) return progress < 0.5;
    return !widget.isAdvanced;
  }

  void _handleTapToExpand() {
    if (!_canTapToExpand) return;
    widget.onModeToggle();
  }

  _OnAirControls _buildOnAirControls({
    required bool isPlaying,
    required bool hasCurrent,
    required bool hasQueue,
  }) {
    return _OnAirControls(
      volume: widget.musicVolume,
      onVolumeChanged: widget.onMusicVolumeChanged,
      isPlaying: isPlaying,
      hasCurrent: hasCurrent,
      hasQueue: hasQueue,
      keyboardEnabled: widget.isDesktop,
      selectedTransitionDuration: widget.selectedTransitionDuration,
      transitionDurationLocked: widget.transitionDurationLocked,
      onTransitionOptionTapped: widget.onTransitionOptionTapped,
      onTransitionOptionLongPressed: widget.onTransitionOptionLongPressed,
      activeTransitionKind: widget.activeTransitionKind,
      transitionProgress: widget.transitionProgress,
      transitionBlinkOpacity: widget.transitionBlinkOpacity,
      onChooseMusic: widget.onChooseMusicToPlay,
      onTogglePlayPause: () =>
          widget.onPauseToggle(isPlaying: isPlaying, hasCurrent: hasCurrent),
      onSkipNext: () =>
          widget.onSkipNext(isPlaying: isPlaying, hasQueue: hasQueue),
      onEjectMusic: widget.onEjectMusic,
    );
  }

  Widget _buildModeBody({
    required BuildContext context,
    required ColorScheme scheme,
    required bool advanced,
    required bool useTwoColumns,
    required PadItem? current,
    required bool isPlaying,
    required PadItem? next,
    required List<PadItem> queue,
    required _OnAirControls onAirControls,
  }) {
    if (!advanced) {
      return _buildCompactBar(
        context: context,
        scheme: scheme,
        current: current,
        isPlaying: isPlaying,
        hasQueue: queue.isNotEmpty,
        next: next,
      );
    }

    // Pas de cadre autour de la lecture en cours : contrôles en tête, puis
    // titre/avancement en dessous. Assez de largeur pour les deux moitiés
    // (lecture / file) → côte à côte ; sinon empilés, la file en dernier.
    // En deux colonnes, le chevron a sa propre colonne (plus bas) ; en
    // colonne unique, il n'y a plus de gouttière pour l'accueillir, donc on
    // le glisse en bout de la rangée « à l'antenne », déjà plus haute que
    // lui — toujours zéro hauteur ajoutée, jamais d'overlay à réserver.
    final onAirRow = useTwoColumns
        ? onAirControls
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: onAirControls),
              const SizedBox(width: 8),
              _DrawerChevronButton(
                scheme: scheme,
                expanded: true,
                onTap: widget.onModeToggle,
              ),
            ],
          );
    final leftColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        onAirRow,
        const SizedBox(height: 14),
        _buildTrackInfo(scheme: scheme, current: current, isPlaying: isPlaying),
        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 10),
        Text('AMBIANCE', style: AppTextStyles.sectionLabel(context)),
        const SizedBox(height: 4),
        _buildAmbianceSlot(layout: _AmbianceSlotLayout.row),
      ],
    );
    final queueSection = _PassageQueueSection(
      queue: queue,
      isDesktop: widget.isDesktop,
      onRemove: widget.onRemoveFromQueue,
      onReorder: widget.onReorderMusicQueue,
      onChooseMusic: widget.onChooseMusic,
      // En deux colonnes, la carte est étirée à une hauteur fixe (voir plus
      // bas) : « Ajouter à la file » doit rester ancré tout en bas plutôt
      // que de suivre le dernier élément de la liste. Tant que cette hauteur
      // n'a pas encore été mesurée (premier affichage en deux colonnes,
      // avant le postFrameCallback de _ReportSize), rester en shrinkWrap :
      // un stretch sans hauteur bornée ferait planter le RenderFlex.
      stretchToFill: useTwoColumns && _onAirColumnHeight != null,
    );

    if (useTwoColumns) {
      // Le chevron vit dans sa propre colonne centrale, alignée en haut :
      // les deux colonnes voisines sont toujours plus hautes que lui, donc
      // il n'ajoute aucune hauteur au tiroir (cf. build(), qui saute
      // l'overlay dans ce cas précis).
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _ReportSize(
              onChange: _reportOnAirColumnHeight,
              child: leftColumn,
            ),
          ),
          const SizedBox(width: _MusicRegieDrawer._advancedColumnGap),
          SizedBox(
            width: _MusicRegieDrawer._centerChevronColumnWidth,
            child: Center(
              child: _DrawerChevronButton(
                scheme: scheme,
                expanded: true,
                onTap: widget.onModeToggle,
              ),
            ),
          ),
          const SizedBox(width: _MusicRegieDrawer._advancedColumnGap),
          Expanded(
            // La file est étirée à exactement la hauteur de la colonne « à
            // l'antenne » (mesurée ci-dessus) plutôt que de ne prendre que
            // celle de son propre contenu — une hauteur fixe, pas un simple
            // minimum, sinon la colonne grandirait pour remplir tout le
            // tiroir dès qu'un stretch quelconque s'applique (mainAxisSize
            // par défaut = max). stretchToFill fait défiler la liste en
            // interne dans cette hauteur fixe (au lieu du shrinkWrap
            // habituel) : jamais de débordement même avec beaucoup
            // d'éléments, et « Ajouter à la file » reste ancré en bas.
            // Plancher à _PassageQueueSection.minStretchHeight : la colonne
            // « à l'antenne » est courte, et à sa seule hauteur la file ne
            // montrait qu'un élément — le tiroir grandit alors un peu.
            child: _onAirColumnHeight == null
                ? queueSection
                : SizedBox(
                    height: math.max(
                      _onAirColumnHeight ?? 0,
                      _PassageQueueSection.minStretchHeight,
                    ),
                    child: queueSection,
                  ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [leftColumn, const SizedBox(height: 12), queueSection],
    );
  }

  _AmbianceSlot _buildAmbianceSlot({required _AmbianceSlotLayout layout}) {
    return _AmbianceSlot(
      current: widget.state.currentAmbiancePad,
      volume: widget.ambianceVolume,
      layout: layout,
      onChoose: widget.onChooseAmbiance,
      onStop: widget.onStopAmbiance,
      onVolumeChanged: widget.onAmbianceVolumeChanged,
    );
  }

  /// Titre courant + avancement (waveform ou barre linéaire, avec seek) —
  /// sans cadre ni pastille « à l'antenne » (supprimés), juste l'info utile
  /// sous les contrôles.
  Widget _buildTrackInfo({
    required ColorScheme scheme,
    required PadItem? current,
    required bool isPlaying,
  }) {
    final titleText = Text(
      current?.displayName ?? 'Aucune musique lancée',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: current != null ? scheme.onSurface : scheme.onSurfaceVariant,
      ),
    );
    final titleRow = current == null
        ? titleText
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titleText),
              _EjectMusicButton(
                scheme: scheme,
                enabled: !isPlaying,
                onTap: widget.onEjectMusic,
              ),
            ],
          );

    final details = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titleRow,
        if (current != null && current.pad.sounds.length > 1)
          Text(
            '${current.pad.sounds.length} variantes',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          )
        else if (current == null)
          Text(
            'Choisissez une piste pour démarrer',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
            ),
          ),
        if (current != null) ...[
          const SizedBox(height: 10),
          _RegieProgressBar(
            padItem: current,
            isPlaying: isPlaying,
            showTimes: true,
            onSeek: widget.onSeekMusic,
          ),
        ],
      ],
    );

    if (current == null) return details;

    // Jaquette minimale : la couleur du pad suffit à identifier la piste
    // d'un coup d'œil, pas de vraie pochette à afficher en régie.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PadColorChip(padItem: current, size: 44),
        const SizedBox(width: 12),
        Expanded(child: details),
      ],
    );
  }

  /// Bandeau réduit — une seule ligne : lecture/pause (accent plein) + suivant
  /// + fondu, titre courant avec position, volume. Pas de section « à
  /// l'antenne » ni de carte : direction "Console Linear", voir
  /// `.claude/rules/ui.md`. Le détail (queue, à l'antenne étendu) reste
  /// disponible en développant vers le mode avancé.
  Widget _buildCompactBar({
    required BuildContext context,
    required ColorScheme scheme,
    required PadItem? current,
    required bool isPlaying,
    required bool hasQueue,
    required PadItem? next,
  }) {
    final hasCurrent = current != null;
    final canControl = hasCurrent || hasQueue;
    final comfortable =
        MediaQuery.sizeOf(context).width >=
        _GroupedPlaybackControls.comfortableWidthThreshold;

    final playbackControls = _GroupedPlaybackControls(
      isPlaying: isPlaying,
      canControl: canControl,
      hasQueue: hasQueue,
      selectedTransitionDuration: widget.selectedTransitionDuration,
      transitionDurationLocked: widget.transitionDurationLocked,
      onTransitionOptionTapped: widget.onTransitionOptionTapped,
      onTransitionOptionLongPressed: widget.onTransitionOptionLongPressed,
      showCut: comfortable,
      isDesktop: widget.isDesktop,
      activeTransitionKind: widget.activeTransitionKind,
      transitionProgress: widget.transitionProgress,
      transitionBlinkOpacity: widget.transitionBlinkOpacity,
      onChooseMusic: widget.onChooseMusicToPlay,
      onTogglePlayPause: () =>
          widget.onPauseToggle(isPlaying: isPlaying, hasCurrent: hasCurrent),
      onSkipNext: () =>
          widget.onSkipNext(isPlaying: isPlaying, hasQueue: hasQueue),
    );

    final currentTitleStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: hasCurrent ? scheme.onSurface : scheme.onSurfaceVariant,
    );
    final currentTitleText = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (hasCurrent) ...[
          _PadColorChip(padItem: current, size: 14),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            current?.displayName ?? 'Aucune piste sélectionnée',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: currentTitleStyle,
          ),
        ),
        if (hasCurrent)
          _EjectMusicButton(
            scheme: scheme,
            enabled: !isPlaying,
            onTap: widget.onEjectMusic,
          ),
      ],
    );

    final trackInfo = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // Place restante entre les boutons de lecture et le volume : en
              // dessous du seuil, la musique en cours garde toute la largeur ;
              // au-dessus, on la partage à parts égales avec la file (moitié
              // gauche = en cours, moitié droite = suivant).
              const splitThreshold = 680.0;
              const splitGap = 10.0;
              final showNext =
                  next != null && constraints.maxWidth >= splitThreshold;
              if (!showNext) return currentTitleText;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: currentTitleText),
                  const SizedBox(width: splitGap),
                  Expanded(
                    child: _CompactNextUpLabel(
                      name: next.displayName,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            },
          ),
          if (hasCurrent) ...[
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.graphic_eq_rounded,
                  size: 12,
                  color: isPlaying
                      ? scheme.primary
                      : scheme.onSurfaceVariant.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 5),
                _CompactNowPlayingTime(
                  padItem: current,
                  isPlaying: isPlaying,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ],
      ),
    );

    final volume = SizedBox(
      width: comfortable ? 150 : 110,
      child: _CompactVolumeSlider(
        value: widget.musicVolume,
        onChanged: widget.onMusicVolumeChanged,
        isPlaying: isPlaying,
        keyboardEnabled: widget.isDesktop,
      ),
    );

    // Voie ambiance : glissée dans la même rangée (jamais sur une ligne à
    // elle), pastille complète si la largeur le permet, sinon icône seule.
    final ambianceSlot = _buildAmbianceSlot(
      layout: comfortable ? _AmbianceSlotLayout.pill : _AmbianceSlotLayout.icon,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        playbackControls,
        Expanded(child: trackInfo),
        ambianceSlot,
        const SizedBox(width: 8),
        volume,
        const SizedBox(width: 8),
        // Chevron en bout de bandeau, jamais au-dessus : la rangée est déjà
        // plus haute que lui (boutons de lecture), donc la barre réduite ne
        // grandit pas d'un pixel pour l'accueillir.
        _DrawerChevronButton(
          scheme: scheme,
          expanded: false,
          onTap: widget.onModeToggle,
        ),
      ],
    );
  }

  Widget _buildDrawerInner({
    required BuildContext context,
    required ColorScheme scheme,
    required bool advanced,
    required double? progress,
    required bool useTwoColumns,
  }) {
    final current = widget.state.currentMusicPad;
    final isPlaying = current?.isPlaying ?? false;
    final queue = widget.state.musicQueue(widget.resolveMusicPad);
    final next = queue.isNotEmpty ? queue.first : null;
    final hasCurrent = current != null;
    final hasQueue = queue.isNotEmpty;
    final onAirControls = _buildOnAirControls(
      isPlaying: isPlaying,
      hasCurrent: hasCurrent,
      hasQueue: hasQueue,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: advanced
              ? _MusicRegieDrawer._advancedDrawerPadding
              : _MusicRegieDrawer._compactDrawerPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (progress == null)
                _buildModeBody(
                  context: context,
                  scheme: scheme,
                  advanced: advanced,
                  useTwoColumns: useTwoColumns,
                  current: current,
                  isPlaying: isPlaying,
                  next: next,
                  queue: queue,
                  onAirControls: onAirControls,
                )
              else
                Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    IgnorePointer(
                      ignoring: progress > 0.5,
                      child: Opacity(
                        opacity: (1 - progress).clamp(0.0, 1.0),
                        child: _buildModeBody(
                          context: context,
                          scheme: scheme,
                          advanced: false,
                          useTwoColumns: useTwoColumns,
                          current: current,
                          isPlaying: isPlaying,
                          next: next,
                          queue: queue,
                          onAirControls: _buildOnAirControls(
                            isPlaying: isPlaying,
                            hasCurrent: hasCurrent,
                            hasQueue: hasQueue,
                          ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      ignoring: progress <= 0.5,
                      child: Opacity(
                        opacity: progress.clamp(0.0, 1.0),
                        child: _buildModeBody(
                          context: context,
                          scheme: scheme,
                          advanced: true,
                          useTwoColumns: useTwoColumns,
                          current: current,
                          isPlaying: isPlaying,
                          next: next,
                          queue: queue,
                          onAirControls: _buildOnAirControls(
                            isPlaying: isPlaying,
                            hasCurrent: hasCurrent,
                            hasQueue: hasQueue,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = widget.expandProgress;
    final expanded = (progress ?? (widget.isAdvanced ? 1.0 : 0.0)) >= 0.5;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Mesurée avant le padding du tiroir (voir _buildDrawerInner) : on
        // rajoute ce padding au seuil plutôt que de le retrancher de la
        // largeur, pour garder une seule mesure ici.
        final useTwoColumns =
            widget.isAdvanced &&
            constraints.maxWidth >=
                _MusicRegieDrawer._twoColumnMinWidth +
                    _MusicRegieDrawer._advancedDrawerPadding.horizontal;

        final drawerBody = _buildDrawerInner(
          context: context,
          scheme: scheme,
          advanced: widget.isAdvanced,
          progress: progress,
          useTwoColumns: useTwoColumns,
        );

        final Widget drawerContent;
        if (_isInteractive) {
          drawerContent = Semantics(
            label: expanded ? 'Réduire la régie' : 'Développer la régie',
            hint:
                'Appuyer ou glisser vers le haut pour développer, '
                'vers le bas pour réduire',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleTapToExpand,
              onVerticalDragStart: (_) => widget.onVerticalDragStart?.call(),
              onVerticalDragUpdate: widget.onVerticalDragUpdate,
              onVerticalDragEnd: widget.onVerticalDragEnd,
              onVerticalDragCancel: widget.onVerticalDragCancel,
              child: drawerBody,
            ),
          );
        } else if (_canTapToExpand) {
          drawerContent = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleTapToExpand,
            child: drawerBody,
          );
        } else {
          drawerContent = drawerBody;
        }

        return Material(
          color: scheme.surfaceContainerLow,
          shape: widget.isDesktop
              ? const RoundedRectangleBorder()
              : const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
          clipBehavior: Clip.none,
          child: drawerContent,
        );
      },
    );
  }
}
