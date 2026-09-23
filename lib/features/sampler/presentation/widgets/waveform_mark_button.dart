import 'package:flutter/material.dart';

/// Marque Stage Cue : une forme d'onde dessinée en vectoriel (`CustomPainter`,
/// pas un asset image) — sert de repère de marque provisoire pour le bouton
/// menu, en attendant l'identité visuelle définitive. Volontairement sans
/// cadre/bordure (contrairement à [BoxedIconButton]) : une marque, pas une
/// action de barre d'outils — seul un effet de survol (couleur + échelle)
/// signale l'interactivité.
class WaveformMarkButton extends StatefulWidget {
  const WaveformMarkButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
  });

  final String tooltip;
  final VoidCallback? onPressed;

  @override
  State<WaveformMarkButton> createState() => _WaveformMarkButtonState();
}

class _WaveformMarkButtonState extends State<WaveformMarkButton> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _setHovered(true),
          onExit: (_) => _setHovered(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: AnimatedScale(
                  scale: _hovered ? 1.1 : 1.0,
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CustomPaint(
                      painter: _WaveformPainter(
                        color: _hovered
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.color});

  final Color color;

  // Hauteurs relatives des barres (silhouette d'onde asymétrique).
  static const _heights = [0.35, 0.65, 1.0, 0.5, 0.8, 0.3];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const gap = 1.5;
    final barCount = _heights.length;
    final barWidth = (size.width - gap * (barCount - 1)) / barCount;
    final radius = Radius.circular(barWidth / 2);
    final centerY = size.height / 2;

    for (var i = 0; i < barCount; i++) {
      final barHeight = size.height * _heights[i];
      final left = i * (barWidth + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(left + barWidth / 2, centerY),
          width: barWidth,
          height: barHeight,
        ),
        radius,
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.color != color;
}
