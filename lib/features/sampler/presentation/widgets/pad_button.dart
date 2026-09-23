import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../domain/entities/pad.dart';
import '../models/pad_sound_slot.dart';
import '../providers/sampler_provider.dart';
import 'dashed_slot_frame.dart';

/// Famille visuelle d'un pad — projette les 4 états d'availability sur 3 repères
/// lisibles d'un coup d'œil sous stress live (refonte UX P0) :
///
/// - [ready]   : jouable immédiatement (tap = son). Inclut les pads partiels.
/// - [enRoute] : résoluble par un tap (à télécharger / téléchargement en cours).
/// - [blocked] : indisponible maintenant (hors-ligne ou fichier introuvable).
///
/// Clé : `needsDownload` n'est PAS dans la même famille qu'`offline`. Le premier
/// se règle d'un tap ; le second est réellement bloqué. Les confondre est l'erreur
/// cognitive centrale de l'ancienne carte grisée uniforme.
enum _PadVisual { ready, enRoute, blocked, draft }

/// Widget représentant un pad de son.
class PadButton extends StatelessWidget {
  final PadItem padItem;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Mode classique éditable : affiche les icônes éditer/fermer.
  final bool isEditable;

  /// Suppression du pad (déjà enveloppée dans l'animation de sortie par
  /// [PadCard] — jamais appelée directement).
  final VoidCallback? onRemove;

  /// Ouvre les détails du pad (bouton crayon en mode classique éditable).
  final VoidCallback? onEdit;

  /// Affiche la liste des sons du multipad. Visible dès que le pad a
  /// plusieurs sons, y compris en Mode Spectacle — indépendant de
  /// [isEditable].
  final VoidCallback? onShowSounds;

  const PadButton({
    super.key,
    required this.padItem,
    this.onTap,
    this.onLongPress,
    this.isEditable = false,
    this.onRemove,
    this.onEdit,
    this.onShowSounds,
  });

