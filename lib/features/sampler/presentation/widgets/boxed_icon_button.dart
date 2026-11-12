import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/stroke_icon.dart';

/// Icône d'action secondaire de barre d'outils — cadre + bordure fine plutôt
/// qu'une icône Material nue, pour rester dans le langage visuel "Console
/// Linear". Référence partagée pour toute action de barre du haut (recherche,
/// actualiser, etc.) — voir `.claude/rules/ui.md`. Pour une icône flottante
/// sur un pad (contraste dynamique selon la couleur du pad), voir plutôt le
/// style local de `pad_item.dart`, qui ne peut pas partager ce widget statique.
class BoxedIconButton extends StatefulWidget {
  final StrokeIconData? icon;

  /// Contenu alternatif à [icon] — ex. un logo (`Image.asset`) qu'aucune
  /// `StrokeIconData` ne peut représenter. Fournir l'un ou l'autre, jamais aucun.
  final Widget? child;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Cadre rond (cercle) plutôt qu'arrondi `sm` — le côté étant fixe, un rayon
  /// de [_size] / 2 donne un cercle parfait.
  final bool circular;

  /// `false` : icône nue, sans bordure ni fond (zone de clic inchangée) — pour
  /// une action qui doit rester discrète dans la barre, comme la recherche.
  /// Le survol n'ajoute alors aucun fond : seule l'icône s'éclaircit.
  final bool framed;

  /// Retire la marge horizontale de 4 px autour du bouton — pour des boutons
  /// sans cadre côte à côte, où elle s'ajoute à la zone de clic de 32 px et
  /// écarte trop les icônes.
  final bool compact;

  static const double _size = 32;

  const BoxedIconButton({
    super.key,
    this.icon,
    this.child,
    required this.tooltip,
    required this.onPressed,
    this.circular = false,
    this.framed = true,
    this.compact = false,
  }) : assert(
         (icon == null) != (child == null),
         'Fournir soit icon, soit child — jamais les deux, jamais aucun.',
       );

  @override
  State<BoxedIconButton> createState() => _BoxedIconButtonState();
}

class _BoxedIconButtonState extends State<BoxedIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final framed = widget.framed;
    final radius = widget.circular
        ? BorderRadius.circular(BoxedIconButton._size / 2)
        : AppRadius.radiusSm;
    final iconColor = !framed && _hovered && widget.onPressed != null
        ? scheme.onSurface
        : scheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.compact ? 0 : 4),
      child: Tooltip(
        message: widget.tooltip,
        child: InkWell(
          borderRadius: radius,
          onTap: widget.onPressed,
          // Sans cadre, le survol ne peint aucun fond (le thème en met un).
          hoverColor: framed ? null : Colors.transparent,
          onHover: framed ? null : (value) => setState(() => _hovered = value),
          child: Container(
            width: BoxedIconButton._size,
            height: BoxedIconButton._size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: framed
                  ? Border.fromBorderSide(AppElevation.border(scheme))
                  : null,
            ),
            child:
                widget.child ??
                switch (widget.icon) {
                  final icon? => StrokeIcon(icon, size: 16, color: iconColor),
                  null => const SizedBox.shrink(),
                },
          ),
        ),
      ),
    );
  }
}
