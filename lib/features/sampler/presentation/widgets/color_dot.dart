import 'package:flutter/material.dart';

/// Pastille ronde pleine : repère de couleur (scène, tag, état) posé devant un
/// libellé.
class ColorDot extends StatelessWidget {
  const ColorDot({super.key, required this.color, this.size = 6});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