  _PadVisual get _visual {
    if (padItem.isDraft && padItem.totalSoundCount == 0) {
      return _PadVisual.draft;
    }
    if (padItem.isPlayable || padItem.appearsReady) return _PadVisual.ready;
    final reason = padItem.unavailabilityReason;
    if (padItem.isDownloading ||
        reason == null ||
        reason == PadUnavailabilityReason.needsDownload) {
      return _PadVisual.enRoute;
    }
    return _PadVisual.blocked;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual = _visual;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      // Le layout par défaut (Stack centré, contraintes lâches) laisserait le
      // pad se rétracter à la largeur de son titre au lieu de remplir sa
      // cellule — visible en Mode Spectacle, sans icônes pour l'élargir.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.passthrough,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<_PadVisual>(visual),
        child: switch (visual) {
          _PadVisual.ready => _buildReady(context, scheme),
          _PadVisual.enRoute => _buildEnRoute(context, scheme),
          _PadVisual.blocked => _buildBlocked(context, scheme),
          _PadVisual.draft => _buildDraft(context, scheme),
        },
      ),
    );
  }

  // ── BROUILLON (création en cours, pas encore de son) ─────────────────────

  Widget _buildDraft(BuildContext context, ColorScheme scheme) {
    final iconCluster = _buildIconCluster(scheme);
    return DashedSlotFrame(
      child: Stack(
        children: [
          Center(
            child: Icon(
              Icons.library_music_outlined,
              size: 24,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          if (iconCluster != null)
            Positioned(top: 4, right: 4, child: iconCluster),
        ],
      ),
    );
  }

  // ── PRÊT ──────────────────────────────────────────────────────────────────

  Widget _buildReady(BuildContext context, ColorScheme scheme) {
    final colorValue = padItem.pad.colorValue;
    final customColor = colorValue != null ? Color(colorValue) : null;
    final hasCustomColor = customColor != null;
    final defaultColor =
        scheme.surfaceContainerHighest.withValues(alpha: 0.75);
    final baseColor = customColor ?? defaultColor;
    // En lecture sans couleur perso : glacis violet (accent) plutôt qu'un gris
    // neutre — repère "à l'antenne" cohérent avec la régie musique.
    final playingColor = hasCustomColor
        ? customColor.withValues(alpha: 0.75)
        : scheme.primaryContainer;
    final isMulti = padItem.totalSoundCount > 1;
    final iconCluster = _buildIconCluster(scheme);
    final titleStyle = TextStyle(
      fontSize: 15,
      height: 1.2,
      fontWeight: padItem.isPlaying ? FontWeight.w700 : FontWeight.w500,
      color: padItem.isPlaying && hasCustomColor
          ? scheme.primary
          : scheme.onSurface,
    );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.radiusPad,
        side: BorderSide(
          color: padItem.isPlaying
              ? scheme.primary.withValues(alpha: 0.5)
              : padItem.isPaused
                  ? scheme.primary.withValues(alpha: 0.3)
                  : padItem.isPartiallyReady
                      ? scheme.tertiary.withValues(alpha: 0.45)
                      : scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      color: padItem.isPlaying
          ? playingColor
          : padItem.isPaused
              ? (hasCustomColor
                  ? customColor.withValues(alpha: 0.35)
                  : scheme.surfaceContainerHigh.withValues(alpha: 0.6))
              : baseColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _interactive(
            // Titre ancré en haut, durée/progression ancrée en bas — jamais
            // centré : c'est ce qui distingue un pad "Console Linear" d'une
            // tuile Material générique (voir maquette de direction). Seule la
            // 1re ligne du titre cède la place aux icônes : les suivantes
            // reprennent toute la largeur du pad.
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: LayoutBuilder(
                      builder: (context, constraints) => _buildTitle(
                        context,
                        style: titleStyle,
                        maxWidth: constraints.maxWidth,
                        iconCluster: iconCluster,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (isMulti)
                    _buildVariantChip(scheme)
                  else
                    _buildBottomMeta(scheme, hasCustomColor: hasCustomColor),
                ],
              ),
            ),
          ),
          // Badges informatifs : le corps du pad porte l'action. La pause
          // musique est signalée uniquement dans la régie, pas sur le pad.
          if (padItem.isDownloading) _buildDownloadCorner(scheme.tertiary),
        ],
      ),
    );
  }

  static const int _titleMaxLines = 3;
  static const double _iconSegmentSize = 22;
  static const double _iconClusterGap = 6;

  /// Titre sur [_titleMaxLines] lignes dont seule la 1re partage sa rangée
  /// avec les icônes. Flutter n'a pas d'habillage autour d'un flottant : on
  /// mesure ce qui tient sur la 1re ligne à largeur réduite, puis le reste
  /// repart à pleine largeur dans un second `Text`.
  Widget _buildTitle(
    BuildContext context, {
    required TextStyle style,
    required double maxWidth,
    required Widget? iconCluster,
  }) {
    final label = padItem.displayName;
    final reserved = iconCluster == null
        ? 0.0
        : _iconClusterEntryCount * _iconSegmentSize + _iconClusterGap;
    // Plancher : sur un pad très étroit, la 1re ligne garde de quoi afficher
    // au moins un mot plutôt que de se réduire à rien.
    final firstLineWidth = math.max(maxWidth - reserved, maxWidth * 0.3);

    // Même style effectif que les `Text` ci-dessous (fusion avec
    // DefaultTextStyle → police Manrope du thème) : mesurer avec le style
    // brut retombe sur la police par défaut, plus étroite, et la coupure
    // calculée ne tient plus au rendu réel.
    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    final painter = TextPainter(
      text: TextSpan(text: label, style: effectiveStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: firstLineWidth);
    var firstLineEnd =
        painter.getLineBoundary(const TextPosition(offset: 0)).end;
    final lineHeight = painter.preferredLineHeight;
    painter.dispose();

    // Un mot plus large que la ligne est coupé au caractère, et son début
    // resterait collé en fin de 1re ligne (« ambience So » / « undEffects… »).
    // On recule au dernier espace pour qu'il démarre sur sa propre ligne.
    if (firstLineEnd > 0 &&
        firstLineEnd < label.length &&
        label[firstLineEnd].trim().isNotEmpty &&
        label[firstLineEnd - 1].trim().isNotEmpty) {
      final lastSpace = label.lastIndexOf(' ', firstLineEnd - 1);
      if (lastSpace > 0) firstLineEnd = lastSpace;
    }

    final rest = firstLineEnd < label.length
        ? label.substring(firstLineEnd).trimLeft()
        : '';

    final lines = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(right: maxWidth - firstLineWidth),
          child: Text(
            rest.isEmpty ? label : label.substring(0, firstLineEnd).trimRight(),
            maxLines: 1,
            // Le point de rupture est déjà mesuré pour tenir dans
            // `firstLineWidth` : si du texte continue en dessous, une
            // ellipse ici tronquerait un mot avant la vraie fin du titre.
            // `clip` absorbe juste l'écart d'arrondi entre ce `TextPainter`
            // et le layout réel du `Text`.
            overflow: rest.isEmpty ? TextOverflow.ellipsis : TextOverflow.clip,
            style: style,
          ),
        ),
        if (rest.isNotEmpty)
          Flexible(
            child: Text(
              rest,
              maxLines: _titleMaxLines - 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
      ],
    );
    if (iconCluster == null) return lines;

    // Icônes hors flux, centrées sur la 1re ligne : plus hautes qu'une ligne
    // de texte, elles creuseraient sinon l'interligne entre lignes 1 et 2.
    return SizedBox(
      width: maxWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          lines,
          Positioned(
            top: (lineHeight - _iconSegmentSize) / 2,
            right: 0,
            child: iconCluster,
          ),
        ],
      ),
    );
  }

  /// Bloc bas d'un pad mono-son : barre de progression fine (uniquement
  /// pendant la lecture) suivie de la durée en police technique — remplace
  /// l'ancien glacis plein-carte par une barre discrète, comme sur la
  /// maquette. Les pads multi-sons affichent [_buildVariantChip] à la place.
  Widget _buildBottomMeta(ColorScheme scheme, {required bool hasCustomColor}) {
    final barColor = hasCustomColor ? scheme.primary : scheme.onSurfaceVariant;
    final showProgress = padItem.pad.isMusicPad
        ? padItem.isPlaying || padItem.isPaused
        : padItem.playbackTickets.isNotEmpty;
    final duration = padItem.progressPlayer?.duration;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showProgress) ...[
          padItem.pad.isMusicPad
              ? _MusicProgressBar(padItem: padItem, color: barColor)
              : SizedBox(
                  height: 3,
                  child: Stack(
                    children: [
                      for (final ticket in padItem.playbackTickets)
                        _PolyphonicProgressBar(
                          key: ValueKey<int>(ticket.id),
                          ticket: ticket,
                          color: barColor.withValues(alpha: 0.7),
                        ),
                    ],
                  ),
                ),
          const SizedBox(height: 5),
        ],
        if (duration != null && duration > Duration.zero)
          Text(
            _formatPadDuration(duration),
            style: AppFonts.monoStyle(
              TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant.withValues(
                  alpha: hasCustomColor ? 0.85 : 0.7,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _formatPadDuration(Duration d) {
    final totalSeconds = d.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildVariantChip(ColorScheme scheme) {
    final total = padItem.totalSoundCount;
    final ready = padItem.readySoundCount;
    final label = padItem.isPartiallyReady ? '$ready/$total' : '$total';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          switch (padItem.pad.playMode) {
            PadPlayMode.random => Icons.shuffle_rounded,
            PadPlayMode.sequential => Icons.repeat_one_rounded,
          },
          size: 11,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.65),
        ),
        const SizedBox(width: 3),
        Text(
          padItem.isPartiallyReady ? '$label variantes' : '$label sons',
          style: TextStyle(
            fontSize: 11,
            color: padItem.isPartiallyReady
                ? scheme.tertiary
                : scheme.onSurfaceVariant.withValues(alpha: 0.65),
          ),
        ),
      ],
    );
  }

  // ── Icônes éditer / fermer / sons ─────────────────────────────────────────

  /// Couleur d'icône et de bordure contrastées avec le fond réel du pad — un
  /// gris fixe devient illisible sur un pad rouge ou clair. On reproduit
  /// l'alpha appliqué au fond selon l'état (lecture, pause) puis on compose
  /// sur la surface pour estimer la couleur perçue.
  ({Color icon, Color border}) _iconStyle(ColorScheme scheme) {
    final colorValue = padItem.pad.colorValue;
    if (colorValue == null) {
      return (icon: AppColors.textDim, border: AppElevation.border(scheme).color);
    }

    final customColor = Color(colorValue);
    final alpha = padItem.isPlaying
        ? 0.75
        : padItem.isPaused
            ? 0.35
            : 1.0;
    final effective = Color.alphaBlend(
      customColor.withValues(alpha: alpha),
      scheme.surface,
    );
    final isDarkBackground =
        ThemeData.estimateBrightnessForColor(effective) == Brightness.dark;

    // Teinte du pad conservée (désaturée) mais luminosité poussée à l'extrême
    // opposé du fond — l'icône se fond dans la couleur du pad tout en
    // restant lisible, plutôt qu'un noir/blanc brut déconnecté.
    final hsl = HSLColor.fromColor(customColor);
    final tinted = hsl
        .withSaturation((hsl.saturation * 0.6).clamp(0.0, 1.0))
        .withLightness(isDarkBackground ? 0.88 : 0.16)
        .toColor();
    final icon = tinted.withValues(alpha: isDarkBackground ? 0.9 : 0.75);
    final border = (isDarkBackground ? Colors.white : Colors.black)
        .withValues(alpha: 0.18);
    return (icon: icon, border: border);
  }

  /// Groupe façon "segmented control" : chaque icône est un carré indépendant
  /// (son propre fond + sa propre bordure pleine hauteur), collés bord à bord
  /// sans marge — seuls le coin tout à gauche et le coin tout à droite du
  /// groupe sont arrondis, les autres restent droits. Même langage visuel que
  /// [BoxedIconButton], adapté en contraste dynamique puisque le fond du pad
  /// est arbitraire (voir maquette : icônes éditer/fermer sur la même ligne
  /// que le titre, jamais flottantes dessus).
  List<(IconData, double, VoidCallback?)> get _iconClusterEntries => [
        if (padItem.totalSoundCount > 1 && onShowSounds != null)
          (Icons.queue_music_rounded, 14.0, onShowSounds),
        if (isEditable && onEdit != null) (Icons.edit_outlined, 14.0, onEdit),
        if (isEditable && onRemove != null) (Icons.close, 16.0, onRemove),
      ];

  int get _iconClusterEntryCount => _iconClusterEntries.length;

  Widget? _buildIconCluster(ColorScheme scheme) {
    final entries = _iconClusterEntries;
    if (entries.isEmpty) return null;

    final style = _iconStyle(scheme);

    Widget segment(int index) {
      final (icon, size, onPressed) = entries[index];
      final isFirst = index == 0;
      final isLast = index == entries.length - 1;
      final borderRadius = BorderRadius.horizontal(
        left: isFirst ? const Radius.circular(AppRadius.sm) : Radius.zero,
        right: isLast ? const Radius.circular(AppRadius.sm) : Radius.zero,
      );
      return Container(
        width: _iconSegmentSize,
        height: _iconSegmentSize,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.24),
          borderRadius: borderRadius,
          border: Border(
            top: BorderSide(color: style.border),
            bottom: BorderSide(color: style.border),
            left: isFirst
                ? BorderSide(color: style.border)
                : BorderSide.none,
            right: BorderSide(color: style.border),
          ),
        ),
        // Le hover/splash Material calque le même `borderRadius` que le
        // conteneur : sans ça, sa forme reste rectangulaire par défaut et
        // déborde du coin arrondi du segment (visible surtout sur les coins
        // extérieurs du groupe).
        child: IconButton(
          icon: Icon(icon, size: size),
          onPressed: onPressed,
          style: IconButton.styleFrom(
            foregroundColor: style.icon,
            backgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ).copyWith(
            // Overlay neutre (blanc translucide) plutôt que dérivé de
            // `style.icon` : cette teinte est calée sur la couleur du pad et
            // devient quasi invisible sur certains pads, alors que le fond du
            // segment (noir translucide) reste lui toujours neutre.
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return Colors.white.withValues(alpha: 0.24);
              }
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return Colors.white.withValues(alpha: 0.16);
              }
              return null;
            }),
          ),
          constraints: const BoxConstraints(
            minWidth: _iconSegmentSize,
            minHeight: _iconSegmentSize,
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < entries.length; i++) segment(i),
      ],
    );
  }

  // ── EN ROUTE ──────────────────────────────────────────────────────────────

  Widget _buildEnRoute(BuildContext context, ColorScheme scheme) {
    final label = padItem.displayName;
    final downloading = padItem.isDownloading;
    final onColor = scheme.onTertiaryContainer;
    final iconCluster = _buildIconCluster(scheme);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.radiusPad,
        side: BorderSide(color: scheme.tertiary.withValues(alpha: 0.6)),
      ),
      color: scheme.tertiaryContainer,
      child: _interactive(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: onColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          downloading
                              ? Icons.downloading_rounded
                              : Icons.cloud_download_outlined,
                          size: 12,
                          color: onColor.withValues(alpha: 0.75),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          downloading ? 'téléchargement…' : 'Télécharger',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: onColor.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (downloading) _buildDownloadCorner(onColor),
            if (iconCluster != null)
              Positioned(top: 4, right: 4, child: iconCluster),
          ],
        ),
      ),
    );
  }

  // ── BLOQUÉ ────────────────────────────────────────────────────────────────

  Widget _buildBlocked(BuildContext context, ColorScheme scheme) {
    final reason = padItem.unavailabilityReason;
    final isMissing = reason == PadUnavailabilityReason.missingFile;
    final isUnsupportedFormat =
        reason == PadUnavailabilityReason.unsupportedFormat;
    final label = padItem.displayName;
    final accent = (isMissing || isUnsupportedFormat)
        ? scheme.error
        : scheme.onSurfaceVariant.withValues(alpha: 0.7);
    final (icon, hint) = isMissing
        ? (Icons.warning_amber_rounded, 'fichier introuvable')
        : isUnsupportedFormat
            ? (Icons.block_outlined, 'format non supporté')
            : (Icons.cloud_off_outlined, 'hors-ligne');
    final iconCluster = _buildIconCluster(scheme);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.radiusPad,
        side: BorderSide(
          color: isMissing
              ? scheme.error.withValues(alpha: 0.55)
              : scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      child: _interactive(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 12, color: accent),
                        const SizedBox(width: 4),
                        Text(
                          hint,
                          style: TextStyle(fontSize: 11, color: accent),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (iconCluster != null)
              Positioned(top: 4, right: 4, child: iconCluster),
          ],
        ),
      ),
    );
  }

  // ── Communs ───────────────────────────────────────────────────────────────

  /// Pastille de progression de téléchargement (informative).
  Widget _buildDownloadCorner(Color color) {
    return Positioned(
      top: 4,
      right: 4,
      child: SizedBox(
        width: 26,
        height: 26,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 21,
              height: 21,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                value: padItem.downloadTotal > 0
                    ? padItem.downloadDone / padItem.downloadTotal
                    : null,
                color: color,
              ),
            ),
            Icon(Icons.cloud_download_outlined, size: 14, color: color),
          ],
        ),
      ),
    );
  }

  Widget _interactive({required Widget child}) {
    if (onTap == null && onLongPress == null) {
      return child;
    }
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: AppRadius.radiusPad,
      child: child,
    );
  }
}

