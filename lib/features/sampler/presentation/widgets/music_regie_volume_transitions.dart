part of 'music_preview_panel.dart';

class _CompactVolumeSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double>? onChanged;
  final bool isPlaying;
  final bool keyboardEnabled;

  const _CompactVolumeSlider({
    required this.value,
    this.onChanged,
    this.isPlaying = false,
    this.keyboardEnabled = false,
  });

  @override
  State<_CompactVolumeSlider> createState() => _CompactVolumeSliderState();
}

class _CompactVolumeSliderState extends State<_CompactVolumeSlider>
    with SingleTickerProviderStateMixin {
  double? _localValue;

  /// Ticker qui rampe le volume vers le point maintenu (mode lecture).
  Ticker? _rampTicker;

  /// Fraction cible (0→1) sous le doigt tant qu'il est enfoncé — `null` au repos.
  double? _rampTarget;
  Duration _lastRampTick = Duration.zero;

  /// Touche fléchée en cours de maintien (ramp clavier) — `null` sinon.
  LogicalKeyboardKey? _rampKey;

  /// Vrai si le ramp courant est piloté au pointeur : il doit être coupé si la
  /// lecture s'arrête (le relâchement ne serait plus délivré). Un ramp clavier
  /// reçoit toujours son KeyUpEvent via le handler global, pas ce besoin.
  bool _rampFromPointer = false;

  /// Marge horizontale du rail (rayon du pouce) pour convertir x → fraction.
  static const _trackInset = 8.0;

  /// Vitesse du ramp : parcours complet 0→100 % en 5 s. La position balayée est
  /// linéaire ; c'est le taper de la régie qui la courbe ensuite en gain.
  static const _rampUnitsPerSecond = 1 / 5;

  double get _displayValue => _localValue ?? widget.value;

  /// Le ramp progressif ne s'active qu'à l'antenne et si le slider est actif.
  bool get _rampEnabled => widget.isPlaying && widget.onChanged != null;

  @override
  void initState() {
    super.initState();
    // Handler clavier global : les flèches ↑/↓ agissent sans dépendre du focus
    // (indispensable en régie live où le focus est souvent ailleurs). Filtré
    // sur desktop et sur les seules flèches verticales dans le handler.
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
  }

  @override
  void didUpdateWidget(_CompactVolumeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // La lecture s'arrête (ou le slider se désactive) pendant un appui pointeur :
    // le Listener disparaît, donc on coupe le ramp nous-mêmes pour ne pas
    // laisser le ticker tourner dans le vide.
    if (!_rampEnabled && _rampFromPointer && _rampTarget != null) {
      _rampTarget = null;
      _rampFromPointer = false;
      _rampTicker?.stop();
      _localValue = null;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    _rampTicker?.dispose();
    super.dispose();
  }

  double _fractionFromLocalX(double dx) {
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 0;
    final usable = width - 2 * _trackInset;
    if (usable <= 0) return _displayValue.clamp(0.0, 1.0);
    return ((dx - _trackInset) / usable).clamp(0.0, 1.0);
  }

  /// Démarre (ou redirige) le ramp vers une fraction cible 0→1.
  void _beginRamp(double target) {
    _rampTarget = target;
    _lastRampTick = Duration.zero;
    _rampTicker ??= createTicker(_onRampTick);
    if (!_rampTicker!.isActive) _rampTicker!.start();
  }

  void _startRamp(PointerDownEvent event) {
    _rampFromPointer = true;
    _beginRamp(_fractionFromLocalX(event.localPosition.dx));
  }

  void _updateRampTarget(PointerMoveEvent event) {
    _rampTarget = _fractionFromLocalX(event.localPosition.dx);
  }

  void _stopRamp() {
    _rampTarget = null;
    _rampKey = null;
    _rampFromPointer = false;
    _rampTicker?.stop();
    // La dernière valeur atteinte a déjà été poussée via onChanged : on repasse
    // sur widget.value (identique) pour rester synchronisé avec le parent.
    if (_localValue != null) {
      setState(() => _localValue = null);
    }
  }

  /// Un champ texte a-t-il le focus ? Dans ce cas on laisse les flèches à
  /// l'édition (déplacement du curseur) plutôt que de piloter le volume.
  bool _isEditingText() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  /// Handler clavier global : flèches ↑/↓ maintenues → ramp du volume vers
  /// 100 % / 0 %, relâché = arrêt net. Ne consomme que les flèches verticales
  /// (les autres touches passent) et seulement sur desktop, slider actif, hors
  /// saisie texte — sinon comportement clavier normal préservé.
  bool _handleGlobalKey(KeyEvent event) {
    if (!widget.keyboardEnabled || widget.onChanged == null) return false;
    final key = event.logicalKey;
    final isUp = key == LogicalKeyboardKey.arrowUp;
    final isDown = key == LogicalKeyboardKey.arrowDown;
    if (!isUp && !isDown) return false;
    if (_isEditingText()) return false;

    if (event is KeyDownEvent) {
      _rampKey = key;
      _beginRamp(isUp ? 1.0 : 0.0);
    } else if (event is KeyUpEvent && key == _rampKey) {
      _stopRamp();
    }
    // KeyRepeatEvent : rien à faire, le ramp tourne déjà — on consomme quand même.
    return true;
  }

  void _onRampTick(Duration elapsed) {
    final target = _rampTarget;
    if (target == null) return;
    final dt = (elapsed - _lastRampTick).inMicroseconds / 1e6;
    _lastRampTick = elapsed;
    if (dt <= 0) return;

    final current = _displayValue;
    final maxStep = _rampUnitsPerSecond * dt;
    final double next;
    if ((target - current).abs() <= maxStep) {
      next = target;
    } else {
      next = current + (target > current ? maxStep : -maxStep);
    }
    if (next == current) return;
    setState(() => _localValue = next);
    widget.onChanged!(next);
  }

  @override
  Widget build(BuildContext context) {
    final fraction = _displayValue.clamp(0.0, 1.0);

    final sliderTheme = SliderTheme.of(context).copyWith(
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(
        enabledThumbRadius: 8,
        disabledThumbRadius: 8,
      ),
      overlayShape: SliderComponentShape.noOverlay,
      showValueIndicator: ShowValueIndicator.onDrag,
    );

    final Widget sliderCore;
    if (_rampEnabled) {
      // Lecture : le Slider natif n'affiche que la position courante — les
      // pointeurs sont interceptés pour piloter le ramp à la main.
      sliderCore = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Listener(
          // Opaque : l'enfant IgnorePointer n'est pas hit-testable, donc sans
          // ça (deferToChild par défaut) le Listener ne recevrait aucun appui.
          behavior: HitTestBehavior.opaque,
          onPointerDown: _startRamp,
          onPointerMove: _updateRampTarget,
          onPointerUp: (_) => _stopRamp(),
          onPointerCancel: (_) => _stopRamp(),
          child: IgnorePointer(
            child: SliderTheme(
              data: sliderTheme,
              child: Slider(
                value: fraction,
                min: 0.0,
                max: 1.0,
                label: '${(fraction * 100).round()}%',
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
    } else {
      sliderCore = SliderTheme(
        data: sliderTheme,
        child: Slider(
          value: widget.value,
          min: 0.0,
          max: 1.0,
          label: '${(fraction * 100).round()}%',
          onChanged: widget.onChanged == null
              ? null
              : (value) {
                  setState(() => _localValue = value);
                  widget.onChanged!(value);
                },
          onChangeEnd: widget.onChanged == null
              ? null
              : (_) => setState(() => _localValue = null),
        ),
      );
    }

    // Les flèches clavier passent par le handler global (indépendant du focus),
    // donc aucun wrapper Focus ici — juste le rail.
    return SizedBox(height: 42, child: sliderCore);
  }
}

/// Sélecteur minimal de durée (1 / 3 / 5 s) — reclic pour désélectionner.
class _CompactTransitionPicker extends StatelessWidget {
  final Duration? selected;

  /// Vrai si la durée [selected] est verrouillée (persiste après transition).
  final bool locked;
  final ValueChanged<Duration> onOptionTapped;
  final ValueChanged<Duration> onOptionLongPressed;

  /// Affiche une cellule de coupe sèche explicite en tête du sélecteur.
  final bool showCut;
  final double cellSize;
  final double cellGap;
  final double fontSize;

  static const _options = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 5),
  ];

  /// Sentinelle : `Duration.zero` signale la coupe sèche (état `null` côté
  /// panneau — aucun fondu). Jamais une durée réelle du sélecteur.
  static const cutSentinel = Duration.zero;

  const _CompactTransitionPicker({
    required this.selected,
    required this.locked,
    required this.onOptionTapped,
    required this.onOptionLongPressed,
    required this.showCut,
    required this.cellSize,
    required this.cellGap,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      height: 1,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showCut) ...[
          _TransitionCell(
            size: cellSize,
            icon: Icons.content_cut_rounded,
            isSelected: selected == null,
            onTap: () => onOptionTapped(cutSentinel),
            labelStyle: labelStyle,
            scheme: scheme,
          ),
          SizedBox(width: cellGap),
        ],
        for (var i = 0; i < _options.length; i++) ...[
          if (i > 0) SizedBox(width: cellGap),
          _TransitionCell(
            size: cellSize,
            label: '${_options[i].inSeconds}',
            isSelected: selected == _options[i],
            isLocked: locked && selected == _options[i],
            onTap: () => onOptionTapped(_options[i]),
            onLongPress: () => onOptionLongPressed(_options[i]),
            labelStyle: labelStyle,
            scheme: scheme,
          ),
        ],
      ],
    );
  }
}

class _TransitionCell extends StatelessWidget {
  final double size;

  /// Libellé numérique de la durée, ou `null` si la cellule affiche [icon].
  final String? label;

  /// Icône (coupe sèche) affichée à la place du libellé.
  final IconData? icon;
  final bool isSelected;

  /// Durée verrouillée : affiche un cadenas en filigrane derrière le chiffre.
  final bool isLocked;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final TextStyle? labelStyle;
  final ColorScheme scheme;

  const _TransitionCell({
    required this.size,
    this.label,
    this.icon,
    required this.isSelected,
    this.isLocked = false,
    required this.onTap,
    this.onLongPress,
    required this.labelStyle,
    required this.scheme,
  }) : assert(label != null || icon != null, 'label ou icon requis');

  @override
  Widget build(BuildContext context) {
    final foreground =
        isSelected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    final Widget child = icon != null
        ? Icon(icon, size: size * 0.55, color: foreground)
        : Text(
            label!,
            style: labelStyle?.copyWith(
              color: foreground,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            ),
          );

    // Cadenas en filigrane derrière le chiffre — signale la durée verrouillée
    // sans masquer le libellé, qui reste lisible par-dessus.
    final Widget content = isLocked
        ? Stack(
            alignment: Alignment.center,
            children: [
              Transform.translate(
                offset: const Offset(0, -2),
                child: Icon(
                  Icons.lock_rounded,
                  size: size * 0.7,
                  color: foreground.withValues(alpha: 0.22),
                ),
              ),
              child,
            ],
          )
        : child;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: isSelected
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primaryContainer.withValues(alpha: 0.65),
                )
              : null,
          child: content,
        ),
      ),
    );
  }
}

/// Indicateur circulaire de téléchargement pour la régie musique.
