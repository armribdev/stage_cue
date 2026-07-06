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

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) {
          return Text.rich(TextSpan(style: style, children: [span]), maxLines: 1);
        }

        final richSpan = TextSpan(style: style, children: [span]);
        final textWidth = _measureTextWidth(richSpan, direction);
        final overflow = textWidth - constraints.maxWidth;

        return _ScrollingTextSpanBody(
          span: richSpan,
          overflow: overflow,
          shouldScroll: animate && overflow > 1,
        );
      },
    );
  }

  static double _measureTextWidth(TextSpan span, TextDirection direction) {
    final painter = TextPainter(
      text: span,
      textDirection: direction,
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
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

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

    final durationMs = (widget.overflow * 35).round().clamp(2500, 10000);
    final duration = Duration(milliseconds: durationMs);

    if (_controller == null) {
      _controller = AnimationController(vsync: this, duration: duration)
        ..repeat(reverse: true);
      return;
    }

    if (_controller!.duration != duration) {
      _controller!
        ..duration = duration
        ..repeat(reverse: true);
    } else if (!_controller!.isAnimating) {
      _controller!.repeat(reverse: true);
    }
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
          return Transform.translate(
            offset: Offset(-widget.overflow * controller.value, 0),
            child: Text.rich(widget.span, maxLines: 1, softWrap: false),
          );
        },
      ),
    );
  }
}
