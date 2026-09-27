part of 'music_preview_panel.dart';

class _DrawerChevronButton extends StatelessWidget {
  final ColorScheme scheme;
  final bool expanded;
  final VoidCallback? onTap;

  const _DrawerChevronButton({
    required this.scheme,
    required this.expanded,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 18),
      icon: Icon(
        expanded
            ? Icons.keyboard_arrow_down_rounded
            : Icons.keyboard_arrow_up_rounded,
        size: 16,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
      ),
    );
  }
}

/// Éjecte la musique en cours — placé juste après le titre, donc affiché
/// uniquement quand une piste est chargée. Désactivé tant qu'elle est en
/// lecture (voir [MusicPreviewPanel.onEjectMusic]) : il faut d'abord mettre
/// en pause ou attendre un fondu pour éviter une coupure sèche accidentelle.
class _EjectMusicButton extends StatelessWidget {
  final ColorScheme scheme;
  final bool enabled;
  final VoidCallback? onTap;

  const _EjectMusicButton({
    required this.scheme,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 20),
      icon: Icon(
        Icons.eject_rounded,
        size: 16,
        color: enabled
            ? scheme.onSurfaceVariant.withValues(alpha: 0.75)
            : scheme.onSurfaceVariant.withValues(alpha: 0.3),
      ),
    );
  }
}

/// Contrôles de lecture intégrés à la zone « À l'antenne ».
class _OnAirControls extends StatelessWidget {
  static const _volumeSliderMinWidth = 100.0;
  static const _volumeSliderMaxWidth = 150.0;
  static const _inlineGap = 8.0;
  static const _wrappedRowGap = 10.0;
  static const _volumeGroupMinWidth = _volumeSliderMinWidth;

  final double volume;
  final ValueChanged<double>? onVolumeChanged;
  final bool isPlaying;
  final bool hasCurrent;
  final bool hasQueue;
  final bool keyboardEnabled;
  final Duration? selectedTransitionDuration;
  final bool transitionDurationLocked;
  final ValueChanged<Duration> onTransitionOptionTapped;
  final ValueChanged<Duration> onTransitionOptionLongPressed;
  final _MusicTransitionKind? activeTransitionKind;
  final Animation<double>? transitionProgress;
  final Animation<double>? transitionBlinkOpacity;
  final VoidCallback onChooseMusic;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback? onSkipNext;
  final VoidCallback? onEjectMusic;

  const _OnAirControls({
    required this.volume,
    this.onVolumeChanged,
    required this.isPlaying,
    required this.hasCurrent,
    required this.hasQueue,
    this.keyboardEnabled = false,
    required this.selectedTransitionDuration,
    required this.transitionDurationLocked,
    required this.onTransitionOptionTapped,
    required this.onTransitionOptionLongPressed,
    this.activeTransitionKind,
    this.transitionProgress,
    this.transitionBlinkOpacity,
    required this.onChooseMusic,
    this.onTogglePlayPause,
    this.onSkipNext,
    this.onEjectMusic,
  });

  double _resolveSliderWidth(double available) {
    if (available <= 0) return 0;
    return available.clamp(
      available < _volumeSliderMinWidth ? available : _volumeSliderMinWidth,
      _volumeSliderMaxWidth,
    );
  }

  Widget _volumeSlider({double? width, bool flexible = false}) {
    final slider = SizedBox(
      height: 42,
      width: width,
      child: _CompactVolumeSlider(
        value: volume,
        onChanged: onVolumeChanged,
        isPlaying: isPlaying,
        keyboardEnabled: keyboardEnabled,
      ),
    );

    if (flexible) {
      return ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: _volumeSliderMinWidth,
          maxWidth: _volumeSliderMaxWidth,
        ),
        child: slider,
      );
    }

    return slider;
  }

  Widget _volumeRow(double maxWidth) {
    return _volumeSlider(width: _resolveSliderWidth(maxWidth));
  }

  @override
  Widget build(BuildContext context) {
    final canControl = hasCurrent || hasQueue;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final comfortable = MediaQuery.sizeOf(context).width >=
            _GroupedPlaybackControls.comfortableWidthThreshold;
        // Cellules agrandies réservées au confort tactile — sans souris
        // desktop, la taille compacte suffit même sur écran large (voir
        // [_GroupedPlaybackControls.isDesktop]).
        final roomyPicker = comfortable && !keyboardEnabled;
        // Coupe sèche explicite dès que le groupe complet (4 cellules) tient
        // dans la largeur disponible — sinon repli sur les trois durées.
        final showCut = maxWidth >=
            _GroupedPlaybackControls.resolvedMinWidth(
              roomyPicker,
              withCut: true,
            );
        final groupMinWidth = _GroupedPlaybackControls.resolvedMinWidth(
          roomyPicker,
          withCut: showCut,
        );
        final fitsOnOneLine =
            maxWidth >= groupMinWidth + _inlineGap + _volumeGroupMinWidth;

        final playbackControls = _GroupedPlaybackControls(
          isPlaying: isPlaying,
          canControl: canControl,
          hasQueue: hasQueue,
          selectedTransitionDuration: selectedTransitionDuration,
          transitionDurationLocked: transitionDurationLocked,
          onTransitionOptionTapped: onTransitionOptionTapped,
          onTransitionOptionLongPressed: onTransitionOptionLongPressed,
          showCut: showCut,
          isDesktop: keyboardEnabled,
          activeTransitionKind: activeTransitionKind,
          transitionProgress: transitionProgress,
          transitionBlinkOpacity: transitionBlinkOpacity,
          onChooseMusic: onChooseMusic,
          onTogglePlayPause: onTogglePlayPause,
          onSkipNext: onSkipNext,
        );

        final Widget controls;
        if (fitsOnOneLine) {
          controls = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              playbackControls,
              const SizedBox(width: _inlineGap),
              Flexible(child: _volumeSlider(flexible: true)),
            ],
          );
        } else {
          controls = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              playbackControls,
              const SizedBox(height: _wrappedRowGap),
              _volumeRow(maxWidth),
            ],
          );
        }

        return SizedBox(
          width: maxWidth,
          child: controls,
        );
      },
    );
  }
}

