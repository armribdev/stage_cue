import 'package:flutter/material.dart';

/// Boutons d'action GO + secondaire, partagés entre sélecteurs de sons.
class SoundPickerActionButtons extends StatelessWidget {
  static const double _goButtonHeight = 36;
  static const double _secondaryButtonSize = 30;

  const SoundPickerActionButtons({
    super.key,
    required this.onGo,
    this.goEnabled = true,
    required this.onSecondary,
    this.secondaryEnabled = true,
    required this.secondaryIcon,
  });

  final VoidCallback? onGo;
  final bool goEnabled;
  final VoidCallback? onSecondary;
  final bool secondaryEnabled;
  final IconData secondaryIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(
          onPressed: goEnabled ? onGo : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, _goButtonHeight),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: const Text('GO'),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: _secondaryButtonSize,
          height: _secondaryButtonSize,
          child: IconButton(
            onPressed: secondaryEnabled ? onSecondary : null,
            icon: Icon(secondaryIcon, size: 18),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              shape: const CircleBorder(),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              hoverColor: scheme.onSurface.withValues(alpha: 0.08),
              foregroundColor: scheme.onSurfaceVariant,
              disabledForegroundColor:
                  scheme.onSurfaceVariant.withValues(alpha: 0.38),
            ),
            constraints: const BoxConstraints.tightFor(
              width: _secondaryButtonSize,
              height: _secondaryButtonSize,
            ),
          ),
        ),
      ],
    );
  }
}
