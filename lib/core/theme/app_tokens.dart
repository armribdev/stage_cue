import 'package:flutter/material.dart';

/// Échelle de rayons harmonisée — sobre, desktop-first.
///
/// Valeurs intentionnellement basses : on évite le look "app mobile arrondie"
/// au profit d'un rendu d'outil pro (proche VS Code / Figma).
abstract final class AppRadius {
  /// Petits éléments : chips, badges, barres de progression.
  static const double xs = 2;

  /// Champs de saisie, boutons, petites cartes.
  static const double sm = 4;

  /// Cartes standard, pads, tuiles de liste.
  static const double md = 6;

  /// Conteneurs majeurs : dialogues, modales, panneaux.
  static const double lg = 8;

  static const BorderRadius radiusXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius radiusSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius radiusMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius radiusLg = BorderRadius.all(Radius.circular(lg));
}

/// Échelle d'espacement harmonisée — remplace les `EdgeInsets` à valeurs
/// magiques répétées dans les écrans et widgets.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Comment les surfaces se distinguent les unes des autres.
///
/// Au lieu d'élévations Material 3 prononcées (ombres marquées), on privilégie
/// des bordures fines en `outlineVariant` pour un rendu plus plat et net,
/// cohérent avec une interface desktop dense.
abstract final class AppElevation {
  /// Largeur de bordure standard pour délimiter une surface.
  static const double borderWidth = 1.0;

  /// Opacité de la bordure sur `colorScheme.outlineVariant`.
  static const double borderOpacity = 0.4;

  /// Bordure standard — à utiliser sur cartes, panneaux, champs en repos.
  static BorderSide border(ColorScheme scheme) => BorderSide(
    color: scheme.outlineVariant.withValues(alpha: borderOpacity),
    width: borderWidth,
  );

  /// Bordure mise en avant — focus, sélection, survol actif.
  static BorderSide emphasizedBorder(ColorScheme scheme) =>
      BorderSide(color: scheme.primary, width: 1.4);
}
