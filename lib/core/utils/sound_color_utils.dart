import 'package:flutter/material.dart';
import '../../features/sampler/domain/entities/sound.dart';

/// Couleur déterministe basée sur un seed numérique (typiquement l'id du son).
/// Utilisée comme fallback quand aucun [Sound.colorValue] n'est défini.
Color musicChipColor(int seed, ColorScheme scheme) {
  if (seed == 0) return scheme.primaryContainer;
  final hue = (seed * 47) % 360;
  return HSLColor.fromAHSL(1, hue.toDouble(), 0.45, 0.38).toColor();
}

/// Couleur effective d'un son : [Sound.colorValue] personnalisé s'il existe,
/// sinon couleur déterministe calculée depuis l'id.
Color soundEffectiveColor(Sound sound, ColorScheme scheme) {
  if (sound.colorValue != null) return Color(sound.colorValue!);
  return musicChipColor(sound.id, scheme);
}
