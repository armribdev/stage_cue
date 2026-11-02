import 'package:flutter/material.dart';

/// Bouton d'icône sans cadre au repos : seul le survol dessine un fond rond
/// (couleur de survol du thème). Le cercle fait [size] px — plus grand que
/// l'icône qu'il contient, pour laisser de l'air autour.
///
/// [builder] reçoit l'état de survol pour que le contenu puisse réagir
/// (teinte, échelle) ; un contenu statique l'ignore.
class CircleHoverButton extends StatefulWidget {
  const CircleHoverButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.builder,
  });

  /// Diamètre du fond de survol.
  static const double size = 40;

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<CircleHoverButton> createState() => _CircleHoverButtonState();
}

class _CircleHoverButtonState extends State<CircleHoverButton> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: CircleHoverButton.size,
            height: CircleHoverButton.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hovered ? Theme.of(context).hoverColor : null,
            ),
            child: widget.builder(context, _hovered),
          ),
        ),
      ),
    );
  }
}
