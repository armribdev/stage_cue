import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/stroke_icon.dart';
import '../../domain/entities/pad.dart';

/// Choix du mode de lecture d'un multipad : aléatoire ou séquentiel. Partagé
/// par les détails d'un pad et l'éditeur d'un multipad enregistré.
class PadPlayModeSelector extends StatelessWidget {
  final PadPlayMode value;
  final ValueChanged<PadPlayMode> onChanged;

  const PadPlayModeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<PadPlayMode>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: PadPlayMode.random,
          icon: StrokeIcon(AppIcons.shuffle, size: 16),
          label: Text('Aléatoire'),
        ),
        ButtonSegment(
          value: PadPlayMode.sequential,
          icon: StrokeIcon(AppIcons.repeatOne, size: 16),
          label: Text('Séquentiel'),
        ),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}
