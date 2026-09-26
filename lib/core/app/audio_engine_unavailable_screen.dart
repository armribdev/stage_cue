import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Écran bloquant quand SoLoud n'a pas pu démarrer.
///
/// Sans moteur audio, la régie est inutilisable : on refuse l'UI normale
/// (pads cliquables en silence) et on propose un retry explicite.
class AudioEngineUnavailableScreen extends StatelessWidget {
  const AudioEngineUnavailableScreen({
    super.key,
    required this.error,
    required this.onRetry,
    this.isRetrying = false,
  });

  final Object error;
  final VoidCallback onRetry;
  final bool isRetrying;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = error.toString().trim();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.volume_off_outlined,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Moteur audio indisponible',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontFamily: AppFonts.ui,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Stage Cue n\'a pas pu démarrer le moteur audio. '
                    'Vérifiez qu\'un périphérique de sortie est branché '
                    'et disponible, puis réessayez.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: AppFonts.ui,
                      color: AppColors.textDim,
                      height: 1.45,
                    ),
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: AppRadius.radiusMd,
                        border: Border.all(
                          color: AppColors.border,
                          width: AppElevation.borderWidth,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: SelectableText(
                          detail,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: AppFonts.mono,
                            color: AppColors.textFaint,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton(
                    onPressed: isRetrying ? null : onRetry,
                    child: isRetrying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
