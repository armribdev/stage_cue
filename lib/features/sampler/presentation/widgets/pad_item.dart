import 'package:flutter/material.dart';
import '../providers/sampler_provider.dart';
import 'pad_button.dart';

/// Widget affichant un pad dans la grille (animations, suppression, surbrillance).
class PadCard extends StatefulWidget {
  final PadItem padItem;

  /// Mode classique éditable : affiche la croix de suppression et autorise le
  /// déplacement. Aucun wiggle — les affordances d'édition sont permanentes.
  final bool isEditable;

  /// Petit pop d'apparition (ex. annulation).
  final bool animateOnRestore;

  /// Bordure discrète pour indiquer le pad ciblé (ex. retour bibliothèque).
  final bool isHighlighted;
  final bool Function(PadItem padItem) isTapBlocked;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onRemove;

  /// Ouvre les détails du pad (bouton crayon en mode classique éditable).
  final VoidCallback? onEdit;

  /// Affiche la liste des sons du multipad (choix d'une variante précise à
  /// déclencher). Visible dès que le pad a plusieurs sons, y compris en Mode
  /// Spectacle — indépendant de [isEditable].
  final VoidCallback? onShowSounds;

  const PadCard({
    super.key,
    required this.padItem,
    required this.isEditable,
    required this.isTapBlocked,
    this.animateOnRestore = false,
    this.isHighlighted = false,
    this.onTap,
    this.onLongPress,
    this.onRemove,
    this.onEdit,
    this.onShowSounds,
  });

  @override
  State<PadCard> createState() => _PadCardState();
}

class _PadCardState extends State<PadCard> with TickerProviderStateMixin {
  late final AnimationController _deleteController;
  late final Animation<double> _deleteScale;
  late final AnimationController _restoreController;
  late final Animation<double> _restoreCurve;
  late final AnimationController _highlightFadeController;
  late final Animation<double> _highlightFade;
  late final AnimationController _highlightBreathController;
  bool _animationsDisabled = false;

