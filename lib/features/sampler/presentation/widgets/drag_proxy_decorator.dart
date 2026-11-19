import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

/// Rendu d'une ligne en cours de glissement dans une `ReorderableListView`.
///
/// Pas d'élévation Material (surfaceTint neutralisé pour la direction
/// "Console Linear") : le retour visuel du drag vient d'un éclaircissement
/// plat de la surface plutôt que d'une ombre.
Widget dragProxyDecorator(
  Widget child,
  int index,
  Animation<double> animation,
) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, child) {
      final baseColor = Theme.of(context).canvasColor;
      final animValue = Curves.easeInOut.transform(animation.value);
      return Material(
        color: Color.lerp(baseColor, AppColors.surface2, animValue),
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        borderRadius: AppRadius.radiusLg,
        child: child,
      );
    },
    child: child,
  );
}
