import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Poste desktop natif (Windows, macOS, Linux) — hors web.
bool isNativeDesktopPlatform() {
  return !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);
}

/// Seuils de largeur centralisés pour adapter la navigation et les layouts.
///
/// Alignés sur les conventions Material/Fluent : en dessous de [tablet], on
/// considère un téléphone (navigation compacte, plein écran) ; entre [tablet]
/// et [desktop], une tablette (navigation hybride) ; au-delà, un poste
/// desktop (sidebar persistante, panneaux, menus contextuels).
abstract final class AppBreakpoints {
  static const double tablet = 840;
  static const double desktop = 1200;
}

/// Catégorie d'appareil dérivée de la largeur disponible.
///
/// Sert de point d'entrée unique pour les décisions de layout — préférer
/// `context.deviceClass` aux comparaisons `if (width < x)` éparpillées.
enum DeviceClass {
  phone,
  tablet,
  desktop;

  factory DeviceClass.fromWidth(double width) {
    if (width >= AppBreakpoints.desktop) return DeviceClass.desktop;
    if (width >= AppBreakpoints.tablet) return DeviceClass.tablet;
    return DeviceClass.phone;
  }

  bool get isPhone => this == DeviceClass.phone;
  bool get isTablet => this == DeviceClass.tablet;
  bool get isDesktop => this == DeviceClass.desktop;

  /// Tablette ou desktop — utile pour les décisions binaires "large vs compact".
  bool get isAtLeastTablet => this != DeviceClass.phone;
}

extension DeviceClassContext on BuildContext {
  /// Catégorie d'appareil pour la largeur actuelle de l'écran.
  ///
  /// Distinct de [preferModalPresentation] : ce dernier décide modale-vs-page
  /// selon la plus petite dimension (`shortestSide`), tandis que [DeviceClass]
  /// pilote la structure de navigation selon la largeur disponible.
  DeviceClass get deviceClass =>
      DeviceClass.fromWidth(MediaQuery.sizeOf(this).width);

  /// Navigation barre desktop, drag souris, régie musique fixe, etc.
  ///
  /// Vrai sur poste natif (quelle que soit la largeur) ou fenêtre ≥ [AppBreakpoints.desktop].
  bool get prefersDesktopUi =>
      isNativeDesktopPlatform() || deviceClass.isDesktop;
}

/// Tablette, desktop et fenêtres larges : préférer une modale à une page plein écran.
bool preferModalPresentation(BuildContext context) {
  return MediaQuery.sizeOf(context).shortestSide >= 600;
}

/// Sélectionne un layout selon la catégorie d'appareil, avec repli en cascade
/// desktop → tablet → phone (un builder manquant utilise le suivant disponible).
///
/// Évite la prolifération de `LayoutBuilder` ad-hoc : chaque écran déclare ses
/// variantes de layout (souvent juste `phone` et `desktop`) sans dupliquer la
/// logique de seuils.
///
/// Exemple :
/// ```dart
/// AdaptiveLayout(
///   phone: (context) => _CompactSamplerLayout(...),
///   desktop: (context) => _SidebarSamplerLayout(...),
/// )
/// ```
class AdaptiveLayout extends StatelessWidget {
  const AdaptiveLayout({super.key, this.phone, this.tablet, this.desktop})
    : assert(
        phone != null || tablet != null || desktop != null,
        'AdaptiveLayout requiert au moins un builder (phone, tablet ou desktop).',
      );

  final WidgetBuilder? phone;
  final WidgetBuilder? tablet;
  final WidgetBuilder? desktop;

  @override
  Widget build(BuildContext context) {
    final deviceClass = context.deviceClass;
    final builder = switch (deviceClass) {
      DeviceClass.desktop => desktop ?? tablet ?? phone,
      DeviceClass.tablet => tablet ?? desktop ?? phone,
      DeviceClass.phone => phone ?? tablet ?? desktop,
    };
    return builder!(context);
  }
}
