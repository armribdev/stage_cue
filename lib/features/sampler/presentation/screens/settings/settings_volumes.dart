// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../settings_screen.dart';

/// Section « Volumes » : recalcul en masse du volume « auto » de tous les sons
/// disponibles sur l'appareil (décision 0036). Méthodes de
/// [_SettingsScreenState] extraites via extension dans le même `part`.
extension _SettingsVolumes on _SettingsScreenState {
  // Pas de Card : un libellé de section, son contenu, puis le séparateur posé
  // par `_buildSettingsBody` (direction « Console Linear », ADR 0023).
  Widget _buildVolumeSection() {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final progress = _autoVolumeProgress;
    final inLiveMode = widget.syncController.isAutoSyncPaused;
    // Bouton(s) : `minimumSize` surchargé (le thème donne sinon une largeur
    // infinie).
    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(64, 42),
    );

    return _buildSettingsSectionCard(
      title: _buildSectionTitleRow(icon: AppIcons.volumeOn, title: 'Volumes'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mesure la sonie de chaque son téléchargé sur cet appareil et règle '
            'son volume selon son type : musique, ambiance (plus en retrait) '
            'ou bruitage. Les sons non téléchargés sont ignorés. Les volumes '
            'réglés pad par pad ne changent pas.',
            style: muted,
          ),
          const SizedBox(height: 12),
          if (progress != null) ...[
            LinearProgressIndicator(
              value: progress.total > 0 ? progress.done / progress.total : null,
            ),
            const SizedBox(height: 6),
            Text(
              '${progress.done} / ${progress.total} sons mesurés',
              style: muted,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: buttonStyle,
              onPressed: _autoVolumeCancelRequested
                  ? null
                  : () => setState(() => _autoVolumeCancelRequested = true),
              icon: const Icon(AppIcons.close, size: 18),
              label: Text(
                _autoVolumeCancelRequested ? 'Annulation…' : 'Annuler',
              ),
            ),
          ] else ...[
            OutlinedButton.icon(
              style: buttonStyle,
              onPressed: _isAutoVolumeBusy || inLiveMode
                  ? null
                  : () => unawaited(_confirmRecomputeAutoVolumes()),
              icon: _isAutoVolumeBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(AppIcons.tune, size: 18),
              label: const Text('Recalculer les volumes auto'),
            ),
            if (inLiveMode) ...[
              const SizedBox(height: 6),
              Text('Indisponible en Mode Spectacle.', style: muted),
            ],
          ],
        ],
      ),
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
    final lines = [
      '${plan.sounds.length} sons téléchargés vont être mesurés.',
      customized > 0
          ? '$customized ont déjà un volume réglé : il sera remplacé.'
          : 'Aucun n\'a de volume réglé à la main.',
      if (plan.unavailable > 0)
        '${plan.unavailable} sons non téléchargés sont ignorés.',
      'L\'opération peut prendre plusieurs minutes. Elle peut être annulée : '
          'ce qui est déjà mesuré est conservé.',
    ];
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recalculer les volumes ?'),
        content: Text(lines.join('\n\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Recalculer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runRecomputeAutoVolumes(plan);
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
        // Fermer l'écran interrompt la passe : chaque volume est déjà écrit.
        isCancelled: () => _autoVolumeCancelRequested || !mounted,
      );
    } catch (e) {
      error = e;
    }
    // Les boards chargés et l'index de recherche portent l'ancien volume.
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
        ? ', $failed sons non mesurables (volume conservé)'
        : '';
    showCopyableSnackBar(
      context,
      '$prefix${r.updated} volumes mis à jour$suffix.',
    );
  }
}
