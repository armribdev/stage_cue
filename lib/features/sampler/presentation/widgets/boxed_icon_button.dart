import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

/// Icône d'action secondaire de barre d'outils — cadre + bordure fine plutôt
/// qu'une icône Material nue, pour rester dans le langage visuel "Console
/// Linear". Référence partagée pour toute action de barre du haut (recherche,
/// actualiser, etc.) — voir `.claude/rules/ui.md`. Pour une icône flottante
/// sur un pad (contraste dynamique selon la couleur du pad), voir plutôt le
/// style local de `pad_item.dart`, qui ne peut pas partager ce widget statique.
class BoxedIconButton extends StatelessWidget {
  final IconData? icon;

  /// Contenu alternatif à [icon] — ex. un logo (`Image.asset`) qu'aucune
  /// `IconData` ne peut représenter. Fournir l'un ou l'autre, jamais aucun.
  final Widget? child;
  final String tooltip;
  final VoidCallback? onPressed;

  const BoxedIconButton({
    super.key,
    this.icon,
    this.child,
    required this.tooltip,
    required this.onPressed,
  }) : assert(
         (icon == null) != (child == null),
         'Fournir soit icon, soit child — jamais les deux, jamais aucun.',
       );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: AppRadius.radiusSm,
          onTap: onPressed,
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: AppRadius.radiusSm,
              border: Border.fromBorderSide(AppElevation.border(scheme)),
            ),
            child:
                child ?? Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
