import 'package:flutter/material.dart';

/// Entrée des dialogues et modales : fondu + remontée de [_rise] px, courte et
/// sans rebond. Le `showDialog` Material se contente d'un fondu de 150 ms, ce
/// qui lit comme du Material par défaut.
///
/// Pas de `scale` : il rééchantillonnerait le texte du dialogue pendant toute
/// l'animation. Sans effet si le système demande de réduire les animations.
Widget appDialogTransition(
  BuildContext context,
  Animation<double> animation,
  Widget child,
) {
  if (MediaQuery.disableAnimationsOf(context)) return child;
  final curved = animation.drive(CurveTween(curve: Curves.easeOutCubic));
  return FadeTransition(
    opacity: curved,
    child: AnimatedBuilder(
      animation: curved,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _rise * (1 - curved.value)),
        child: child,
      ),
      child: child,
    ),
  );
}

const double _rise = 8;

/// Remplace `showDialog` : mêmes capacités (thèmes capturés, zone sûre,
/// barrière, libellé d'accessibilité), transition [appDialogTransition].
/// À utiliser pour tout dialogue — jamais `showDialog` direct.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push<T>(
    _AppDialogRoute<T>(
      context: context,
      builder: builder,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierDismissible: barrierDismissible,
    ),
  );
}

class _AppDialogRoute<T> extends DialogRoute<T> {
  _AppDialogRoute({
    required super.context,
    required super.builder,
    super.themes,
    super.barrierDismissible,
  });

  // Sortie plus vive que l'entrée : le dialogue ne doit jamais retarder la
  // reprise du jeu en live.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 160);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 100);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => appDialogTransition(context, animation, child);
}
