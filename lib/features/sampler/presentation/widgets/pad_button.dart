import 'package:flutter/material.dart';
import '../../../../core/theme/app_icons.dart';
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

    return _PadSurface(
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
          Padding(
            padding: const EdgeInsets.all(12),
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
                    child: Text(
                      padItem.displayName,
                      maxLines: _titleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: isMulti
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: _buildVariantChip(scheme),
                            )
                          : _buildBottomMeta(
                              scheme,
                              hasCustomColor: hasCustomColor,
                            ),
                    ),
                    ?iconCluster,
                  ],
                ),
              ],
            ),
          ),
          // Badges informatifs : le corps du pad porte l'action. La pause
          // musique est signalée uniquement dans la régie, pas sur le pad.
          if (padItem.isDownloading) _buildDownloadCorner(scheme.tertiary),
          ?_buildProgress(scheme, hasCustomColor: hasCustomColor),
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
            ? _MusicProgressBar(padItem: padItem, color: color)
            : Stack(
                children: [
                  for (final ticket in padItem.playbackTickets)
                    _PolyphonicProgressBar(
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
          Icon(
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
            Icon(AppIcons.chevronRight, size: 12, color: tint),
        ],
      );
    }

    if (onShowSounds == null) return content(false);
    // Le libellé lui-même ouvre le choix du son (pas d'icône dédiée) : le
    // chevron signale qu'il est cliquable. Même teinte et même survol que les
    // icônes du pad, sans fond. Le tap est capté ici avant celui du pad.
    return _HoverTint(
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
  /// ([_HoverTint]). Leur couleur vient de [_iconStyle], contrastée avec le
  /// fond arbitraire du pad.
  ///
  /// [includeSounds] : icône « sons du pad ». Un pad prêt ouvre ce choix en
  /// touchant son libellé « N sons » ; les états en route / bloqué n'ont pas
  /// ce libellé, l'icône reste donc leur seule porte d'entrée.
  List<(IconData, double, VoidCallback?)> _iconClusterEntries({
    required bool includeSounds,
  }) => [
    if (onCue != null) (AppIcons.padCue, 15.0, onCue),
    if (includeSounds && padItem.totalSoundCount > 1 && onShowSounds != null)
      (AppIcons.padSounds, 15.0, onShowSounds),
    if (isEditable && onEdit != null) (AppIcons.padEdit, 15.0, onEdit),
    if (isEditable && onRemove != null) (AppIcons.padRemove, 17.0, onRemove),
  ];

  Widget? _buildIconCluster(ColorScheme scheme, {bool includeSounds = false}) {
    final entries = _iconClusterEntries(includeSounds: includeSounds);
    if (entries.isEmpty) return null;

    final color = _iconStyle(scheme);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (icon, size, onPressed) in entries)
          _HoverTint(
            onTap: onPressed,
            builder: (context, hovered) => SizedBox(
              width: _iconTargetSize,
              height: _iconTargetSize,
              child: Center(
                child: Icon(
                  icon,
                  size: size,
                  color: _hoverTint(color, hovered),
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

    return _PadSurface(
      fill: scheme.tertiaryContainer,
      border: scheme.tertiary.withValues(alpha: 0.6),
      onTap: onTap,
      onLongPress: onLongPress,
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
                            ? AppIcons.downloading
                            : AppIcons.cloudDownload,
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

    return _PadSurface(
      fill: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      border: isMissing
          ? scheme.error.withValues(alpha: 0.55)
          : scheme.outlineVariant.withValues(alpha: 0.5),
      onTap: onTap,
      onLongPress: onLongPress,
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
                      Text(hint, style: TextStyle(fontSize: 11, color: accent)),
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
            Icon(AppIcons.cloudDownload, size: 14, color: color),
          ],
        ),
      ),
    );
  }
}

/// Surface d'un pad : carte à hairline qui réagit au survol (bordure
/// éclaircie), au clic (voile sombre) et à la lecture (halo [glow]). Les
/// changements de fond et de bordure sont fondus plutôt que commutés.
///
/// Pas de `Transform.scale` à l'enfoncement : le texte du pad serait rééchantillonné
/// (flou), cf. `pad_item.dart`.
class _PadSurface extends StatefulWidget {
  final Color fill;
  final Color border;

  /// Couleur du halo de lecture ; `null` = pas de halo.
  final Color? glow;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  const _PadSurface({
    required this.fill,
    required this.border,
    required this.child,
    this.glow,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<_PadSurface> createState() => _PadSurfaceState();
}

class _PadSurfaceState extends State<_PadSurface> {
  static const Duration _fade = Duration(milliseconds: 140);

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null || widget.onLongPress != null;
    final border = interactive && _hovered
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.2), widget.border)
        : widget.border;
    final glow = widget.glow;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Halo derrière la carte, rogné à l'extérieur de son contour : un
        // `BoxShadow` Flutter n'est pas rogné sous la boîte (contrairement au
        // CSS), il traverserait le fond translucide et teinterait l'intérieur.
        Positioned.fill(
          child: IgnorePointer(
            child: ClipPath(
              clipper: const _OutsidePadClipper(),
              child: AnimatedContainer(
                duration: _fade,
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  borderRadius: AppRadius.radiusPad,
                  boxShadow: glow == null
                      ? const []
                      : [
                          BoxShadow(
                            color: glow.withValues(alpha: 0.3),
                            blurRadius: 16,
                          ),
                        ],
                ),
              ),
            ),
          ),
        ),
        _buildCard(interactive: interactive, border: border),
      ],
    );
  }

  Widget _buildCard({required bool interactive, required Color border}) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: widget.fill),
      duration: _fade,
      builder: (context, fill, child) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: border),
        duration: _fade,
        builder: (context, border, child) => Card(
          elevation: 0,
          // Le clip épouse les coins arrondis : la progression collée au
          // bord bas ne déborde pas.
          clipBehavior: Clip.antiAlias,
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.radiusPad,
            side: BorderSide(color: border ?? widget.border),
          ),
          child: child,
        ),
        child: child,
      ),
      child: interactive
          ? InkWell(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              borderRadius: AppRadius.radiusPad,
              highlightColor: Colors.black.withValues(alpha: 0.16),
              onHover: (value) => setState(() => _hovered = value),
              child: widget.child,
            )
          : widget.child,
    );
  }
}

