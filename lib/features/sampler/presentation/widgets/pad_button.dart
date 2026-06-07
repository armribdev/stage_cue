import 'package:flutter/material.dart';
import '../../domain/entities/pad.dart';
import '../models/pad_sound_slot.dart';
import '../providers/sampler_provider.dart';

/// Widget représentant un pad de son
class PadButton extends StatelessWidget {
  final PadItem padItem;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  /// Déclenché par le badge (téléchargement des variantes manquantes).
  final VoidCallback? onBadgeTap;

  const PadButton({
    super.key,
    required this.padItem,
    this.onTap,
    this.onLongPress,
    this.onBadgeTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!padItem.isPlayable && padItem.unavailabilityReason != null) {
      return _buildUnavailableCard(context, padItem.unavailabilityReason!);
    }

    final scheme = Theme.of(context).colorScheme;
    final colorValue = padItem.pad.colorValue;
    final customColor = colorValue != null ? Color(colorValue) : null;
    final defaultColor =
        scheme.surfaceContainerHighest.withValues(alpha: 0.75);
    final baseColor = customColor ?? defaultColor;
    final playingColor = customColor != null
        ? customColor.withValues(alpha: 0.75)
        : scheme.primaryContainer.withValues(alpha: 0.85);
    final label = padItem.pad.displayName;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: padItem.isPlaying
              ? scheme.primary.withValues(alpha: 0.5)
              : padItem.isPartiallyReady
                  ? scheme.tertiary.withValues(alpha: 0.45)
                  : scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      color: padItem.isPlaying ? playingColor : baseColor,
      child: _buildInteractiveChild(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          children: [
            TweenAnimationBuilder<double>(
              key: ValueKey(
                'progress_${padItem.pad.id}_${padItem.isPlaying}'
                '_${padItem.currentSoundIndex}',
              ),
              tween: Tween(begin: 0.0, end: padItem.isPlaying ? 1.0 : 0.0),
              duration: padItem.isPlaying
                  ? (padItem.currentPlayer?.duration ??
                      const Duration(seconds: 1))
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
                        scheme.primary.withValues(alpha: 0.22),
                      ),
                      minHeight: double.infinity,
                    ),
                  ),
                );
              },
            ),
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
                        color: padItem.isPlaying
                            ? scheme.primary
                            : scheme.onSurface,
                      ),
                    ),
                    if (padItem.totalSoundCount > 1) ...[
                      const SizedBox(height: 4),
                      _buildVariantChip(context, scheme),
                    ],
                  ],
                ),
              ),
            ),
            if (padItem.isPartiallyReady || padItem.isDownloading)
              _buildPartialBadge(context, scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildVariantChip(BuildContext context, ColorScheme scheme) {
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

  Widget _buildPartialBadge(BuildContext context, ColorScheme scheme) {
    final onBadgeTap = this.onBadgeTap;
    if (padItem.isDownloading) {
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
                  color: scheme.tertiary,
                ),
              ),
              Icon(
                Icons.cloud_download_outlined,
                size: 14,
                color: scheme.tertiary,
              ),
            ],
          ),
        ),
      );
    }

    if (onBadgeTap == null) return const SizedBox.shrink();

    return Positioned(
      top: 4,
      right: 4,
      child: IconButton(
        icon: Icon(Icons.cloud_download_outlined, size: 16),
        tooltip: 'Télécharger les variantes manquantes',
        onPressed: onBadgeTap,
        color: scheme.tertiary,
        splashRadius: 14,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      ),
    );
  }

  Widget _buildUnavailableCard(
    BuildContext context,
    PadUnavailabilityReason reason,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final label = padItem.pad.displayName;

    final (badgeIcon, badgeColor) = switch (reason) {
      PadUnavailabilityReason.needsDownload => (
          Icons.cloud_download_outlined,
          scheme.onSurfaceVariant.withValues(alpha: 0.55),
        ),
      PadUnavailabilityReason.offline => (
          Icons.cloud_off_outlined,
          scheme.onSurfaceVariant.withValues(alpha: 0.45),
        ),
      PadUnavailabilityReason.missingFile => (
          Icons.warning_amber_rounded,
          scheme.error.withValues(alpha: 0.55),
        ),
    };

    final badge = Positioned(
      top: 4,
      right: 4,
      child: switch (reason) {
        PadUnavailabilityReason.needsDownload => padItem.isDownloading
            ? SizedBox(
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
                        color: badgeColor,
                      ),
                    ),
                    Icon(badgeIcon, size: 16, color: badgeColor),
                  ],
                ),
              )
            : IconButton(
                icon: Icon(badgeIcon, size: 16),
                tooltip: 'Télécharger',
                onPressed: onBadgeTap,
                color: badgeColor,
                splashRadius: 14,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              ),
        _ => Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(badgeIcon, size: 14, color: badgeColor),
          ),
      },
    );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: _buildInteractiveChild(
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
                        color: scheme.onSurface.withValues(alpha: 0.35),
                      ),
                    ),
                    if (padItem.totalSoundCount > 1) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${padItem.totalSoundCount} variantes',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            badge,
          ],
        ),
      ),
    );
  }

  Widget _buildInteractiveChild({
    required VoidCallback? onTap,
    required VoidCallback? onLongPress,
    required Widget child,
  }) {
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

/// Icône de statut d'une variante (liste de téléchargement, détails pad…).
Widget padSoundAvailabilityIcon(
  PadSoundAvailability availability,
  ColorScheme scheme, {
  double size = 18,
}) {
  final (icon, color) = switch (availability) {
    PadSoundAvailability.ready => (
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
  };
  return Icon(icon, size: size, color: color);
}
