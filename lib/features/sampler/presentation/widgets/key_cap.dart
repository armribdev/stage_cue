import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

/// Touche de clavier (« ↵ », « Échap »…) : libellé mono dans un filet.
///
/// Par défaut, la touche des pieds d'aide (fond plein, 12 px). [compact] : la
/// version en ligne, à côté d'un libellé (sans fond, 10 px, teinte discrète).
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key, this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: compact ? null : scheme.surfaceContainerHighest,
        borderRadius: AppRadius.radiusXs,
        border: Border.fromBorderSide(AppElevation.borderStrong(scheme)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: Text(
          label,
          style: AppFonts.monoStyle(
            TextStyle(
              fontSize: compact ? 10 : 12,
              color: compact ? scheme.onSurfaceVariant : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
