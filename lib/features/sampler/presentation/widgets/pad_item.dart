import 'package:flutter/material.dart';
import '../providers/sampler_provider.dart';
import 'pad_button.dart';

/// Widget affichant un pad dans la grille (animations, mode édition).
class PadCard extends StatefulWidget {
  final PadItem padItem;
  final bool isEditMode;
  /// Petit pop d'apparition (ex. annulation).
  final bool animateOnRestore;
  /// Bordure discrète pour indiquer le pad ciblé (ex. retour bibliothèque).
  final bool isHighlighted;
  final bool Function(PadItem padItem) isTapBlocked;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onRemove;

  const PadCard({
    super.key,
    required this.padItem,
    required this.isEditMode,
    required this.isTapBlocked,
    this.animateOnRestore = false,
    this.isHighlighted = false,
    this.onTap,
    this.onLongPress,
    this.onRemove,
  });

  @override
  State<PadCard> createState() => _PadCardState();
}

class _PadCardState extends State<PadCard> with TickerProviderStateMixin {
  static const double _maxRotationRadians = 0.012;
  static const double _maxOffsetX = 0.6;
  late final AnimationController _controller;
  late final Animation<double> _wiggle;
  late final AnimationController _deleteController;
  late final Animation<double> _deleteScale;
  late final AnimationController _restoreController;
  late final Animation<double> _restoreCurve;
  late final AnimationController _highlightFadeController;
  late final Animation<double> _highlightFade;
  late final AnimationController _highlightBreathController;
  bool _animationsDisabled = false;
  late final double _amplitudeFactor;
  late final double _speedFactor;
  late final double _phaseSign;

  @override
  void initState() {
    super.initState();
    final seed = widget.padItem.pad.id;
    _amplitudeFactor = 0.85 + ((seed % 5) * 0.05);
    _speedFactor = 0.9 + ((seed % 4) * 0.06);
    _phaseSign = seed.isEven ? 1.0 : -1.0;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (180 / _speedFactor).round()),
    );
    _wiggle = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.value = (seed % 100) / 100;
    _deleteController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _deleteScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.95).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.95, end: 1.0).chain(
          CurveTween(curve: Curves.easeOutBack),
        ),
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
    _syncAnimationState();
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
    if (oldWidget.isEditMode != widget.isEditMode) {
      _syncAnimationState();
    }
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

  void _syncAnimationState() {
    if (!mounted) return;
    if (widget.isEditMode && !_animationsDisabled) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0.0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disabled != _animationsDisabled) {
      _animationsDisabled = disabled;
      _syncAnimationState();
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
    _controller.dispose();
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

  @override
  Widget build(BuildContext context) {
    final deleteButton = widget.isEditMode && widget.onRemove != null
        ? Positioned(
            top: 6,
            right: 6,
            child: IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Supprimer le pad',
              onPressed: _handleRemoveTap,
              color: Colors.grey.shade600,
              splashRadius: 16,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          )
        : null;

    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: Listenable.merge([
        _wiggle,
        _restoreCurve,
        _highlightFadeController,
        _highlightBreathController,
      ]),
      builder: (context, child) {
        final t = (_wiggle.value * 2.0) - 1.0;
        final rotation = widget.isEditMode
            ? t * _maxRotationRadians * _phaseSign * _amplitudeFactor
            : 0.0;
        final offsetX = widget.isEditMode
            ? t * _maxOffsetX * _phaseSign * _amplitudeFactor
            : 0.0;
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

        return Transform.translate(
          offset: Offset(offsetX, 0),
          child: Transform.rotate(
            angle: rotation,
            child: Transform.scale(
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
                    ?deleteButton,
                  ],
                ),
              ),
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
          final blocked =
              widget.isEditMode || widget.isTapBlocked(widget.padItem);
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
