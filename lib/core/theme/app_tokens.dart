import 'package:flutter/material.dart';

/// Échelle de rayons harmonisée — sobre, desktop-first.
///
/// Valeurs intentionnellement basses : on évite le look "app mobile arrondie"
/// au profit d'un rendu d'outil pro (proche VS Code / Figma / Linear).
abstract final class AppRadius {
  /// Petits éléments : chips, badges, barres de progression.
  static const double xs = 2;

  /// Champs de saisie, boutons, petites cartes.
  static const double sm = 4;

  /// Cartes standard, tuiles de liste.
  static const double md = 6;

  /// Conteneurs majeurs : dialogues, modales, panneaux, pads.
  static const double lg = 8;

  static const BorderRadius radiusXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius radiusSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius radiusMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius radiusLg = BorderRadius.all(Radius.circular(lg));

  /// Rayon des pads du sampler — aligné sur [lg], remplace l'ancienne valeur
  /// (14) codée en dur qui détonnait avec le reste de l'échelle.
  static const double pad = lg;
  static const BorderRadius radiusPad = radiusLg;
}

/// Palette "Console Linear" — surfaces neutres quasi noires, un seul accent
/// violet, pas de couleur "Google". Valeurs exactes (pas dérivées d'un seed)
/// pour un rendu maîtrisé, cohérent avec la maquette validée.
abstract final class AppColors {
  static const Color bg = Color(0xFF0B0B0E);
  static const Color surface = Color(0xFF14151B);
  static const Color surface2 = Color(0xFF1B1C24);

  static const Color border = Color(0x17FFFFFF); // rgba(255,255,255,.09)
  static const Color borderStrong = Color(0x2EFFFFFF); // rgba(255,255,255,.18)

  static const Color text = Color(0xFFEDEDF1);
  static const Color textDim = Color(0xFF8B8D98);
  static const Color textFaint = Color(0xFF54565F);

  static const Color accent = Color(0xFF6E56CF);
  static const Color accentSoft = Color(0x296E56CF); // rgba(110,86,207,.16)
  static const Color accentLine = Color(0x806E56CF); // rgba(110,86,207,.5)

  static const Color success = Color(0xFF4CC38A);
  static const Color danger = Color(0xFFE5484D);
  static const Color warn = Color(0xFFE8A23B);
}

/// Réduction typographique appliquée sur poste desktop.
///
/// L'échelle Material par défaut (et nos propres tailles) reste pensée pour
/// une consultation tactile à bout de bras ; devant un écran de bureau, à
/// distance normale, souris/clavier en main, elle paraît surdimensionnée.
/// Appliqué globalement via `MaterialApp.builder` (voir `core/app/app.dart`)
/// selon `context.prefersDesktopUi` — jamais codé en dur par écran.
abstract final class AppTypography {
  static const double desktopFontScale = 0.88;
}

/// Styles de texte partagés de la direction "Console Linear".
abstract final class AppTextStyles {
  /// Libellé de section (cartes "Réglages", en-têtes Paramètres) — capitales
  /// espacées et discrètes plutôt qu'un gros titre de Card générique M3.
  /// Le texte doit être passé en majuscules par l'appelant (`.toUpperCase()`).
  static TextStyle sectionLabel(BuildContext context) => TextStyle(
    fontFamily: AppFonts.ui,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );
}

/// Familles de police de la direction "Console Linear" — Manrope pour
/// l'interface, JetBrains Mono pour tout affichage technique (durées,
/// compteurs, chemins, identifiants). Bundlées en assets locaux : pas de
/// dépendance réseau, l'app doit rester utilisable backstage hors ligne.
abstract final class AppFonts {
  static const String ui = 'Manrope';
  static const String mono = 'JetBrains Mono';

  /// Applique la police technique à un style existant (durées, compteurs…).
  static TextStyle monoStyle(TextStyle base) => base.copyWith(
    fontFamily: mono,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
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

/// Densité des menus contextuels (`PopupMenuButton`/`showMenu`) — les
/// valeurs Material par défaut (item de 48px de haut, ouverture en
/// fade/scale) sont pensées pour du tactile et détonnent en usage
/// souris/clavier. À passer explicitement sur chaque `PopupMenuItem`
/// (`height`/`padding`) et chaque `PopupMenuButton`/`showMenu`
/// (`popUpAnimationStyle: AnimationStyle.noAnimation`) — pas de levier
/// global côté thème pour la hauteur des items.
abstract final class AppMenu {
  static const double itemHeight = 32;
  static const EdgeInsets itemPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
  );
}

/// Comment les surfaces se distinguent les unes des autres.
///
/// Au lieu d'élévations Material 3 prononcées (ombres marquées), on privilégie
/// des bordures fines en `outlineVariant` pour un rendu plus plat et net,
/// cohérent avec une interface desktop dense.
abstract final class AppElevation {
  /// Largeur de bordure standard pour délimiter une surface.
  static const double borderWidth = 1.0;

  /// Opacité de la bordure sur `colorScheme.outlineVariant` (hairline —
  /// `AppColors.border`, en supposant `outlineVariant` blanc opaque).
  static const double borderOpacity = 0.09;

  /// Opacité de la bordure renforcée (`AppColors.borderStrong`) — pointillés
  /// des emplacements vides, séparateurs sur survol.
  static const double borderOpacityStrong = 0.18;

  /// Bordure standard — à utiliser sur cartes, panneaux, champs en repos.
  static BorderSide border(ColorScheme scheme) => BorderSide(
    color: scheme.outlineVariant.withValues(alpha: borderOpacity),
    width: borderWidth,
  );

  /// Bordure renforcée — pointillés, séparateurs marqués, états survolés.
  static BorderSide borderStrong(ColorScheme scheme) => BorderSide(
    color: scheme.outlineVariant.withValues(alpha: borderOpacityStrong),
    width: borderWidth,
  );

  /// Bordure mise en avant — focus, sélection, survol actif.
  static BorderSide emphasizedBorder(ColorScheme scheme) =>
      BorderSide(color: scheme.primary, width: 1.4);
}
