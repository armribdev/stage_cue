import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/stroke_icon.dart';

/// Cotes d'une étiquette selon sa densité (normale ou compacte).
class _PillMetrics {
  final double fontSize;
  final double hPad;
  final double vPad;

  /// Côté de la zone de clic de la croix / du « + » : assez grande pour être
  /// visée sans loucher, sans agrandir l'étiquette (elle tient dans sa hauteur).
  final double actionBox;
  final double actionIcon;

  const _PillMetrics.regular()
    : fontSize = 14,
      hPad = 12,
      vPad = 7,
      actionBox = 22,
      actionIcon = 13;

  const _PillMetrics.compact()
    : fontSize = 10,
      hPad = 6,
      vPad = 2,
      actionBox = 14,
      actionIcon = 9;

  factory _PillMetrics.of({required bool compact}) =>
      compact ? const _PillMetrics.compact() : const _PillMetrics.regular();
}

TextStyle _labelStyle(ColorScheme scheme, _PillMetrics m) => TextStyle(
  fontFamily: AppFonts.ui,
  fontSize: m.fontSize,
  fontWeight: FontWeight.w500,
  height: 1.25,
  color: scheme.onSurface,
);

/// Étiquette d'un tag — unique rendu des tags dans l'app (éditeur, suggestions,
/// bibliothèque, sélecteur, détails de pad).
///
/// Langage « Console Linear » plutôt que puce Material : un fond teinté de la
/// couleur de catégorie, un filet de ton, un texte neutre lisible — pas de
/// forme en pilule ni de pastille en plus de la couleur.
///
/// Deux tailles, choisies par l'écran qui l'affiche (jamais par la largeur) :
/// normale pour les écrans de détail, [compact] (texte et marges réduits) pour
/// les endroits où la place manque, comme la recherche rapide.
///
/// Options : [onRemove] ajoute une croix (tag posé sur un son), avec sa zone de
/// clic et son survol ; [suggestion] allège le fond et le filet et pose un « + »
/// à la place de la croix, car ce n'est pas encore un tag (décision 0031) —
/// mais l'étiquette garde exactement le gabarit d'un tag posé.
class TagPill extends StatefulWidget {
  final InlineSpan label;

  /// Couleur de catégorie ; `null` = neutre.
  final Color? color;
  final bool compact;
  final bool suggestion;

  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  /// Libellé accessible de la croix ; requis avec [onRemove].
  final String? removeTooltip;

  TagPill({
    super.key,
    required String label,
    this.color,
    this.compact = false,
    this.suggestion = false,
    this.onTap,
    this.onRemove,
    this.removeTooltip,
  }) : label = TextSpan(text: label);

  /// Variante dont le libellé est déjà un span (surlignage de recherche).
  const TagPill.rich({
    super.key,
    required this.label,
    this.color,
    this.compact = false,
    this.suggestion = false,
    this.onTap,
    this.onRemove,
    this.removeTooltip,
  });

  @override
  State<TagPill> createState() => _TagPillState();
}