/// Play / suivant et durée de transition regroupés visuellement.
class _GroupedPlaybackControls extends StatelessWidget {
  static const _iconSize = 24.0;
  static const _actionSize = 48.0;
  static const _actionButtonSize = 40.0;
  static const _progressBadgeSize = 11.0;

  /// Au-delà de cette largeur d'écran on n'est plus sur un téléphone : on
  /// agrandit les cibles du sélecteur de durée pour le confort tactile
  /// (tablette). Sous ce seuil on garde le mode compact pour que tout tienne
  /// sur petit écran. Sans pointeur tactile (souris desktop), l'agrandissement
  /// ne sert à rien — [isDesktop] force alors les petites cellules même sur
  /// un écran large.
  static const comfortableWidthThreshold = 600.0;

  static const _pickerCellCompact = 18.0;
  static const _pickerCellComfortable = 36.0;
  static const _pickerGapCompact = 1.0;
  static const _pickerGapComfortable = 4.0;
  static const _pickerFontCompact = 9.0;
  static const _pickerFontComfortable = 13.0;

  static double _pickerCellSize(bool comfortable) =>
      comfortable ? _pickerCellComfortable : _pickerCellCompact;

  static double _pickerGap(bool comfortable) =>
      comfortable ? _pickerGapComfortable : _pickerGapCompact;

  static double _pickerFontSize(bool comfortable) =>
      comfortable ? _pickerFontComfortable : _pickerFontCompact;

  static double _transitionPickerWidth(bool comfortable, bool withCut) {
    final cells = withCut ? 4 : 3;
    return cells * _pickerCellSize(comfortable) +
        (cells - 1) * _pickerGap(comfortable);
  }

  /// Largeur minimale du groupe play / suivant / durée selon le mode
  /// d'affichage et la présence de la cellule de coupe sèche.
  static double resolvedMinWidth(bool comfortable, {bool withCut = false}) =>
      6.0 +
      2 * _actionButtonSize +
      6.0 +
      1.0 +
      4.0 +
      _transitionPickerWidth(comfortable, withCut) +
      8.0;

  final bool isPlaying;
  final bool canControl;
  final bool hasQueue;
  final Duration? selectedTransitionDuration;
  final bool transitionDurationLocked;
  final ValueChanged<Duration> onTransitionOptionTapped;
  final ValueChanged<Duration> onTransitionOptionLongPressed;
  final bool showCut;

  /// Vrai sur desktop (souris) : les cellules du sélecteur de durée restent
  /// en taille compacte même sur écran large — l'agrandissement "confort" ne
  /// répond qu'à un besoin tactile, absent ici.
  final bool isDesktop;
  final _MusicTransitionKind? activeTransitionKind;
  final Animation<double>? transitionProgress;
  final Animation<double>? transitionBlinkOpacity;
  final VoidCallback onChooseMusic;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback? onSkipNext;

  const _GroupedPlaybackControls({
    required this.isPlaying,
    required this.canControl,
    required this.hasQueue,
    required this.selectedTransitionDuration,
    required this.transitionDurationLocked,
    required this.onTransitionOptionTapped,
    required this.onTransitionOptionLongPressed,
    required this.showCut,
    this.isDesktop = false,
    this.activeTransitionKind,
    this.transitionProgress,
    this.transitionBlinkOpacity,
    required this.onChooseMusic,
    this.onTogglePlayPause,
    this.onSkipNext,
  });

