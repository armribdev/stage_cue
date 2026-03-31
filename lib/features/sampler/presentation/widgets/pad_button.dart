import 'package:flutter/material.dart';
import '../providers/sampler_provider.dart';

/// Widget représentant un pad de son
class PadButton extends StatelessWidget {
  final SoundItem soundItem;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onRemove;

  const PadButton({
    super.key,
    required this.soundItem,
    required this.onTap,
    this.onLongPress,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final customColor = soundItem.buttonColor;
    final defaultColor = Theme.of(context).colorScheme.surface;
    final baseColor = customColor ?? defaultColor;
    final playingColor = customColor != null
        ? customColor.withValues(alpha: 0.75)
        : Theme.of(context).colorScheme.primaryContainer;
    final displayName = soundItem.sound.displayName;
    final label = (displayName != null && displayName.trim().isNotEmpty)
        ? displayName
        : soundItem.sound.title;

    return Card(
      elevation: soundItem.isPlaying ? 8 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      color: soundItem.isPlaying ? playingColor : baseColor,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            // Barre de progression en arrière-plan
            TweenAnimationBuilder<double>(
              key: ValueKey('progress_${soundItem.sound.id}_${soundItem.isPlaying}'),
              tween: Tween(begin: 0.0, end: soundItem.isPlaying ? 1.0 : 0.0),
              duration: soundItem.isPlaying
                  ? soundItem.player.duration
                  : const Duration(milliseconds: 200),
              curve: Curves.linear,
              builder: (context, value, child) {
                if (!soundItem.isPlaying && value == 0.0) {
                  return const SizedBox.shrink();
                }
                return Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: value,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
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
                        fontSize: 14,
                        fontWeight: soundItem.isPlaying
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: soundItem.isPlaying
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Positioned(
            //   top: 8,
            //   right: 8,
            //   child: IconButton(
            //     icon: const Icon(Icons.close, size: 20),
            //     color: Colors.grey[600],
            //     onPressed: onRemove,
            //     tooltip: 'Retirer',
            //   ),
            // ),
          ],
        ),
      ),
    );
  }
}