class _TagPillState extends State<TagPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = widget.color ?? scheme.onSurfaceVariant;
    final interactive = widget.onTap != null;
    final m = _PillMetrics.of(compact: widget.compact);

    final pill = _buildPill(scheme, tone, m, interactive);

    if (!interactive) return pill;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: pill,
        ),
      ),
    );
  }

  Widget _buildPill(
    ColorScheme scheme,
    Color tone,
    _PillMetrics m,
    bool interactive,
  ) {
    final hovered = _hovered && interactive;
    // La couleur de catégorie porte l'étiquette entière (fond + filet) : pas de
    // pastille en plus. Sans couleur, teinte neutre discrète.
    //
    // Une suggestion est le MÊME widget qu'un tag posé (mêmes dimensions, même
    // texte, même rayon) : seuls le fond et le filet sont plus légers, et un
    // « + » prend la place de la croix. Elle devient un tag sans changer de
    // forme.
    final colored = widget.color != null;
    final background = widget.suggestion
        ? tone.withAlpha(colored ? (hovered ? 48 : 22) : (hovered ? 28 : 10))
        : tone.withAlpha(colored ? (hovered ? 82 : 60) : (hovered ? 36 : 22));
    final side = widget.suggestion
        ? BorderSide(
            color: tone.withAlpha(
              colored ? (hovered ? 190 : 90) : (hovered ? 80 : 30),
            ),
          )
        : BorderSide(color: tone.withAlpha(colored ? 150 : 40));
    final textStyle = _labelStyle(scheme, m);
    final trailing = widget.onRemove != null
        ? _PillAction(
            icon: AppIcons.close,
            tooltip: widget.removeTooltip ?? 'Retirer',
            box: m.actionBox,
            iconSize: m.actionIcon,
            onPressed: widget.onRemove,
          )
        : (widget.suggestion && interactive)
        ? _PillAction(
            icon: AppIcons.add,
            box: m.actionBox,
            iconSize: m.actionIcon,
            highlighted: hovered,
          )
        : null;

    // La zone de l'action est plus haute que le texte : on rogne d'autant le
    // padding vertical pour que l'étiquette garde la même hauteur avec ou sans
    // elle, et on cale l'action à égale distance du haut, du bas et du bord
    // droit.
    final textHeight = m.fontSize * 1.25;
    final vPad = trailing == null
        ? m.vPad
        : (m.vPad - (m.actionBox - textHeight) / 2).clamp(0.0, m.vPad);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: widget.compact ? AppRadius.radiusSm : AppRadius.radiusMd,
        border: Border.fromBorderSide(side),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          m.hPad,
          vPad,
          trailing == null ? m.hPad : vPad,
          vPad,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text.rich(
                widget.label,
                style: textStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 2), trailing],
          ],
        ),
      ),
    );
  }
}

/// Action en bout d'étiquette : la croix qui retire un tag posé (cliquable),
/// ou le « + » d'une suggestion (décoratif : c'est toute l'étiquette qui
/// s'ajoute au toucher).
///
/// La croix a une vraie zone de clic ([box]) et réagit au survol par un glyphe
/// plus contrasté et le curseur main — jamais de fond. Pas de rouge : retirer
/// un tag est une action banale (ui.md).
class _PillAction extends StatefulWidget {
  final StrokeIconData icon;
  final double box;
  final double iconSize;
  final String? tooltip;
  final VoidCallback? onPressed;

  /// Pour le « + » décoratif : l'étiquette entière est survolée.
  final bool highlighted;

  const _PillAction({
    required this.icon,
    required this.box,
    required this.iconSize,
    this.tooltip,
    this.onPressed,
    this.highlighted = false,
  });

  @override
  State<_PillAction> createState() => _PillActionState();
}

class _PillActionState extends State<_PillAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clickable = widget.onPressed != null;
    final active = clickable ? _hovered : widget.highlighted;
    final glyph = StrokeIcon(
      widget.icon,
      size: widget.iconSize,
      color: active ? scheme.onSurface : scheme.onSurfaceVariant,
    );
    final box = SizedBox.square(
      dimension: widget.box,
      child: Center(child: glyph),
    );
    if (!clickable) return box;
    return Tooltip(
      message: widget.tooltip ?? 'Retirer',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Semantics(
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: box,
          ),
        ),
      ),
    );
  }
}

/// Un tag à afficher dans une [TagPillRow].
typedef TagPillSpec = ({InlineSpan label, Color? color});

/// Rangée d'étiquettes sur une seule ligne : les [maxVisible] premières, puis
/// « +N » pour le reste. Le texte d'une étiquette s'abrège (« … ») plutôt que
/// de déborder si la ligne est trop étroite.
class TagPillRow extends StatelessWidget {
  final List<TagPillSpec> tags;
  final int maxVisible;
  final bool compact;

  const TagPillRow({
    super.key,
    required this.tags,
    this.maxVisible = 3,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final visible = tags.take(maxVisible).toList();
    final overflow = tags.length - visible.length;
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final t in visible) ...[
          Flexible(
            child: TagPill.rich(
              label: t.label,
              color: t.color,
              compact: compact,
            ),
          ),
          const SizedBox(width: 4),
        ],
        if (overflow > 0)
          Text(
            '+$overflow',
            style: TextStyle(
              fontFamily: AppFonts.ui,
              fontSize: compact ? 10 : 14,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
      ],
    );
  }
}