/// Barre de progression de lecture d'un pad musique, synchronisée sur la
/// position **réelle** du lecteur. Contrairement à une simple animation 0→1
/// relancée à chaque `play`, elle se ré-aligne à chaque rebuild sur
/// `player.position` (ou sur la position mémorisée en pause) : une reprise après
/// pause repart de l'endroit où le son a été suspendu, jamais de zéro.
class _MusicProgressBar extends StatefulWidget {
  final PadItem padItem;
  final Color color;

  const _MusicProgressBar({
    required this.padItem,
    required this.color,
  });

  @override
  State<_MusicProgressBar> createState() => _MusicProgressBarState();
}

class _MusicProgressBarState extends State<_MusicProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _syncToPlayback();
  }

  @override
  void didUpdateWidget(covariant _MusicProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Le grid se reconstruit à chaque `_notify()` du notifier : on en profite
    // pour recaler la barre sur la position réelle (corrige aussi la dérive).
    _syncToPlayback();
  }

  /// Ré-aligne la barre sur l'état de lecture courant du pad :
  /// - en lecture : anime depuis la position réelle jusqu'à la fin, sur le temps
  ///   restant — l'`AnimationController` de durée = durée totale interpole
  ///   linéairement le reste depuis `value` (`forward()` prend `durée × (1 −
  ///   value)`) ;
  /// - en pause : fige à la position mémorisée d'où la reprise repartira ;
  /// - arrêté : ramène à zéro (barre masquée).
  void _syncToPlayback() {
    final pad = widget.padItem;
    final totalMs = (pad.progressPlayer?.duration ?? Duration.zero).inMilliseconds;

    if (pad.isPlaying && totalMs > 0) {
      final posMs =
          (pad.progressPlayer?.position.inMilliseconds ?? 0).clamp(0, totalMs);
      _controller.duration = Duration(milliseconds: totalMs);
      _controller.value = posMs / totalMs;
      _controller.forward();
    } else if (pad.isPaused && totalMs > 0) {
      final posMs =
          (pad.pausedPlaybackPosition?.inMilliseconds ?? 0).clamp(0, totalMs);
      _controller.stop();
      _controller.value = posMs / totalMs;
    } else {
      _controller.stop();
      _controller.value = 0.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const _barHeight = 3.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final value = _controller.value;
        // Rien à afficher tant que le pad est arrêté et la barre vide.
        if (!widget.padItem.isPlaying && value <= 0.0) {
          return const SizedBox.shrink();
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(_barHeight),
          child: LinearProgressIndicator(
            value: value,
            backgroundColor: widget.color.withValues(alpha: 0.16),
            valueColor: AlwaysStoppedAnimation<Color>(widget.color),
            minHeight: _barHeight,
          ),
        );
      },
    );
  }
}

