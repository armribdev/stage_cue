import 'package:flutter/widgets.dart';

/// Glyphes de transport (lecture, pause, suivant, stop, éjecter).
enum TransportGlyph { play, pause, next, stop, eject }

/// Icône de transport **pleine aux angles arrondis** — la convention des
/// lecteurs modernes (Spotify, Apple Music).
///
/// Lucide n'a pas de variante pleine ([décision 0034](../../../docs/decisions/0034-icones-lucide-via-appicons.md)),
/// et un triangle de lecture au trait fin se lit comme un pictogramme de
/// formulaire plutôt que comme un bouton de régie : ces quatre glyphes sont
/// donc dessinés ici, sur la même grille de 24 que `AppIcons`.
///
/// Se pose comme un [Icon] : taille et couleur viennent de l'[IconTheme]
/// (donc d'un `IconButton`, état désactivé compris) sauf si on les passe.
class TransportIcon extends StatelessWidget {
  final TransportGlyph glyph;
  final double? size;
  final Color? color;

  const TransportIcon(this.glyph, {super.key, this.size, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final resolvedSize = size ?? theme.size ?? 24.0;
    final base = color ?? theme.color;
    final resolvedColor = base?.withValues(
      alpha: (theme.opacity ?? 1) * base.a,
    );

    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: resolvedSize,
        child: resolvedColor == null
            ? null
            : CustomPaint(painter: _TransportPainter(glyph, resolvedColor)),
      ),
    );
  }
}

class _TransportPainter extends CustomPainter {
  final TransportGlyph glyph;
  final Color color;

  const _TransportPainter(this.glyph, this.color);

  /// Épaisseur du contour de même couleur qui arrondit les angles du
  /// triangle : les sommets sont rentrés d'autant pour garder l'emprise.
  static const _round = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final fill = Paint()..color = color;
    final rounded = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _round
      ..strokeJoin = StrokeJoin.round;

    void roundedTriangle(Offset a, Offset b, Offset c) {
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(c.dx, c.dy)
        ..close();
      canvas
        ..drawPath(path, fill)
        ..drawPath(path, rounded);
    }

    void bar(double left, double right, {double radius = 1.5}) {
      canvas.drawRRect(
        RRect.fromLTRBR(left, 5, right, 19, Radius.circular(radius)),
        fill,
      );
    }

    switch (glyph) {
      case TransportGlyph.play:
        roundedTriangle(
          const Offset(8, 6.2),
          const Offset(8, 17.8),
          const Offset(18, 12),
        );
      case TransportGlyph.pause:
        bar(6, 10);
        bar(14, 18);
      case TransportGlyph.next:
        roundedTriangle(
          const Offset(6.5, 6.4),
          const Offset(6.5, 17.6),
          const Offset(15, 12),
        );
        bar(17, 20, radius: 1.2);
      case TransportGlyph.eject:
        roundedTriangle(
          const Offset(6.6, 12.6),
          const Offset(17.4, 12.6),
          const Offset(12, 5.2),
        );
        canvas.drawRRect(
          RRect.fromLTRBR(5.5, 16.5, 18.5, 19, const Radius.circular(1.2)),
          fill,
        );
      case TransportGlyph.stop:
        canvas.drawRRect(
          RRect.fromLTRBR(6, 6, 18, 18, const Radius.circular(2.5)),
          fill,
        );
    }
  }

  @override
  bool shouldRepaint(_TransportPainter old) =>
      old.glyph != glyph || old.color != color;
}
