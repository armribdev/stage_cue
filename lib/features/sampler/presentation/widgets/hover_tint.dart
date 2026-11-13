import 'package:flutter/material.dart';

/// Zone cliquable sans fond ni ripple : le contenu se teinte lui-même via
/// l'état de survol fourni à [builder] (direction "Console Linear", cf.
/// décision 0023). Le `GestureDetector` opaque capte le tap avant celui du pad.
class HoverTint extends StatefulWidget {
  const HoverTint({super.key, required this.onTap, required this.builder});

  final VoidCallback? onTap;
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<HoverTint> createState() => _HoverTintState();
}

class _HoverTintState extends State<HoverTint> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.builder(context, _hovered),
      ),
    );
  }
}
