import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Petit spinner de barre du sampler : une passe de synchro Drive fait quelque
/// chose (lancement, actualisation manuelle, ou veille qui a trouvé du nouveau).
///
/// Il ne dit rien d'autre — pas d'échec, pas de bilan : ils vivent dans les
/// Paramètres, sur la ligne de chaque bibliothèque. Une veille qui conclut
/// « rien de neuf » ne l'allume jamais (voir `AutoSyncCoordinator.visiblePassActive`).
class SyncActivityIndicator extends StatelessWidget {
  const SyncActivityIndicator({super.key, required this.active});

  final ValueListenable<bool> active;

  /// Côté de la zone occupée, aligné sur les boutons de barre (32 px).
  static const double _slot = 32;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return ValueListenableBuilder<bool>(
      valueListenable: active,
      builder: (context, isActive, _) {
        if (!isActive) return const SizedBox.shrink();
        return Tooltip(
          message: 'Synchronisation avec Drive en cours',
          child: SizedBox(
            width: _slot,
            height: _slot,
            child: Center(
              child: SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: color,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
