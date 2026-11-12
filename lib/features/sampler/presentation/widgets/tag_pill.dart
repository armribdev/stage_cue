import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/stroke_icon.dart';

/// Cotes d'une étiquette selon sa densité (normale ou compacte).
class _PillMetrics {
  final double fontSize;
  final double hPad;
  final double vPad;

  const _PillMetrics.regular() : fontSize = 14, hPad = 12, vPad = 7;

  const _PillMetrics.compact() : fontSize = 10, hPad = 6, vPad = 2;

  factory _PillMetrics.of({required bool compact}) =>
      compact ? const _PillMetrics.compact() : const _PillMetrics.regular();
}

TextStyle _labelStyle(
  ColorScheme scheme,
  _PillMetrics m, {
  bool suggestion = false,
}) => TextStyle(
  fontFamily: AppFonts.ui,
  fontSize: m.fontSize,
  fontWeight: FontWeight.w500,
  height: 1.25,
  color: suggestion ? scheme.onSurfaceVariant : scheme.onSurface,
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
/// Options : [onRemove] ajoute une croix discrète (tag posé sur un son) ;
/// [suggestion] passe en fantôme (fond transparent, filet de ton) car ce n'est
/// pas encore un tag (décision 0031).
class TagPill extends StatefulWidget {
  final InlineSpan label;

  /// Couleur de catégorie ; `null` = neutre.
  final Color? color;
  final bool compact;
  final bool suggestion;

  /// Valeur affichée en mono après le nom (ex. confiance d'une suggestion).
  final String? meta;
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
    this.meta,
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
    this.meta,
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
    final colored = widget.color != null;
    final background = widget.suggestion
        ? tone.withAlpha(hovered ? 34 : 0)
        : tone.withAlpha(colored ? (hovered ? 82 : 60) : (hovered ? 36 : 22));
    final side = widget.suggestion
        ? BorderSide(color: tone.withAlpha(_hovered ? 190 : 120))
        : BorderSide(color: tone.withAlpha(colored ? 150 : 40));
    final textStyle = _labelStyle(scheme, m, suggestion: widget.suggestion);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: widget.compact ? AppRadius.radiusSm : AppRadius.radiusMd,
        border: Border.fromBorderSide(side),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: m.hPad, vertical: m.vPad),
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
            if (widget.meta != null) ...[
              const SizedBox(width: 6),
              Text(
                widget.meta!,
                style: AppFonts.monoStyle(
                  textStyle.copyWith(
                    fontSize: m.fontSize - 1,
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (widget.onRemove != null) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: widget.removeTooltip ?? 'Retirer',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onRemove,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: StrokeIcon(
                      AppIcons.close,
                      size: m.fontSize,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ],
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
