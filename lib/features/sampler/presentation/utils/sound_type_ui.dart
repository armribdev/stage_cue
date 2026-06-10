import 'package:flutter/material.dart';

import '../../domain/entities/sound.dart';

/// Libellés, icônes et couleurs d'avatar pour les types de sons.
extension SoundTypeUi on SoundType {
  String get label => switch (this) {
        SoundType.soundEffect => 'Bruitage',
        SoundType.music => 'Musique',
        SoundType.ambiance => 'Ambiance',
      };

  IconData get icon => switch (this) {
        SoundType.soundEffect => Icons.graphic_eq_rounded,
        SoundType.music => Icons.music_note_rounded,
        SoundType.ambiance => Icons.waves_rounded,
      };

  ({Color background, Color foreground}) avatarColors(ColorScheme scheme) =>
      switch (this) {
        SoundType.soundEffect => (
          background: scheme.tertiaryContainer,
          foreground: scheme.onTertiaryContainer,
        ),
        SoundType.music => (
          background: scheme.primaryContainer,
          foreground: scheme.onPrimaryContainer,
        ),
        SoundType.ambiance => (
          background: scheme.secondaryContainer,
          foreground: scheme.onSecondaryContainer,
        ),
      };
}

/// Filtre par type et libellé d'affichage (sons Drive non encore téléchargés exclus).
extension SoundClassificationUi on Sound {
  bool get isClassifiedForTypeFilter => type != null;

  bool matchesSoundType(SoundType filter) => type == filter;

  String get typeDisplayLabel => type?.label ?? 'Non classé';
}

/// Avatar circulaire avec l'icône du type de son.
/// [type] null = son non encore classé (icône neutre).
class SoundTypeAvatar extends StatelessWidget {
  final SoundType? type;
  final double radius;
  final double? iconSize;

  const SoundTypeAvatar({
    super.key,
    required this.type,
    this.radius = 20,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (type == null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: scheme.surfaceContainerHighest,
        child: Icon(
          Icons.help_outline_rounded,
          size: iconSize,
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    final colors = type!.avatarColors(scheme);
    return CircleAvatar(
      radius: radius,
      backgroundColor: colors.background,
      child: Icon(
        type!.icon,
        size: iconSize,
        color: colors.foreground,
      ),
    );
  }
}
