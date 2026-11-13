import 'package:flutter/material.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/stroke_icon.dart';
import '../../domain/entities/pad.dart';
import '../models/pad_sound_slot.dart';
import '../providers/sampler_provider.dart';
import 'dashed_slot_frame.dart';
import 'hover_tint.dart';
import 'pad_progress_bars.dart';
import 'pad_surface.dart';

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

  /// Écoute le pad au casque sans le déclencher en salle. Visible aussi en
  /// Mode Spectacle — c'est là qu'on en a besoin.
  final VoidCallback? onCue;

  /// La pré-écoute de ce pad est audible : le bouton [onCue] passe à l'accent
  /// (plein, sans l'atténuation de repos) pour montrer qu'il joue.
  final bool isCueActive;

  const PadButton({
    super.key,
    required this.padItem,
    this.onTap,
    this.onLongPress,
    this.isEditable = false,
    this.onRemove,
    this.onEdit,
    this.onShowSounds,
    this.onCue,
    this.isCueActive = false,
  });

  _PadVisual get _visual {
    // Un brouillon n'est pas encore créé : il garde son cadre pointillé jusqu'à
    // son remplacement par le vrai pad, même une fois le son choisi.
    if (padItem.isDraft) return _PadVisual.draft;
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
            child: StrokeIcon(
              AppIcons.queue,
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
    final defaultColor = scheme.surfaceContainerHighest.withValues(alpha: 0.75);
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

    final fill = padItem.isPlaying
        ? playingColor
        : padItem.isPaused
        ? (hasCustomColor
              ? customColor.withValues(alpha: 0.35)
              : scheme.surfaceContainerHigh.withValues(alpha: 0.6))
        : baseColor;
    final border = padItem.isPlaying
        ? scheme.primary.withValues(alpha: 0.85)
        : padItem.isPaused
        ? scheme.primary.withValues(alpha: 0.3)
        : padItem.isPartiallyReady
        ? scheme.tertiary.withValues(alpha: 0.45)
        : scheme.outlineVariant.withValues(alpha: 0.45);

    return PadSurface(
      fill: fill,
      border: border,
      // Halo de la couleur du pad (ou de l'accent) : un pad "à l'antenne" se
      // repère à distance, sans dépendre uniquement de son fond.
      glow: padItem.isPlaying ? (customColor ?? scheme.primary) : null,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Titre ancré en haut, durée / variantes et actions ancrées en bas —
          // jamais centré : c'est ce qui distingue un pad "Console Linear"
          // d'une tuile Material générique. Les icônes d'action ne partagent
          // plus la rangée du titre, qui garde toute la largeur.
          _buildAnchoredBody(
            title: Text(
              padItem.displayName,
              maxLines: _titleMaxLines,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
            bottom: isMulti
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: _buildVariantChip(scheme),
                  )
                : _buildBottomMeta(scheme, hasCustomColor: hasCustomColor),
            iconCluster: iconCluster,
          ),
          // Badges informatifs : le corps du pad porte l'action. La pause
          // musique est signalée uniquement dans la régie, pas sur le pad.
          if (padItem.isDownloading) _buildDownloadCorner(scheme.tertiary),
          ?_buildProgress(scheme, hasCustomColor: hasCustomColor),
        ],
      ),
    );
  }

  /// Corps commun des pads prêt / en route / bloqué : titre ancré en haut,
  /// état ([bottom]) et actions ([iconCluster]) ancrés en bas — les actions
  /// ne changent pas de place quand le pad change d'état. Marges basse et
  /// droite réduites : les icônes (cases de 20 px, glyphe en haut à gauche) et
  /// la puce « N sons » (4 px de padding) ajoutent déjà de l'air.
  Widget _buildAnchoredBody({
    required Widget title,
    required Widget bottom,
    required Widget? iconCluster,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Padding(
              // Réserve la pastille de téléchargement (coin haut droit).
              padding: EdgeInsets.only(
                right: padItem.isDownloading ? _downloadCornerSize : 0,
              ),
              child: title,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: bottom),
              ?iconCluster,
            ],
          ),
        ],
      ),
    );
  }

  static const int _titleMaxLines = 3;
  static const double _iconTargetSize = 20;
  static const double _downloadCornerSize = 26;

  /// Progression de lecture : filet de 3 px collé au bord bas du pad (le
  /// clip arrondi de la carte en épouse les coins), uniquement pendant la
  /// lecture ou la pause. `null` quand il n'y a rien à montrer.
  Widget? _buildProgress(ColorScheme scheme, {required bool hasCustomColor}) {
    final isMusic = padItem.pad.isMusicPad;
    final showProgress = isMusic
        ? padItem.isPlaying || padItem.isPaused
        : padItem.playbackTickets.isNotEmpty;
    if (!showProgress) return null;

    // Couleur d'icône contrastée avec le fond réel du pad si celui-ci a une
    // couleur perso ; l'accent sinon.
    final color = hasCustomColor ? _iconStyle(scheme) : scheme.primary;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 3,
      child: IgnorePointer(
        child: isMusic
            ? MusicProgressBar(padItem: padItem, color: color)
            : Stack(
                children: [
                  for (final ticket in padItem.playbackTickets)
                    PolyphonicProgressBar(
                      key: ValueKey<int>(ticket.id),
                      ticket: ticket,
                      color: color.withValues(alpha: 0.8),
                    ),
                ],
              ),
      ),
    );
  }

  /// Durée d'un pad mono-son, en police technique. Les pads multi-sons
  /// affichent [_buildVariantChip] à la place.
  Widget _buildBottomMeta(ColorScheme scheme, {required bool hasCustomColor}) {
    final duration = padItem.progressPlayer?.duration;
    if (duration == null || duration <= Duration.zero) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
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

    final base = _iconStyle(scheme);
    Widget content(bool hovered) {
      final tint = _hoverTint(base, hovered);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StrokeIcon(
            switch (padItem.pad.playMode) {
              PadPlayMode.random => AppIcons.shuffle,
              PadPlayMode.sequential => AppIcons.repeatOne,
            },
            size: 11,
            color: tint,
          ),
          const SizedBox(width: 3),
          Text(
            padItem.isPartiallyReady ? '$label variantes' : '$label sons',
            style: TextStyle(
              fontSize: 11,
              color: padItem.isPartiallyReady ? scheme.tertiary : tint,
            ),
          ),
          if (onShowSounds != null)
            StrokeIcon(AppIcons.chevronRight, size: 12, color: tint),
        ],
      );
    }

    if (onShowSounds == null) return content(false);
    // Le libellé lui-même ouvre le choix du son (pas d'icône dédiée) : le
    // chevron signale qu'il est cliquable. Même teinte et même survol que les
    // icônes du pad, sans fond. Le tap est capté ici avant celui du pad.
    return HoverTint(
      onTap: onShowSounds,
      builder: (context, hovered) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: content(hovered),
      ),
    );
  }

  // ── Icônes éditer / fermer / sons ─────────────────────────────────────────

  /// Couleur d'icône et de bordure contrastées avec le fond réel du pad — un
  /// gris fixe devient illisible sur un pad rouge ou clair. On reproduit
  /// l'alpha appliqué au fond selon l'état (lecture, pause) puis on compose
  /// sur la surface pour estimer la couleur perçue.
  Color _iconStyle(ColorScheme scheme) {
    final colorValue = padItem.pad.colorValue;
    if (colorValue == null) {
      return AppColors.textDim;
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
    return tinted.withValues(alpha: isDarkBackground ? 0.9 : 0.75);
  }

  /// Rangée d'icônes nues (ni fond ni bordure) : au repos elles sont
  /// atténuées, le survol ne fait que les ramener à pleine intensité
  /// ([HoverTint]). Leur couleur vient de [_iconStyle], contrastée avec le
  /// fond arbitraire du pad.
  ///
  /// [includeSounds] : icône « sons du pad ». Un pad prêt ouvre ce choix en
  /// touchant son libellé « N sons » ; les états en route / bloqué n'ont pas
  /// ce libellé, l'icône reste donc leur seule porte d'entrée.
  List<(StrokeIconData, double, VoidCallback?, bool)> _iconClusterEntries({
    required bool includeSounds,
  }) => [
    if (onCue != null) (AppIcons.padCue, 15.0, onCue, isCueActive),
    if (includeSounds && padItem.totalSoundCount > 1 && onShowSounds != null)
      (AppIcons.padSounds, 15.0, onShowSounds, false),
    if (isEditable && onEdit != null) (AppIcons.padEdit, 15.0, onEdit, false),
    if (isEditable && onRemove != null)
      (AppIcons.padRemove, 17.0, onRemove, false),
  ];

  Widget? _buildIconCluster(ColorScheme scheme, {bool includeSounds = false}) {
    final entries = _iconClusterEntries(includeSounds: includeSounds);
    if (entries.isEmpty) return null;

    final color = _iconStyle(scheme);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (icon, size, onPressed, active) in entries)
          HoverTint(
            onTap: onPressed,
            builder: (context, hovered) => SizedBox(
              width: _iconTargetSize,
              height: _iconTargetSize,
              // Aligné sur la grille de pixels : un `Center` posait l'icône
              // à un demi-pixel (20 − 15 = 5), ce qui brouille le trait.
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.all(
                    ((_iconTargetSize - size) / 2).floorToDouble(),
                  ),
                  child: StrokeIcon(
                    icon,
                    size: size,
                    color: active ? scheme.primary : _hoverTint(color, hovered),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Teinte des actions d'un pad : franchement estompée au repos, pleine
  /// intensité au survol — l'écart doit se voir sur n'importe quelle couleur
  /// de pad. Partagée par les icônes et le libellé « N sons ».
  static Color _hoverTint(Color base, bool hovered) =>
      hovered ? base.withValues(alpha: 1) : base.withValues(alpha: 0.5);

  // ── EN ROUTE ──────────────────────────────────────────────────────────────

  Widget _buildEnRoute(BuildContext context, ColorScheme scheme) {
    final label = padItem.displayName;
    final downloading = padItem.isDownloading;
    final onColor = scheme.onTertiaryContainer;
    final iconCluster = _buildIconCluster(scheme, includeSounds: true);

    return PadSurface(
      fill: scheme.tertiaryContainer,
      border: scheme.tertiary.withValues(alpha: 0.6),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildAnchoredBody(
            title: Text(
              label,
              maxLines: _titleMaxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: onColor,
              ),
            ),
            bottom: Row(
              children: [
                StrokeIcon(
                  downloading ? AppIcons.downloading : AppIcons.cloudDownload,
                  size: 12,
                  color: onColor.withValues(alpha: 0.75),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    downloading ? 'téléchargement…' : 'Télécharger',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: onColor.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
            iconCluster: iconCluster,
          ),
          if (downloading) _buildDownloadCorner(onColor),
        ],
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
        ? (AppIcons.warning, 'fichier introuvable')
        : isUnsupportedFormat
        ? (AppIcons.blocked, 'format non supporté')
        : (AppIcons.cloudOff, 'hors-ligne');
    final iconCluster = _buildIconCluster(scheme, includeSounds: true);

    return PadSurface(
      fill: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      border: isMissing
          ? scheme.error.withValues(alpha: 0.55)
          : scheme.outlineVariant.withValues(alpha: 0.5),
      onTap: onTap,
      onLongPress: onLongPress,
      child: _buildAnchoredBody(
        title: Text(
          label,
          maxLines: _titleMaxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            height: 1.2,
            fontWeight: FontWeight.w500,
            color: scheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
        bottom: Row(
          children: [
            StrokeIcon(icon, size: 12, color: accent),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: accent),
              ),
            ),
          ],
        ),
        iconCluster: iconCluster,
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
            StrokeIcon(
              AppIcons.cloudDownload,
              size: AppIconSize.sm,
              color: color,
            ),
          ],
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
    PadSoundAvailability.ready ||
    PadSoundAvailability.cached => (AppIcons.checkCircle, scheme.primary),
    PadSoundAvailability.needsDownload => (
      AppIcons.cloudDownload,
      scheme.onSurfaceVariant,
    ),
    PadSoundAvailability.offline => (
      AppIcons.cloudOff,
      scheme.onSurfaceVariant.withValues(alpha: 0.7),
    ),
    PadSoundAvailability.missingFile => (AppIcons.error, scheme.error),
    PadSoundAvailability.unsupportedFormat => (AppIcons.blocked, scheme.error),
  };
  return StrokeIcon(icon, size: size, color: color);
}
