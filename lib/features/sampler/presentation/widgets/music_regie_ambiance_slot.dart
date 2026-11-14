part of 'music_preview_panel.dart';

enum _AmbianceSlotLayout {
  /// Icône seule (écran étroit) : changer / arrêter passent par un menu.
  icon,

  /// Bandeau réduit : icône ambiance sans fond au repos, qui s'étire en
  /// pastille bordée (nom et arrêt) à l'antenne. Pas de volume en mode
  /// réduit — il se règle dans le tiroir ouvert.
  pill,

  /// Ligne pleine largeur dans le tiroir ouvert, avec le volume de voie.
  row,
}

/// Voie ambiance de la régie. L'ambiance n'a besoin que de son nom, de son
/// volume et d'un arrêt (pas de file, pas de pause) : elle tient dans une
/// pastille glissée dans une rangée existante, sans ajouter de hauteur.
class _AmbianceSlot extends StatelessWidget {
  final PadItem? current;
  final double volume;

  /// Fondu en cours (arrêt ou enchaîné) : loader sur le bouton concerné, et
  /// commandes figées jusqu'à la fin, comme lecture/suivant côté musique.
  final AmbianceTransition? transition;
  final _AmbianceSlotLayout layout;
  final VoidCallback? onChoose;
  final VoidCallback? onStop;
  final ValueChanged<double>? onVolumeChanged;

  static const _pillNameMaxWidth = 200.0;

