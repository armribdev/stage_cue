import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/stroke_icon.dart';

/// Pastilles de choix de la couleur par défaut d'un son. `null` = « D » (pas de
/// couleur propre, on retombe sur celle du type).
class SoundColorPicker extends StatelessWidget {
  static const List<Color> _choices = <Color>[
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.red,
    Colors.teal,
    Colors.brown,
    Colors.grey,
  ];

  final int? value;
  final ValueChanged<int?> onChanged;

  const SoundColorPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _swatch(
          context,
          label: 'D',
          color: null,
          isSelected: value == null,
          onTap: () => onChanged(null),
        ),
        for (final color in _choices)
          _swatch(
            context,
            color: color,
            isSelected: value == color.toARGB32(),
            onTap: () => onChanged(color.toARGB32()),
          ),
      ],
    );
  }

  Widget _swatch(
    BuildContext context, {
    Color? color,
    required bool isSelected,
    required VoidCallback onTap,
    String? label,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? scheme.surfaceContainerHighest;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: effectiveColor,
          border: Border.all(
            color: isSelected ? scheme.primary : scheme.outlineVariant,
            width: isSelected ? 3 : 1,
          ),
        ),
        child: isSelected
            ? StrokeIcon(
                AppIcons.check,
                size: AppIconSize.sm,
                color: color == null
                    ? scheme.onSurfaceVariant
                    : _checkmarkColor(effectiveColor),
              )
            : (label != null
                  ? Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null),
      ),
    );
  }

  Color _checkmarkColor(Color bg) =>
      bg.computeLuminance() > 0.6 ? Colors.black : Colors.white;
}
