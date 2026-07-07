import 'package:flutter/material.dart';

/// Texte sur une ligne : ellipse si tronqué, défilement horizontal si [animate].
class ScrollingTextSpan extends StatelessWidget {
  const ScrollingTextSpan({
    super.key,
    required this.span,
    required this.animate,
    this.style,
  });

  final InlineSpan span;
  final bool animate;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final style = this.style ?? DefaultTextStyle.of(context).style;
    final direction = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) {
          return Text.rich(TextSpan(style: style, children: [span]), maxLines: 1);
        }

        final richSpan = TextSpan(style: style, children: [span]);
        final textWidth = _measureTextWidth(richSpan, direction, textScaler);
        final overflow = textWidth - constraints.maxWidth;

        return _ScrollingTextSpanBody(
          span: richSpan,
          overflow: overflow,
          shouldScroll: animate && overflow > 1,
        );
      },
    );
  }

  static double _measureTextWidth(
    TextSpan span,
    TextDirection direction,
    TextScaler textScaler,
  ) {
    final painter = TextPainter(
      text: span,
      textDirection: direction,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    return painter.size.width;
  }
}

class _ScrollingTextSpanBody extends StatefulWidget {
  const _ScrollingTextSpanBody({
    required this.span,
    required this.overflow,
    required this.shouldScroll,
  });

  final TextSpan span;
  final double overflow;
  final bool shouldScroll;

  @override
  State<_ScrollingTextSpanBody> createState() => _ScrollingTextSpanBodyState();
}

class _ScrollingTextSpanBodyState extends State<_ScrollingTextSpanBody>
    with TickerProviderStateMixin {
  // Pause une fois le texte défilé jusqu'au bout, avant de revenir au début.
  static const _pauseAtEnd = Duration(milliseconds: 700);
  // Pause au début, une fois revenu au début, avant de redéfiler.
  static const _pauseAtStart = Duration(milliseconds: 900);

  AnimationController? _controller;
  Duration _scrollDuration = Duration.zero;

  @override
  void didUpdateWidget(_ScrollingTextSpanBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _syncController() {
    if (!widget.shouldScroll) {
      _controller?.dispose();
      _controller = null;
      return;
    }

    final scrollMs = (widget.overflow * 35).round().clamp(2500, 10000);
    final scrollDuration = Duration(milliseconds: scrollMs);
    final totalDuration = scrollDuration + _pauseAtEnd + _pauseAtStart;
    // Position dans le cycle où commence la pause du début, pour qu'un
    // contrôleur qui démarre (nouvelle sélection, ouverture de l'overlay...)
    // marque toujours cette pause avant de défiler.
    final startPauseT =
        (scrollDuration + _pauseAtEnd).inMicroseconds / totalDuration.inMicroseconds;

    if (_controller == null) {
      _scrollDuration = scrollDuration;
      _controller = AnimationController(vsync: this, duration: totalDuration)
        ..value = startPauseT
        ..repeat();
      return;
    }

    if (_scrollDuration != scrollDuration) {
      _scrollDuration = scrollDuration;
      _controller!
        ..duration = totalDuration
        ..value = startPauseT
        ..repeat();
    } else if (!_controller!.isAnimating) {
      _controller!.value = startPauseT;
      _controller!.repeat();
    }
  }

  /// Défile de 0 à 1 immédiatement, marque une pause en fin de course,
  /// puis revient d'un coup au début et marque une pause avant de redéfiler.
  double _progressFor(double t) {
    final total = _scrollDuration + _pauseAtEnd + _pauseAtStart;
    final scrollFraction = _scrollDuration.inMicroseconds / total.inMicroseconds;
    final endPauseFraction = _pauseAtEnd.inMicroseconds / total.inMicroseconds;

    if (t < scrollFraction) {
      return t / scrollFraction;
    }
    if (t < scrollFraction + endPauseFraction) {
      return 1;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    _syncController();

    if (widget.overflow <= 1) {
      return Text.rich(widget.span, maxLines: 1, overflow: TextOverflow.clip);
    }

    if (!widget.shouldScroll) {
      return Text.rich(
        widget.span,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final controller = _controller!;
    return ClipRect(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final progress = _progressFor(controller.value);
          return Transform.translate(
            offset: Offset(-widget.overflow * progress, 0),
            child: Text.rich(
              widget.span,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
            ),
          );
        },
      ),
    );
  }
}