  @override
  void initState() {
    super.initState();
    _deleteController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _deleteScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 0.95,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.95,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 55,
      ),
    ]).animate(_deleteController);
    _restoreController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: widget.animateOnRestore ? 0.0 : 1.0,
    );
    _restoreCurve = CurvedAnimation(
      parent: _restoreController,
      curve: Curves.easeOutCubic,
    );
    _highlightFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _highlightFade = CurvedAnimation(
      parent: _highlightFadeController,
      curve: Curves.easeInOutCubic,
    );
    _highlightBreathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _highlightFadeController.addStatusListener(_onHighlightFadeStatus);

    if (widget.animateOnRestore && !widget.isHighlighted) {
      _restoreController.forward();
    }
    if (widget.isHighlighted) {
      _applyHighlighted(true);
    }
  }

  void _onHighlightFadeStatus(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.completed && widget.isHighlighted) {
      _startBreathing();
    }
    if (status == AnimationStatus.dismissed) {
      _stopBreathing(resetValue: true);
    }
  }

  void _startBreathing() {
    if (!mounted || !widget.isHighlighted || _animationsDisabled) return;
    if (_highlightBreathController.isAnimating) return;
    _highlightBreathController.repeat(reverse: true);
  }

  void _stopBreathing({bool resetValue = false}) {
    _highlightBreathController.stop();
    if (resetValue) {
      _highlightBreathController.value = 0;
    }
  }

  void _applyHighlighted(bool highlighted) {
    if (_animationsDisabled) {
      _highlightFadeController.value = highlighted ? 1.0 : 0.0;
      _stopBreathing(resetValue: true);
      return;
    }
    if (highlighted) {
      _stopBreathing(resetValue: true);
      if (_highlightFadeController.value >= 1.0) {
        _startBreathing();
      } else {
        _highlightFadeController.forward();
      }
    } else {
      _stopBreathing(resetValue: true);
      _highlightFadeController.reverse();
    }
  }

  @override
  void didUpdateWidget(covariant PadCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.animateOnRestore &&
        widget.animateOnRestore &&
        !widget.isHighlighted &&
        !_animationsDisabled) {
      _restoreController.forward(from: 0);
    }
    if (oldWidget.isHighlighted != widget.isHighlighted) {
      _applyHighlighted(widget.isHighlighted);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disabled != _animationsDisabled) {
      _animationsDisabled = disabled;
      _applyHighlighted(widget.isHighlighted);
    }
  }

  @override
  void dispose() {
    _highlightFadeController.removeStatusListener(_onHighlightFadeStatus);
    _highlightBreathController.dispose();
    _highlightFadeController.dispose();
    _restoreController.dispose();
    _deleteController.dispose();
    super.dispose();
  }

  Future<void> _handleRemoveTap() async {
    if (widget.onRemove == null) return;
    if (!_animationsDisabled) {
      await _deleteController.forward(from: 0);
    }
    widget.onRemove!.call();
  }

  double _highlightBreathFactor() {
    if (_highlightFade.value <= 0) return 0;
    // Respiration uniquement une fois l'entrée terminée.
    if (_highlightFadeController.status != AnimationStatus.completed) {
      return 0;
    }
    // Valeur 0→1→0 : on centre sur 0.5 pour un souffle symétrique.
    return (_highlightBreathController.value - 0.5).abs() * 2.0;
  }

  /// Couleur des icônes flottantes (edit/fermer/sons) contrastée avec le fond
  /// réel du pad — un gris fixe devient illisible sur un pad rouge ou sombre.
  /// On reproduit l'alpha appliqué par [PadButton] selon l'état (lecture,
  /// pause) puis on compose sur la surface pour estimer la couleur perçue.
  Color _iconColor(ColorScheme scheme) {
    final colorValue = widget.padItem.pad.colorValue;
    if (colorValue == null) return Colors.grey.shade600;

    final customColor = Color(colorValue);
    final alpha = widget.padItem.isPlaying
        ? 0.75
        : widget.padItem.isPaused
            ? 0.35
            : 1.0;
    final effective = Color.alphaBlend(
      customColor.withValues(alpha: alpha),
      scheme.surface,
    );
    final isDarkBackground =
        ThemeData.estimateBrightnessForColor(effective) == Brightness.dark;

    // Teinte du pad conservée (désaturée) mais luminosité poussée à l'extrême
    // opposé du fond — l'icône se fond dans la couleur du pad tout en
    // restant lisible, plutôt qu'un noir/blanc brut déconnecté.
    final hsl = HSLColor.fromColor(customColor);
    final tinted = hsl
        .withSaturation((hsl.saturation * 0.6).clamp(0.0, 1.0))
        .withLightness(isDarkBackground ? 0.88 : 0.16)
        .toColor();
    return tinted.withValues(alpha: isDarkBackground ? 0.9 : 0.75);
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = _iconColor(Theme.of(context).colorScheme);

    // Boutons edit/close : uniquement affichés en mode édition sur PC (souris),
    // pas de contrainte de taille tactile nécessaire → icônes plus rapprochées.
    final deleteButton = widget.isEditable && widget.onRemove != null
        ? Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: _handleRemoveTap,
              color: iconColor,
              splashRadius: 12,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            ),
          )
        : null;

    final editButton = widget.isEditable && widget.onEdit != null
        ? Positioned(
            top: 4,
            right: 26,
            child: IconButton(
              icon: const Icon(Icons.edit_outlined, size: 14),
              onPressed: widget.onEdit,
              color: iconColor,
              splashRadius: 12,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            ),
          )
        : null;

    // Décalage dynamique : le bouton sons se recale à droite quand
    // éditer/fermer sont masqués (mode live), au lieu de laisser un trou.
    final hasDeleteButton = deleteButton != null;
    final hasEditButton = editButton != null;
    final showSoundsRight =
        4.0 +
        (hasDeleteButton ? 22.0 : 0.0) +
        (hasEditButton ? 22.0 : 0.0);

    final showSoundsButton =
        widget.padItem.totalSoundCount > 1 && widget.onShowSounds != null
        ? Positioned(
            top: 4,
            right: showSoundsRight,
            child: IconButton(
              icon: const Icon(Icons.queue_music_rounded, size: 14),
              onPressed: widget.onShowSounds,
              color: iconColor,
              splashRadius: 12,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            ),
          )
        : null;

    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: Listenable.merge([
        _deleteController,
        _restoreCurve,
        _highlightFadeController,
        _highlightBreathController,
      ]),
      builder: (context, child) {
        final deleteScale = _animationsDisabled ? 1.0 : _deleteScale.value;
        final restoreT = _animationsDisabled ? 1.0 : _restoreCurve.value;
        final useRestorePop =
            widget.animateOnRestore &&
            !widget.isHighlighted &&
            !_animationsDisabled;

        final fade = _animationsDisabled ? 0.0 : _highlightFade.value;
        final breath = _animationsDisabled ? 0.0 : _highlightBreathFactor();

        // Ne pas scaler le pad (texte) : évite le flou et les artefacts de bordure.
        final scale = useRestorePop
            ? deleteScale * (0.97 + (0.03 * restoreT))
            : deleteScale;
        final opacity = useRestorePop ? 0.85 + (0.15 * restoreT) : 1.0;

        final overlayScale = 1.0 + (fade * (0.01 + (0.008 * breath)));

        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: Stack(
              children: [
                RepaintBoundary(child: child!),
                if (fade > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Transform.scale(
                        scale: overlayScale,
                        child: Opacity(
                          opacity: fade.clamp(0.0, 1.0),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: scheme.primary.withValues(
                                    alpha: 0.1 + (0.06 * breath),
                                  ),
                                  blurRadius: 10 + (2 * breath),
                                  spreadRadius: 0,
                                ),
                              ],
                              border: Border.all(
                                color: scheme.primary.withValues(
                                  alpha: 0.3 + (0.15 * breath),
                                ),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ?editButton,
                ?deleteButton,
                ?showSoundsButton,
              ],
            ),
          ),
        );
      },
      // Rebuild ciblé : le PadButton se reconstruit sur la révision du pad
      // (progression de download, disponibilité) sans dépendre d'un rebuild
      // global de la grille (refonte UX P2).
      child: ListenableBuilder(
        listenable: widget.padItem.revision,
        builder: (context, _) {
          final blocked = widget.isTapBlocked(widget.padItem);
          return PadButton(
            key: ValueKey<int>(widget.padItem.pad.id),
            padItem: widget.padItem,
            onTap: blocked ? null : widget.onTap,
            onLongPress: widget.onLongPress,
          );
        },
      ),
    );
  }
}
