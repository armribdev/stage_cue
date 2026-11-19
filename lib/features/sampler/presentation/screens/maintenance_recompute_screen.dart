import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/stroke_icon.dart';
import '../providers/maintenance_recompute_controller.dart';
import '../widgets/app_modal.dart';
import '../widgets/settings_layout.dart';

/// Recalcul de maintenance, **réservé au développeur** (build debug, ouvert
/// depuis Réglages → Maintenance) — décision 0049.
///
/// On coche ce qu'on veut recalculer (waveforms, gains, suggestions de tags,
/// empreintes audio) ; la passe tourne sur les sons **déjà téléchargés**, l'un
/// après l'autre, et peut être annulée sans rien perdre de ce qui est fait.
class MaintenanceRecomputeScreen extends StatefulWidget {
  final MaintenanceRecomputeController controller;

  /// Pack de modèles installé : sans lui, les empreintes audio ne peuvent pas
  /// être recalculées (les effacer serait irréversible).
  final bool packInstalled;
  final bool isModal;

  const MaintenanceRecomputeScreen({
    super.key,
    required this.controller,
    required this.packInstalled,
    this.isModal = false,
  });

  static Future<void> open(
    BuildContext context, {
    required MaintenanceRecomputeController controller,
    required bool packInstalled,
  }) {
    return openAdaptiveScreen(
      context: context,
      builder: ({required isModal}) => MaintenanceRecomputeScreen(
        controller: controller,
        packInstalled: packInstalled,
        isModal: isModal,
      ),
    );
  }

  @override
  State<MaintenanceRecomputeScreen> createState() =>
      _MaintenanceRecomputeScreenState();
}

class _MaintenanceRecomputeScreenState
    extends State<MaintenanceRecomputeScreen> {
  final Set<RecomputeTask> _selected = {};

  MaintenanceRecomputeController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle(RecomputeTask task) {
    setState(() {
      if (!_selected.remove(task)) _selected.add(task);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final body = _buildBody(context);
        // Quitter pendant une passe laisserait un contrôleur libéré écrire.
        return PopScope(
          canPop: !_controller.isRunning,
          child: widget.isModal
              ? AppModalShell(
                  title: 'Recalcul (dev)',
                  body: body,
                  onClose: () => Navigator.of(context).maybePop(),
                )
              : Scaffold(
                  appBar: AppBar(title: const Text('Recalcul (dev)')),
                  body: body,
                ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    final plan = _controller.plan;
    if (_controller.loadError != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SettingsNote(
          'Lecture de la base impossible : ${_controller.loadError}',
          color: Theme.of(context).colorScheme.error,
        ),
      );
    }
    if (plan == null) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final running = _controller.isRunning;
    final blocked = _controller.isBlockedByLiveMode;
    final tagsAvailable = _controller.hasAutoTag;
    final fingerprints = _selected.contains(RecomputeTask.fingerprints);
    // Les empreintes entraînent les suggestions : la case se coche d'elle-même.
    final effective = {
      ..._selected,
      if (fingerprints) RecomputeTask.suggestions,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppModalStyle.padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsNote(
            blocked
                ? 'Indisponible en Mode Spectacle.'
                : '${plan.local.length} son(s) téléchargé(s) sur cet appareil '
                      '(${plan.unavailable} non téléchargé(s) ignoré(s) : rien '
                      'n\'est téléchargé).',
          ),
          const SizedBox(height: AppSpacing.sm),
          _taskRow(
            task: RecomputeTask.waveforms,
            title: 'Waveforms',
            description:
                'Recalcule l\'enveloppe de chacun des ${plan.local.length} '
                'sons (${plan.staleWaveforms} manquante(s) ou périmée(s)). '
                'Ne touche à aucun gain.',
            checked: effective.contains(RecomputeTask.waveforms),
            enabled: !running && !blocked,
          ),
          const Divider(height: 1),
          _taskRow(
            task: RecomputeTask.gains,
            title: 'Gain auto',
            description:
                'Remesure la sonie des ${plan.local.length} sons et '
                '${plan.customizedGains > 0 ? 'remplace ${plan.customizedGains} gain(s) déjà réglé(s)' : 'écrit leur gain'}.',
            checked: effective.contains(RecomputeTask.gains),
            enabled: !running && !blocked,
          ),
          const Divider(height: 1),
          _taskRow(
            task: RecomputeTask.suggestions,
            title: 'Suggestions de tags',
            description: tagsAvailable
                ? 'Recalcule les suggestions des ${plan.eligibleMusic} '
                      'musique(s) non traitée(s) depuis leur empreinte. La '
                      'synchro fusionne par union : un autre appareil peut '
                      'rendre d\'anciennes suggestions. Tags posés et sons '
                      'traités ne sont jamais touchés.'
                : 'Analyse indisponible sur cet appareil.',
            checked: effective.contains(RecomputeTask.suggestions),
            enabled: !running && !blocked && tagsAvailable && !fingerprints,
          ),
          const Divider(height: 1),
          _taskRow(
            task: RecomputeTask.fingerprints,
            title: 'Empreintes audio',
            description: !tagsAvailable
                ? 'Analyse indisponible sur cet appareil.'
                : widget.packInstalled
                ? 'Efface puis ré-analyse l\'audio des ${plan.eligibleMusic} '
                      'musique(s) non traitée(s) : long. Recalcule aussi leurs '
                      'suggestions.'
                : 'Le pack de modèles n\'est pas installé : effacer les '
                      'empreintes serait irréversible.',
            checked: fingerprints,
            enabled:
                !running && !blocked && tagsAvailable && widget.packInstalled,
          ),
          const SizedBox(height: AppSpacing.md),
          _buildRunBar(context, effective, blocked: blocked),
          if (_controller.report.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (final line in _controller.report)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: SettingsNote(line),
              ),
          ],
        ],
      ),
    );
  }

  Widget _taskRow({
    required RecomputeTask task,
    required String title,
    required String description,
    required bool checked,
    required bool enabled,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: AppRadius.radiusSm,
      onTap: enabled ? () => _toggle(task) : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: SettingsRow(
          title: title,
          description: description,
          trailing: StrokeIcon(
            checked ? AppIcons.checkboxOn : AppIcons.checkboxOff,
            color: checked ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildRunBar(
    BuildContext context,
    Set<RecomputeTask> effective, {
    required bool blocked,
  }) {
    final progress = _controller.progress;
    if (!_controller.isRunning) {
      return Align(
        alignment: Alignment.centerRight,
        child: SettingsButton(
          label: 'Recalculer',
          icon: AppIcons.refresh,
          onPressed: effective.isEmpty || blocked
              ? null
              : () => _controller.run(effective),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          value: progress != null && progress.total > 0
              ? progress.done / progress.total
              : null,
        ),
        const SizedBox(height: AppSpacing.xs + 2),
        Row(
          children: [
            Expanded(
              child: SettingsNote(
                '${_controller.stage ?? ''}'
                '${progress != null && progress.total > 0 ? ' : ${progress.done} / ${progress.total}' : ''}',
              ),
            ),
            SettingsButton(
              label: _controller.cancelRequested ? 'Annulation…' : 'Annuler',
              icon: AppIcons.close,
              onPressed: _controller.cancelRequested
                  ? null
                  : _controller.requestCancel,
            ),
          ],
        ),
      ],
    );
  }
}
