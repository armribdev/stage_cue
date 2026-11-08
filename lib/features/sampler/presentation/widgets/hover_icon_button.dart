import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

/// Bouton d'icône sans cadre au repos : seul le survol dessine un fond, un
/// carré à coins [AppRadius.md] qui apparaît en fondu (pas de disque, pas de
/// ripple, pas d'agrandissement — le disque + le zoom sont la signature
/// Material que la direction "Console Linear" écarte, cf. décision 0023).
///
/// [builder] reçoit l'état de survol pour que le contenu puisse réagir
/// (teinte) ; un contenu statique l'ignore.
class HoverIconButton extends StatefulWidget {
  const HoverIconButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.builder,
  });

  /// Côté du fond de survol — aligné sur `BoxedIconButton`.
  static const double size = 32;

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<HoverIconButton> {
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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            width: HoverIconButton.size,
            height: HoverIconButton.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: AppRadius.radiusMd,
              color: _hovered
                  ? Theme.of(context).hoverColor
                  : Colors.transparent,
            ),
            child: widget.builder(context, _hovered),
          ),
        ),
      ),
    );
  }
}