/// Découpe tout sauf le contour du pad : ne laisse passer que la partie
/// extérieure du halo de lecture.
class _OutsidePadClipper extends CustomClipper<Path> {
  const _OutsidePadClipper();

  @override
  Path getClip(Size size) {
    final pad = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(AppRadius.pad),
    );
    return Path.combine(
      PathOperation.difference,
      Path()..addRect((Offset.zero & size).inflate(64)),
      Path()..addRRect(pad),
    );
  }

  @override
  bool shouldReclip(_OutsidePadClipper oldClipper) => false;
}

/// Barre de progression de lecture d'un pad musique, synchronisée sur la
/// position **réelle** du lecteur. Contrairement à une simple animation 0→1
/// relancée à chaque `play`, elle se ré-aligne à chaque rebuild sur
/// `player.position` (ou sur la position mémorisée en pause) : une reprise après
/// pause repart de l'endroit où le son a été suspendu, jamais de zéro.
class _MusicProgressBar extends StatefulWidget {
  final PadItem padItem;
  final Color color;

  const _MusicProgressBar({required this.padItem, required this.color});

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
    final totalMs =
        (pad.progressPlayer?.duration ?? Duration.zero).inMilliseconds;

    if (pad.isPlaying && totalMs > 0) {
      final posMs = (pad.progressPlayer?.position.inMilliseconds ?? 0).clamp(
        0,
        totalMs,
      );
      _controller.duration = Duration(milliseconds: totalMs);
      _controller.value = posMs / totalMs;
      _controller.forward();
    } else if (pad.isPaused && totalMs > 0) {
      final posMs = (pad.pausedPlaybackPosition?.inMilliseconds ?? 0).clamp(
        0,
        totalMs,
      );
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
        return LinearProgressIndicator(
          value: value,
          backgroundColor: widget.color.withValues(alpha: 0.16),
          valueColor: AlwaysStoppedAnimation<Color>(widget.color),
          minHeight: _barHeight,
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
    final startValue = totalMs > 0
        ? (elapsed.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 1.0;
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
        child: LinearProgressIndicator(
          value: _controller.value,
          backgroundColor: Colors.transparent,
          valueColor: AlwaysStoppedAnimation<Color>(widget.color),
          minHeight: _barHeight,
        ),
      ),
    );
  }
}

/// Zone cliquable sans fond ni ripple : le contenu se teinte lui-même via
/// l'état de survol fourni à [builder] (direction "Console Linear", cf.
/// décision 0023). Le `GestureDetector` opaque capte le tap avant celui du pad.
class _HoverTint extends StatefulWidget {
  const _HoverTint({required this.onTap, required this.builder});

  final VoidCallback? onTap;
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_HoverTint> createState() => _HoverTintState();
}

class _HoverTintState extends State<_HoverTint> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.builder(context, _hovered),
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
  return Icon(icon, size: size, color: color);
}
