// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../settings_screen.dart';

/// Ligne « Gain auto » : recalcul en masse du gain « auto » de tous les sons
/// disponibles sur l'appareil (décisions 0036 et 0045). Méthodes de
/// [_SettingsScreenState] extraites via extension dans le même `part`.
extension _SettingsVolumes on _SettingsScreenState {
  /// Ligne « Gain auto » de la maintenance : un réglage (description +
  /// bouton), la progression se range dessous pendant le calcul.
  Widget _buildVolumeRow() {
    final progress = _autoVolumeProgress;
    final inLiveMode = widget.syncController.isAutoSyncPaused;
    final running = progress != null;

    return SettingsRow(
      title: 'Gain auto',
      description: inLiveMode && !running
          ? 'Indisponible en Mode Spectacle.'
          : 'Mesure la sonie de chaque son téléchargé et règle son gain selon '
                'son type (musique, ambiance, bruitage).',
      trailing: running
          ? SettingsButton(
              label: _autoVolumeCancelRequested ? 'Annulation…' : 'Annuler',
              icon: AppIcons.close,
              onPressed: _autoVolumeCancelRequested
                  ? null
                  : () => setState(() => _autoVolumeCancelRequested = true),
            )
          : SettingsButton(
              label: 'Recalculer',
              icon: AppIcons.tune,
              busy: _isAutoVolumeBusy,
              onPressed: inLiveMode
                  ? null
                  : () => unawaited(_confirmRecomputeAutoVolumes()),
            ),
      below: running
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: progress.total > 0
                      ? progress.done / progress.total
                      : null,
                ),
                const SizedBox(height: AppSpacing.xs + 2),
                SettingsNote(
                  '${progress.done} / ${progress.total} sons mesurés',
                ),
              ],
            )
          : null,
    );
  }

  /// Dresse le plan, demande confirmation (avec ce qui sera remplacé), puis
  /// lance la passe.
  Future<void> _confirmRecomputeAutoVolumes() async {
    if (_isAutoVolumeBusy) return;
    setState(() => _isAutoVolumeBusy = true);
    final AutoVolumePlan plan;
    try {
      plan = await widget.libraryRepository.planAutoVolumeRecompute();
    } catch (e) {
      if (mounted) {
        setState(() => _isAutoVolumeBusy = false);
        showCopyableSnackBar(context, 'Impossible de préparer le calcul : $e');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _isAutoVolumeBusy = false);

    if (plan.sounds.isEmpty) {
      showCopyableSnackBar(
        context,
        'Aucun son téléchargé sur cet appareil : rien à mesurer.',
      );
      return;
    }

    final customized = plan.customized;
    final unmeasured = plan.unmeasured;
    final lines = [
      '${plan.sounds.length} sons téléchargés peuvent être mesurés.',
      if (unmeasured > 0)
        '$unmeasured n\'ont jamais été mesurés (gain par défaut) : les mesurer '
            'ne touche à aucun gain réglé.',
      customized > 0
          ? '$customized ont déjà un gain réglé : « Tout recalculer » le '
                'remplace.'
          : 'Aucun n\'a de gain réglé.',
      if (plan.unavailable > 0)
        '${plan.unavailable} sons non téléchargés sont ignorés.',
      'L\'opération peut prendre plusieurs minutes. Elle peut être annulée : '
          'ce qui est déjà mesuré est conservé.',
    ];
    // `true` : tout recalculer ; `false` : seulement les jamais mesurés.
    final scope = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recalculer les gains ?'),
        content: Text(lines.join('\n\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          if (unmeasured > 0 && customized > 0)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Non mesurés seulement'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(customized > 0 ? 'Tout recalculer' : 'Recalculer'),
          ),
        ],
      ),
    );
    if (scope == null || !mounted) return;
    await _runRecomputeAutoVolumes(scope ? plan : plan.onlyUnmeasured());
  }

  Future<void> _runRecomputeAutoVolumes(AutoVolumePlan plan) async {
    setState(() {
      _isAutoVolumeBusy = true;
      _autoVolumeCancelRequested = false;
      _autoVolumeProgress = (done: 0, total: plan.sounds.length);
    });
    AutoVolumeResult? result;
    Object? error;
    try {
      result = await widget.libraryRepository.recomputeAutoVolumes(
        plan,
        onProgress: (done, total) {
          if (mounted) {
            setState(() => _autoVolumeProgress = (done: done, total: total));
          }
        },
        // Fermer l'écran interrompt la passe : chaque gain est déjà écrit.
        isCancelled: () => _autoVolumeCancelRequested || !mounted,
      );
    } catch (e) {
      error = e;
    }
    // Les boards chargés et l'index de recherche portent l'ancien gain.
    widget.syncController.onLibraryMerged?.call();
    if (!mounted) return;
    setState(() {
      _isAutoVolumeBusy = false;
      _autoVolumeProgress = null;
      _autoVolumeCancelRequested = false;
    });
    if (error != null) {
      showCopyableSnackBar(context, 'Échec du recalcul : $error');
      return;
    }
    final r = result;
    if (r == null) return;
    final failed = r.unmeasurable + r.skipped;
    final prefix = r.cancelled ? 'Recalcul annulé : ' : '';
    final suffix = failed > 0
        ? ', $failed sons non mesurables (gain conservé)'
        : '';
    showCopyableSnackBar(
      context,
      '$prefix${r.updated} gains mis à jour$suffix.',
    );
  }
}
