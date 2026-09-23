import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';

/// Contour pointillé pour les emplacements vides (ajout de pad, brouillon).
class DashedRoundedRectPainter extends CustomPainter {
  const DashedRoundedRectPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;
  static const _strokeWidth = 1.0;
  static const _dashLength = 5.0;
  static const _dashGap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;

    final halfStroke = _strokeWidth / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        halfStroke,
        halfStroke,
        size.width - _strokeWidth,
        size.height - _strokeWidth,
      ),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dashLength).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += _dashLength + _dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedRoundedRectPainter oldDelegate) {
    return color != oldDelegate.color || radius != oldDelegate.radius;
  }
}

/// Cadre pointillé partagé entre le bouton « + » et les pads brouillon.
class DashedSlotFrame extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double borderRadius;

  const DashedSlotFrame({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = AppRadius.pad,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dashColor = AppElevation.borderStrong(scheme).color;

    Widget content = Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: CustomPaint(
        foregroundPainter: DashedRoundedRectPainter(
          color: dashColor,
          radius: borderRadius,
        ),
        child: child,
      ),
    );

    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: content,
      );
    }

    return content;
  }
}