/// Barre de progression d'une voix polyphonique : anime 0→1 sur la durée du son
/// à partir de sa position réelle (au cas où la barre apparaît après le départ),
/// indépendamment des rebuilds du pad (chevauchements superposés).
class _PolyphonicProgressBar extends StatefulWidget {
  final PadPlaybackTicket ticket;
  final Color color;

  const _PolyphonicProgressBar({
    super.key,
    required this.ticket,
    required this.color,
  });

  @override
  State<_PolyphonicProgressBar> createState() => _PolyphonicProgressBarState();
}

class _PolyphonicProgressBarState extends State<_PolyphonicProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final total = widget.ticket.duration;
    final elapsed = DateTime.now().difference(widget.ticket.startedAt);
    final totalMs = total.inMilliseconds;
    final startValue =
        totalMs > 0 ? (elapsed.inMilliseconds / totalMs).clamp(0.0, 1.0) : 1.0;
    _controller = AnimationController(
      vsync: this,
      duration: total > Duration.zero ? total : const Duration(milliseconds: 1),
    );
    _controller.value = startValue;
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const _barHeight = 3.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Positioned.fill(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_barHeight),
          child: LinearProgressIndicator(
            value: _controller.value,
            backgroundColor: Colors.transparent,
            valueColor: AlwaysStoppedAnimation<Color>(widget.color),
            minHeight: _barHeight,
          ),
        ),
      ),
    );
  }
}

/// Icône de statut d'une variante (liste de téléchargement, détails pad…).
Widget padSoundAvailabilityIcon(
  PadSoundAvailability availability,
  ColorScheme scheme, {
  double size = 18,
}) {
  final (icon, color) = switch (availability) {
    PadSoundAvailability.ready || PadSoundAvailability.cached => (
        Icons.check_circle_outline,
        scheme.primary,
      ),
    PadSoundAvailability.needsDownload => (
        Icons.cloud_download_outlined,
        scheme.onSurfaceVariant,
      ),
    PadSoundAvailability.offline => (
        Icons.cloud_off_outlined,
        scheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    PadSoundAvailability.missingFile => (
        Icons.error_outline,
        scheme.error,
      ),
    PadSoundAvailability.unsupportedFormat => (
        Icons.block_outlined,
        scheme.error,
      ),
  };
  return Icon(icon, size: size, color: color);
}
