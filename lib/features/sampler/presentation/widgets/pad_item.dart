import 'package:flutter/material.dart';
import '../providers/sampler_provider.dart';
import 'pad_button.dart';

class PadItem extends StatefulWidget {
  final SoundItem soundItem;
  final bool isEditMode;
  final bool animateOnRestore;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onRemove;

  const PadItem({
    super.key,
    required this.soundItem,
    required this.isEditMode,
    this.animateOnRestore = false,
    this.onTap,
    this.onLongPress,
    this.onRemove,
  });

  @override
  State<PadItem> createState() => _PadItemState();
}

class _PadItemState extends State<PadItem> with TickerProviderStateMixin {
  static const double _maxRotationRadians = 0.012;
  static const double _maxOffsetX = 0.6;
  late final AnimationController _controller;
  late final Animation<double> _wiggle;
  late final AnimationController _deleteController;
  late final Animation<double> _deleteScale;
  late final AnimationController _restoreController;
  late final Animation<double> _restoreCurve;
  bool _animationsDisabled = false;
  late final double _amplitudeFactor;
  late final double _speedFactor;
  late final double _phaseSign;

  @override
  void initState() {
    super.initState();
    final seed = widget.soundItem.sound.id;
    _amplitudeFactor = 0.85 + ((seed % 5) * 0.05); // 0.85 -> 1.05
    _speedFactor = 0.9 + ((seed % 4) * 0.06); // 0.90 -> 1.08
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
    _restoreCurve = CurvedAnimation(parent: _restoreController, curve: Curves.easeOutCubic);
    if (widget.animateOnRestore) {
      _restoreController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant PadItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isEditMode != widget.isEditMode) {
      _syncAnimationState();
    }
    if (!oldWidget.animateOnRestore && widget.animateOnRestore && !_animationsDisabled) {
      _restoreController.forward(from: 0);
    }
  }

  void _syncAnimationState() {
    if (!mounted) {
      return;
    }
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
    final mediaQuery = MediaQuery.maybeOf(context);
    _animationsDisabled = mediaQuery?.disableAnimations ?? false;
    _syncAnimationState();
  }

  @override
  void dispose() {
    _restoreController.dispose();
    _deleteController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleRemoveTap() async {
    if (widget.onRemove == null) {
      return;
    }
    if (!_animationsDisabled) {
      await _deleteController.forward(from: 0);
    }
    widget.onRemove!.call();
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
              constraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
            ),
          )
        : null;

    return AnimatedBuilder(
      animation: _wiggle,
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
        return Transform.translate(
          offset: Offset(offsetX, 0),
          child: Transform.rotate(
            angle: rotation,
            child: Transform.scale(
              scale: deleteScale * (0.96 + (0.04 * restoreT)),
              child: Opacity(
                opacity: 0.6 + (0.4 * restoreT),
                child: child,
              ),
            ),
          ),
        );
      },
      child: Stack(
        children: [
          PadButton(
            key: ValueKey<int>(widget.soundItem.sound.id),
            soundItem: widget.soundItem,
            onTap: widget.onTap ?? () {},
            onLongPress: widget.onLongPress,
            onRemove: widget.onRemove ?? () {},
          ),
          if (deleteButton != null) deleteButton,
        ],
      ),
    );
  }
}
