import 'package:flutter/material.dart';
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

  const PadButton({
    super.key,
    required this.padItem,
    this.onTap,
    this.onLongPress,
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
    return DashedSlotFrame(
      child: Center(
        child: Icon(
          Icons.library_music_outlined,
          size: 24,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
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
    final playingColor = hasCustomColor
        ? customColor.withValues(alpha: 0.75)
        : scheme.surfaceContainerHigh.withValues(alpha: 0.9);
    final label = padItem.displayName;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: padItem.isPlaying
              ? hasCustomColor
                  ? scheme.primary.withValues(alpha: 0.5)
                  : scheme.onSurfaceVariant.withValues(alpha: 0.55)
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
      child: _interactive(
        child: Stack(
          children: [
            padItem.pad.isMusicPad
                ? _buildPlaybackProgress(scheme, hasCustomColor: hasCustomColor)
                : _buildPolyphonicProgress(scheme, hasCustomColor: hasCustomColor),
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
                        fontWeight: padItem.isPlaying
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: padItem.isPlaying && hasCustomColor
                            ? scheme.primary
                            : scheme.onSurface,
                      ),
                    ),
                    if (padItem.totalSoundCount > 1) ...[
                      const SizedBox(height: 4),
                      _buildVariantChip(scheme),
                    ],
                  ],
                ),
              ),
            ),
            // Badges informatifs : le corps du pad porte l'action. La pause
            // musique est signalée uniquement dans la régie, pas sur le pad.
            if (padItem.isDownloading)
              _buildDownloadCorner(scheme.tertiary),
          ],
        ),
      ),
    );
  }

  /// Barre de progression de lecture (overlay) pendant que le pad joue.
  Widget _buildPlaybackProgress(
    ColorScheme scheme, {
    required bool hasCustomColor,
  }) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(
        'progress_${padItem.pad.id}_${padItem.isPlaying}'
        '_${padItem.currentSoundIndex}',
      ),
      tween: Tween(begin: 0.0, end: padItem.isPlaying ? 1.0 : 0.0),
      duration: padItem.isPlaying
          ? (padItem.currentPlayer?.duration ?? const Duration(seconds: 1))
          : const Duration(milliseconds: 200),
      curve: Curves.linear,
      builder: (context, value, child) {
        if (!padItem.isPlaying && value == 0.0) {
          return const SizedBox.shrink();
        }
        return Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(
                hasCustomColor
                    ? scheme.primary.withValues(alpha: 0.22)
                    : scheme.onSurfaceVariant.withValues(alpha: 0.22),
              ),
              minHeight: double.infinity,
            ),
          ),
        );
      },
    );
  }

  /// Barres de progression superposées (pads non-musique, polyphonie) : une
  /// barre translucide indépendante par voix en cours. Les zones où plusieurs
  /// voix se chevauchent cumulent l'opacité — repère visuel de la densité.
  Widget _buildPolyphonicProgress(
    ColorScheme scheme, {
    required bool hasCustomColor,
  }) {
    final tickets = padItem.playbackTickets;
    if (tickets.isEmpty) return const SizedBox.shrink();
    final barColor = (hasCustomColor ? scheme.primary : scheme.onSurfaceVariant)
        .withValues(alpha: 0.16);
    return Positioned.fill(
      child: Stack(
        children: [
          for (final ticket in tickets)
            Positioned.fill(
              child: _PolyphonicProgressBar(
                key: ValueKey<int>(ticket.id),
                ticket: ticket,
                color: barColor,
              ),
            ),
        ],
      ),
    );
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

  // ── EN ROUTE ──────────────────────────────────────────────────────────────

  Widget _buildEnRoute(BuildContext context, ColorScheme scheme) {
    final label = padItem.displayName;
    final downloading = padItem.isDownloading;
    final onColor = scheme.onTertiaryContainer;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
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

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
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
            Positioned(
              top: 6,
              right: 6,
              child: Icon(icon, size: 14, color: accent.withValues(alpha: 0.8)),
            ),
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
      borderRadius: BorderRadius.circular(14),
      child: child,
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: LinearProgressIndicator(
          value: _controller.value,
          backgroundColor: Colors.transparent,
          valueColor: AlwaysStoppedAnimation<Color>(widget.color),
          minHeight: double.infinity,
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
