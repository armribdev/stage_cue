import 'package:flutter/material.dart';

import '../../domain/entities/sound.dart';
import '../utils/sound_type_ui.dart';

/// Sélecteur compact du type de son (bruitage, ambiance, musique).
class SoundTypePicker extends StatelessWidget {
  final SoundType? selected;
  final ValueChanged<SoundType> onChanged;

  const SoundTypePicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  static const _types = <SoundType>[
    SoundType.soundEffect,
    SoundType.ambiance,
    SoundType.music,
  ];

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<SoundType>(
      showSelectedIcon: false,
      emptySelectionAllowed: true,
      segments: [
        for (final type in _types)
          ButtonSegment<SoundType>(
            value: type,
            icon: Icon(type.icon, size: 18),
            tooltip: type.label,
          ),
      ],
      selected: selected != null ? {selected!} : {},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) onChanged(selection.first);
      },
    );
  }
}