  Widget _actionButton({
    required BuildContext context,
    required VoidCallback? onPressed,
    required IconData icon,
    required bool showTransitionFeedback,
    bool filled = false,
  }) {
    final scheme = Theme.of(context).colorScheme;

    Widget button = SizedBox(
      width: _actionButtonSize,
      height: _actionButtonSize,
      child: IconButton(
        onPressed: onPressed,
        iconSize: filled ? _iconSize - 2 : _iconSize,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          alignment: Alignment.center,
          backgroundColor: filled ? scheme.primary : null,
          disabledBackgroundColor: filled ? scheme.surfaceContainerHigh : null,
          foregroundColor: filled ? scheme.onPrimary : null,
          disabledForegroundColor:
              filled ? scheme.onSurfaceVariant.withValues(alpha: 0.4) : null,
        ),
        constraints: const BoxConstraints(
          minWidth: _actionButtonSize,
          maxWidth: _actionButtonSize,
          minHeight: _actionButtonSize,
          maxHeight: _actionButtonSize,
        ),
        icon: Icon(icon),
      ),
    );

    if (showTransitionFeedback && transitionBlinkOpacity != null) {
      button = FadeTransition(
        opacity: transitionBlinkOpacity!,
        child: button,
      );
    }

    if (!showTransitionFeedback || transitionProgress == null) {
      return button;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          right: 2,
          top: 2,
          child: SizedBox(
            width: _progressBadgeSize,
            height: _progressBadgeSize,
            child: AnimatedBuilder(
              animation: transitionProgress!,
              builder: (context, _) {
                return CircularProgressIndicator(
                  value: transitionProgress!.value,
                  strokeWidth: 1.5,
                  backgroundColor:
                      scheme.outlineVariant.withValues(alpha: 0.25),
                  valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor = AppElevation.border(scheme).color;
    final comfortable =
        MediaQuery.sizeOf(context).width >= comfortableWidthThreshold &&
        !isDesktop;
    final playFeedback =
        activeTransitionKind == _MusicTransitionKind.fadeOut;
    final skipFeedback =
        activeTransitionKind == _MusicTransitionKind.crossfade;
    final transitionInProgress = activeTransitionKind != null;

    // Pas de pilule bordée autour du groupe — les commandes flottent
    // directement sur le fond de la barre, seul le bouton lecture porte un
    // fond plein (accent) pour rester le repère visuel principal.
    return SizedBox(
      height: _actionSize,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _actionButton(
            context: context,
            onPressed: transitionInProgress
                ? null
                : (canControl ? onTogglePlayPause : onChooseMusic),
            icon: canControl
                ? (isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded)
                : Icons.play_arrow_rounded,
            showTransitionFeedback: playFeedback,
            filled: true,
          ),
          const SizedBox(width: 4),
          _actionButton(
            context: context,
            onPressed: hasQueue && !transitionInProgress ? onSkipNext : null,
            icon: Icons.skip_next_rounded,
            showTransitionFeedback: skipFeedback,
          ),
          const SizedBox(width: 6),
          Container(width: 1, height: 24, color: borderColor),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: _CompactTransitionPicker(
              selected: selectedTransitionDuration,
              locked: transitionDurationLocked,
              onOptionTapped: onTransitionOptionTapped,
              onOptionLongPressed: onTransitionOptionLongPressed,
              showCut: showCut,
              cellSize: _pickerCellSize(comfortable),
              cellGap: _pickerGap(comfortable),
              fontSize: _pickerFontSize(comfortable),
            ),
          ),
        ],
      ),
    );
  }
}

/// Aperçu discret du prochain son de la file — affiché dans le bandeau
/// réduit à droite du titre courant, seulement quand la place restante le
/// permet (voir mesure dans `_buildCompactBar`).
class _CompactNextUpLabel extends StatelessWidget {
  final String name;
  final Color color;

  const _CompactNextUpLabel({required this.name, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.skip_next_rounded,
          size: 14,
          color: color.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color.withValues(alpha: 0.75),
            ),
          ),
        ),
      ],
    );
  }
}

/// Slider volume — affiche le pourcentage via le label natif du curseur
/// pendant le drag (position toujours exacte, gérée par Flutter).
///
/// En lecture (`isPlaying`), un appui ne saute plus directement au point
/// touché : le volume rampe progressivement (5 s pour tout le parcours) vers
/// l'endroit maintenu, et s'arrête net au relâchement — fondu manuel de régie.
///
/// Sur desktop (`keyboardEnabled`), les flèches ↑/↓ du clavier maintenues
/// pilotent le même ramp, sans dépendre du focus (handler clavier global).