  const _AmbianceSlot({
    required this.current,
    required this.volume,
    required this.layout,
    this.transition,
    this.onChoose,
    this.onStop,
    this.onVolumeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = this.current;
    final onAir = current != null && current.isPlaying;

    if (layout == _AmbianceSlotLayout.row) {
      // Repos ↔ à l'antenne : fondu croisé et hauteur animée, pas de saut.
      return AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.topCenter,
            children: [...previousChildren, ?currentChild],
          ),
          child: KeyedSubtree(
            key: ValueKey(onAir),
            child: _buildRow(scheme, onAir ? current : null),
          ),
        ),
      );
    }
    // Bandeau réduit : l'icône ambiance seule au repos (ouvre le sélecteur),
    // qui s'étire vers la droite en pastille à l'antenne. Écran étroit : pas
    // la place pour la pastille, l'icône ouvre un menu.
    if (onAir && layout == _AmbianceSlotLayout.icon) {
      return _buildIconMenu(scheme, current);
    }
    return _buildPill(scheme, current, onAir: onAir);
  }

  Widget _volumeSlider() => _CompactVolumeSlider(
    value: volume,
    onChanged: onVolumeChanged,
    isPlaying: true,
  );

  /// Bouton de transport rond (glyphes pleins de la régie). `filled` : fond
  /// accent, le repère principal — comme lecture/pause côté musique.
  /// Sans pause pour l'ambiance : lancer ouvre le sélecteur, arrêter coupe la
  /// voie, suivant la remplace (fondu enchaîné). [feedbackFor] : nature du
  /// fondu dont ce bouton porte le retour visuel.
  Widget _transport({
    required TransportGlyph glyph,
    required String tooltip,
    required VoidCallback? onPressed,
    required ColorScheme scheme,
    bool filled = false,
    AmbianceTransitionKind? feedbackFor,
  }) {
    final side = filled ? 32.0 : 28.0;
    final transition = this.transition;
    final button = SizedBox.square(
      dimension: side,
      child: IconButton(
        tooltip: tooltip,
        onPressed: transition != null ? null : onPressed,
        padding: EdgeInsets.zero,
        iconSize: filled ? 18 : 16,
        visualDensity: VisualDensity.compact,
        constraints: BoxConstraints.tightFor(width: side, height: side),
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: filled ? scheme.primary : null,
          foregroundColor: filled ? scheme.onPrimary : scheme.onSurface,
        ),
        icon: TransportIcon(glyph),
      ),
    );
    if (feedbackFor == null) return button;
    return _TransitionFeedback(
      transition: transition?.kind == feedbackFor ? transition : null,
      child: button,
    );
  }

  Widget _stopButton(ColorScheme scheme, {bool filled = false}) => _transport(
    glyph: TransportGlyph.stop,
    tooltip: 'Arrêter l\'ambiance',
    onPressed: onStop,
    scheme: scheme,
    filled: filled,
    feedbackFor: AmbianceTransitionKind.fadeOut,
  );

  Widget _name(ColorScheme scheme, String text, {required bool active}) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
        color: active ? scheme.onSurface : scheme.onSurfaceVariant,
      ),
    );
  }

  /// Pastille toujours cernée de sa bordure : au repos elle ne contient que
  /// l'icône ambiance ; à l'antenne, le fond apparaît et elle s'étire vers la
  /// droite pour révéler le titre et l'arrêt. Un seul facteur [0, 1] pilote
  /// fond, teinte de l'icône et largeur révélée.
  /// [current] reste affiché pendant la fermeture (arrêt) : le contenu se
  /// replie au lieu de disparaître d'un coup.
  Widget _buildPill(
    ColorScheme scheme,
    PadItem? current, {
    required bool onAir,
  }) {
    final border = AppElevation.border(scheme);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: onAir ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: Color.lerp(Colors.transparent, scheme.surfaceContainer, t),
          border: Border.fromBorderSide(border),
          borderRadius: AppRadius.radiusMd,
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 32,
                child: IconButton(
                  tooltip: onAir
                      ? 'Changer d\'ambiance'
                      : 'Lancer une ambiance',
                  onPressed: onChoose,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: StrokeIcon(
                    SoundType.ambiance.icon,
                    size: AppIconSize.sm,
                    color:
                        Color.lerp(
                          scheme.onSurfaceVariant,
                          scheme.primary,
                          t,
                        ) ??
                        scheme.onSurfaceVariant,
                  ),
                ),
              ),
              ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: t,
                  child: Opacity(
                    opacity: t,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _pillNameMaxWidth,
                          ),
                          child: _name(
                            scheme,
                            current?.displayName ?? '',
                            active: true,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _stopButton(scheme),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconMenu(ColorScheme scheme, PadItem current) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, -8),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: SizedBox(
            width: 220,
            child: Row(
              children: [
                StrokeIcon(
                  SoundType.ambiance.icon,
                  size: AppIconSize.sm,
                  color: scheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _name(scheme, current.displayName, active: true),
                ),
              ],
            ),
          ),
        ),
        MenuItemButton(
          leadingIcon: const TransportIcon(
            TransportGlyph.stop,
            size: AppIconSize.sm,
          ),
          onPressed: transition != null ? null : onStop,
          child: const Text('Arrêter'),
        ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: current.displayName,
        child: InkWell(
          borderRadius: AppRadius.radiusSm,
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              border: Border.fromBorderSide(AppElevation.border(scheme)),
              borderRadius: AppRadius.radiusSm,
            ),
            child: StrokeIcon(
              SoundType.ambiance.icon,
              size: 16,
              color: scheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  /// Bloc du tiroir ouvert : même disposition que la lecture en cours côté
  /// musique (commandes en tête, puis pastille de la couleur du pad, titre et
  /// sous-titre), avec des boutons plus petits — la voie est secondaire.
  /// Pas de cadre, pas d'avancement : l'ambiance tourne en boucle (non dit à
  /// l'écran, c'est le propre de la voie).
  Widget _buildRow(ColorScheme scheme, PadItem? onAir) {
    final variants = onAir?.pad.sounds.length ?? 0;
    final subtitle = onAir == null
        ? 'Lancez une ambiance'
        : variants > 1
        ? '$variants variantes'
        : null;

    final controls = Row(
      children: [
        if (onAir == null)
          _transport(
            glyph: TransportGlyph.play,
            tooltip: 'Lancer une ambiance',
            onPressed: onChoose,
            scheme: scheme,
            filled: true,
          )
        else ...[
          _stopButton(scheme, filled: true),
          const SizedBox(width: 4),
          _transport(
            glyph: TransportGlyph.next,
            tooltip: 'Changer d\'ambiance',
            onPressed: onChoose,
            scheme: scheme,
            feedbackFor: AmbianceTransitionKind.crossfade,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 100, maxWidth: 150),
              child: SizedBox(height: 32, child: _volumeSlider()),
            ),
          ),
        ],
      ],
    );

    final details = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          onAir?.displayName ?? 'Aucune ambiance',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: onAir != null ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: onAir != null
                  ? scheme.onSurfaceVariant
                  : scheme.onSurfaceVariant.withValues(alpha: 0.75),
            ),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        controls,
        const SizedBox(height: 10),
        if (onAir == null)
          details
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _PadColorChip(
                padItem: onAir,
                size: 32,
                icon: SoundType.ambiance.icon,
                tinted: false,
              ),
              const SizedBox(width: 12),
              Expanded(child: details),
            ],
          ),
      ],
    );
  }
}

