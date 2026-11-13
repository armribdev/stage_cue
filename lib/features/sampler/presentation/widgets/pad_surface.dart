import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

/// Surface d'un pad : carte à hairline qui réagit au survol (bordure
/// éclaircie), au clic (voile sombre) et à la lecture (halo [glow]). Les
/// changements de fond et de bordure sont fondus plutôt que commutés.
///
/// Pas de `Transform.scale` à l'enfoncement : le texte du pad serait rééchantillonné
/// (flou), cf. `pad_item.dart`.
class PadSurface extends StatefulWidget {
  final Color fill;
  final Color border;

  /// Couleur du halo de lecture ; `null` = pas de halo.
  final Color? glow;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  const PadSurface({
    super.key,
    required this.fill,
    required this.border,
    required this.child,
    this.glow,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<PadSurface> createState() => _PadSurfaceState();
}

class _PadSurfaceState extends State<PadSurface> {
  static const Duration _fade = Duration(milliseconds: 140);

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null || widget.onLongPress != null;
    final border = interactive && _hovered
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.2), widget.border)
        : widget.border;
    final glow = widget.glow;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Halo derrière la carte, rogné à l'extérieur de son contour : un
        // `BoxShadow` Flutter n'est pas rogné sous la boîte (contrairement au
        // CSS), il traverserait le fond translucide et teinterait l'intérieur.
        Positioned.fill(
          child: IgnorePointer(
            child: ClipPath(
              clipper: const _OutsidePadClipper(),
              child: AnimatedContainer(
                duration: _fade,
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  borderRadius: AppRadius.radiusPad,
                  boxShadow: glow == null
                      ? const []
                      : [
                          BoxShadow(
                            color: glow.withValues(alpha: 0.3),
                            blurRadius: 16,
                          ),
                        ],
                ),
              ),
            ),
          ),
        ),
        _buildCard(interactive: interactive, border: border),
      ],
    );
  }

  Widget _buildCard({required bool interactive, required Color border}) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: widget.fill),
      duration: _fade,
      builder: (context, fill, child) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: border),
        duration: _fade,
        builder: (context, border, child) => Card(
          elevation: 0,
          // Le clip épouse les coins arrondis : la progression collée au
          // bord bas ne déborde pas.
          clipBehavior: Clip.antiAlias,
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.radiusPad,
            side: BorderSide(color: border ?? widget.border),
          ),
          child: child,
        ),
        child: child,
      ),
      child: interactive
          ? InkWell(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              borderRadius: AppRadius.radiusPad,
              highlightColor: Colors.black.withValues(alpha: 0.16),
              onHover: (value) => setState(() => _hovered = value),
              child: widget.child,
            )
          : widget.child,
    );
  }
}

/// Découpe tout sauf le contour du pad : ne laisse passer que la partie
/// extérieure du halo de lecture.
class _OutsidePadClipper extends CustomClipper<Path> {
  const _OutsidePadClipper();

  @override
  Path getClip(Size size) {
    final pad = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(AppRadius.pad),
    );
    return Path.combine(
      PathOperation.difference,
      Path()..addRect((Offset.zero & size).inflate(64)),
      Path()..addRRect(pad),
    );
  }

  @override
  bool shouldReclip(_OutsidePadClipper oldClipper) => false;
}
