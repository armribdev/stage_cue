import 'package:flutter/widgets.dart';
import 'package:path_drawing/path_drawing.dart';

/// Icône Lucide décrite par ses tracés SVG (grille de 24, trait arrondi).
///
/// Pourquoi pas une police : les glyphes de police sont rasterisés au pixel près par Skia, sans
/// anti-aliasing exploitable sur un trait de ~1 px (escaliers visibles sous
/// Windows à 100 %). Un `Path` passe par le rasteriseur de formes, qui calcule
/// la couverture réelle de chaque pixel.
class StrokeIconData {
  /// Un attribut `d` SVG par tracé, tel que publié par Lucide.
  final List<String> paths;

  /// Épaisseur sur la grille de 24. 1,75 donne ~1,2 px à 16 px et ~1,5 px à
  /// 20 px : plus fin (1,5 → 1 px à 16 px), le trait tombe à cheval sur deux
  /// pixels et se lit grisé ; plus épais (2), les icônes détaillées (théâtre,
  /// bibliothèque) se bouchent à 16 px.
  final double strokeWidth;

  const StrokeIconData(this.paths, {this.strokeWidth = 1.75});
}

/// Se pose comme un [Icon] : taille et couleur viennent de l'[IconTheme] sauf
/// si on les passe.
class StrokeIcon extends StatelessWidget {
  final StrokeIconData data;
  final double? size;
  final Color? color;

  /// Libellé lu par les lecteurs d'écran ; sans lui l'icône est décorative.
  final String? semanticLabel;

  const StrokeIcon(
    this.data, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  static final Expando<Path> _parsed = Expando<Path>('StrokeIcon paths');

  static Path _pathOf(StrokeIconData data) {
    return _parsed[data] ??= () {
      final path = Path();
      for (final d in data.paths) {
        path.addPath(parseSvgPathData(d), Offset.zero);
      }
      return path;
    }();
  }

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final resolvedSize = size ?? theme.size ?? 24.0;
    final base = color ?? theme.color;
    final resolvedColor = base?.withValues(
      alpha: (theme.opacity ?? 1) * base.a,
    );

    final box = SizedBox.square(
      dimension: resolvedSize,
      child: resolvedColor == null
          ? null
          : CustomPaint(
              painter: _StrokeIconPainter(
                _pathOf(data),
                data.strokeWidth,
                resolvedColor,
                resolvedSize,
              ),
            ),
    );
    final label = semanticLabel;
    if (label == null) return ExcludeSemantics(child: box);
    return Semantics(label: label, image: true, child: box);
  }
}

class _StrokeIconPainter extends CustomPainter {
  final Path path;
  final double strokeWidth;
  final Color color;

  /// Taille demandée. La boîte peut être plus grande (parent à contraintes
  /// serrées : `SizedBox`, `Container` à taille fixe) : comme [Icon], le tracé
  /// garde sa taille et se centre au lieu de s'étirer.
  final double iconSize;

  const _StrokeIconPainter(
    this.path,
    this.strokeWidth,
    this.color,
    this.iconSize,
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate((size.width - iconSize) / 2, (size.height - iconSize) / 2);
    canvas.scale(iconSize / 24);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_StrokeIconPainter old) =>
      old.path != path ||
      old.strokeWidth != strokeWidth ||
      old.color != color ||
      old.iconSize != iconSize;
}