/// Retour visuel d'un fondu de la voie ambiance, identique à celui des boutons
/// lecture / suivant côté musique : le bouton clignote (opacité 0,35 ↔ 1) et un
/// petit badge de progression, dans le coin, se remplit sur la durée du fondu.
/// Sans fondu en cours, le bouton reste à pleine opacité et rien n'est dessiné.
class _TransitionFeedback extends StatefulWidget {
  final AmbianceTransition? transition;
  final Widget child;

  const _TransitionFeedback({required this.transition, required this.child});

  @override
  State<_TransitionFeedback> createState() => _TransitionFeedbackState();
}

class _TransitionFeedbackState extends State<_TransitionFeedback>
    with TickerProviderStateMixin {
  static const _blinkDuration = Duration(milliseconds: 320);
  static const _badgeSize = 11.0;

  late final AnimationController _progress = AnimationController(vsync: this);

  /// Repos à 1 : le bouton n'est jamais atténué hors fondu.
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: _blinkDuration,
    value: 1,
  );
  late final Animation<double> _opacity = Tween<double>(
    begin: 0.35,
    end: 1,
  ).animate(CurvedAnimation(parent: _blink, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    final transition = widget.transition;
    if (transition != null) _begin(transition);
  }

  @override
  void didUpdateWidget(_TransitionFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    final transition = widget.transition;
    if (transition == null) {
      if (oldWidget.transition != null) _end();
    } else if (oldWidget.transition?.id != transition.id) {
      _begin(transition);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _blink.dispose();
    super.dispose();
  }

  void _begin(AmbianceTransition transition) {
    _progress.duration = transition.duration;
    _progress.forward(from: 0);
    _blink.repeat(reverse: true);
  }

  void _end() {
    _progress.stop();
    _blink.value = 1;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        FadeTransition(opacity: _opacity, child: widget.child),
        if (widget.transition != null)
          Positioned(
            right: 2,
            top: 2,
            child: IgnorePointer(
              child: SizedBox.square(
                dimension: _badgeSize,
                child: AnimatedBuilder(
                  animation: _progress,
                  builder: (context, _) => CircularProgressIndicator(
                    value: _progress.value,
                    strokeWidth: 1.5,
                    backgroundColor: scheme.outlineVariant.withValues(
                      alpha: 0.25,
                    ),
                    valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Chevron très fin (hauteur minimale) : ouvre/ferme la régie explicitement,
/// sans dépendre d'un clic à l'extérieur — la régie reste ouverte quoi qu'il
/// se passe ailleurs sur l'écran (zone pads incluse). Toujours inséré en bout
/// d'une rangée de contrôles déjà plus haute que lui (jamais en overlay au-
/// dessus) : il n'ajoute donc aucune hauteur au tiroir, réduit ou ouvert.
