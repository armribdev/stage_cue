import 'package:flutter/material.dart';
import '../../domain/entities/pad.dart';
import '../providers/sampler_provider.dart';

/// Widget représentant un pad de son
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

  @override
  Widget build(BuildContext context) {
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
    final soundCount = padItem.pad.sounds.length;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: padItem.isPlaying
              ? scheme.primary.withValues(alpha: 0.5)
              : scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      color: padItem.isPlaying ? playingColor : baseColor,
      child: _buildInteractiveChild(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          children: [
            // Barre de progression en arrière-plan
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
                    if (soundCount > 1) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            switch (padItem.pad.playMode) {
                              PadPlayMode.random => Icons.shuffle_rounded,
                              PadPlayMode.sequential =>
                                Icons.repeat_one_rounded,
                            },
                            size: 11,
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: 0.65,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$soundCount sons',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.65,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sans InkWell en mode édition : laisse le drag de la grille fonctionner.
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
