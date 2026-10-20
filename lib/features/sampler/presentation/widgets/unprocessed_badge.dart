import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

/// Pastille « N » des sons à traiter, pour une entrée de menu. Ne dessine rien
/// quand il n'y a plus rien à traiter.
class UnprocessedCountPill extends StatelessWidget {
  const UnprocessedCountPill({super.key, required this.count});

  final ValueListenable<int> count;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ValueListenableBuilder<int>(
      valueListenable: count,
      builder: (context, value, _) {
        if (value <= 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: AppRadius.radiusMd,
            border: Border.all(color: accent.withValues(alpha: 0.5)),
          ),
          child: Text(
            '$value à traiter',
            style: AppFonts.monoStyle(TextStyle(fontSize: 11, color: accent)),
          ),
        );
      },
    );
  }
}

/// Point d'accent posé en haut à droite de [child] tant qu'il reste des sons à
/// traiter : signale depuis le bouton menu qu'il y a du travail en attente.
class UnprocessedDot extends StatelessWidget {
  const UnprocessedDot({super.key, required this.count, required this.child});

  final ValueListenable<int> count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ValueListenableBuilder<int>(
      valueListenable: count,
      child: child,
      builder: (context, value, child) {
        if (value <= 0) return child ?? const SizedBox.shrink();
        return Stack(
          clipBehavior: Clip.none,
          children: [
            ?child,
            Positioned(
              top: 4,
              right: 6,
              child: IgnorePointer(
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
