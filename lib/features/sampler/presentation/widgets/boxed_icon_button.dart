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

  /// Cadre rond (cercle) plutôt qu'arrondi `sm` — le côté étant fixe, un rayon
  /// de [_size] / 2 donne un cercle parfait.
  final bool circular;

  static const double _size = 32;

  const BoxedIconButton({
    super.key,
    this.icon,
    this.child,
    required this.tooltip,
    required this.onPressed,
    this.circular = false,
  }) : assert(
         (icon == null) != (child == null),
         'Fournir soit icon, soit child — jamais les deux, jamais aucun.',
       );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = circular
        ? BorderRadius.circular(_size / 2)
        : AppRadius.radiusSm;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: Container(
            width: _size,
            height: _size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: radius,
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
