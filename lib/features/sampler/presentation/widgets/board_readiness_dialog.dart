import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/audio/cue_audio_service.dart';

import '../../../../core/theme/app_dialog.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/board_readiness.dart';
import '../providers/sampler_provider.dart';

/// Bilan de préparation du plateau, montré avant d'entrer en Mode Spectacle.
///
/// Ne bloque jamais : l'utilisateur peut toujours entrer en scène. Le bilan est
/// recalculé à chaque changement du [SamplerNotifier], donc il se met à jour
/// pendant « Tout télécharger », et à chaque changement de casque.
///
/// Sur une plateforme qui sait router une sortie séparée, le casque de
/// pré-écoute se choisit ici même ([onSelectCueDevice] le persiste).
class BoardReadinessDialog extends StatefulWidget {
  const BoardReadinessDialog({
    super.key,
    required this.notifier,
    required this.onSelectCueDevice,
  });

  final SamplerNotifier notifier;

  /// Applique et persiste le casque choisi (`null` = aucun).
  final Future<void> Function(String? deviceId) onSelectCueDevice;

  /// Renvoie `true` si l'utilisateur choisit d'entrer en Mode Spectacle.
  static Future<bool> show(
    BuildContext context, {
    required SamplerNotifier notifier,
    required Future<void> Function(String? deviceId) onSelectCueDevice,
  }) async {
    final enter = await showAppDialog<bool>(
      context: context,
      builder: (_) => BoardReadinessDialog(
        notifier: notifier,
        onSelectCueDevice: onSelectCueDevice,
      ),
    );
    return enter ?? false;
  }

  @override
  State<BoardReadinessDialog> createState() => _BoardReadinessDialogState();
}

class _BoardReadinessDialogState extends State<BoardReadinessDialog> {
  final CueAudioService _cue = CueAudioService.instance;
  late String? _selectedId = _cue.selectedDeviceId;
  late List<CueDevice> _devices = _cue.cachedDevices;
  bool _isLoadingDevices = false;

  /// Vrai une fois la liste des sorties lue au moins une fois : avant, un casque
  /// choisi absent de [_devices] n'est pas « introuvable », il est « en cours
  /// de recherche ».
  late bool _devicesLoaded = _cue.cachedDevices.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (CueAudioService.isSupported && !_devicesLoaded) {
      unawaited(_refreshDevices());
    }
  }

  Future<void> _refreshDevices() async {
    setState(() => _isLoadingDevices = true);
    final devices = await _cue.refreshDevices();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _devicesLoaded = true;
      _isLoadingDevices = false;
    });
  }

  Future<void> _selectDevice(String? deviceId) async {
    setState(() => _selectedId = deviceId);
    await widget.onSelectCueDevice(deviceId);
  }

  CueReadinessInput get _cueInput => CueReadinessInput(
    isSupported: CueAudioService.isSupported,
    selectedDeviceId: _selectedId,
    visibleDeviceIds: {for (final d in _devices) d.id},
  );

  @override
  Widget build(BuildContext context) {
    final notifier = widget.notifier;
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) {
        final state = notifier.state;
        final report = BoardReadinessReport.build(
          pads: state.pads,
          cue: _cueInput,
        );
        final canDownload =
            report.fixable.isNotEmpty &&
            notifier.allowsSoundDownload &&
            !state.isBoardPreparing;

        return AlertDialog(
          title: const Text('Plateau prêt ?', style: TextStyle(fontSize: 17)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${report.playablePadCount} pad'
                    '${report.playablePadCount > 1 ? 's' : ''} sur '
                    '${report.padCount} prêt'
                    '${report.playablePadCount > 1 ? 's' : ''} à jouer.',
                  ),
                  if (state.isBoardPreparing) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: state.boardPrepareTotal > 0
                          ? state.boardPrepareDone / state.boardPrepareTotal
                          : null,
                      minHeight: 4,
                    ),
                  ],
                  _Section(
                    label: 'Ne jouera pas',
                    icon: AppIcons.error,
                    issues: report.blocking,
                    emphasize: true,
                  ),
                  _Section(
                    label: 'À télécharger',
                    icon: AppIcons.cloudDownload,
                    issues: report.fixable,
                  ),
                  _Section(
                    label: 'À savoir',
                    icon: AppIcons.info,
                    issues: report.warnings,
                  ),
                  if (CueAudioService.isSupported) _buildCuePicker(context),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            if (canDownload)
              TextButton(
                onPressed: () => notifier.prepareBoardForOffline(),
                child: const Text('Tout télécharger'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(minimumSize: const Size(64, 42)),
              child: Text(
                report.isReady ? 'Entrer en scène' : 'Entrer quand même',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCuePicker(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedId = _selectedId;
    final known = _devices.any((d) => d.id == selectedId);
    // Un casque choisi mais absent de la liste garde sa place dans le menu :
    // sans valeur correspondante, le champ lèverait une assertion.
    final orphanLabel = _isLoadingDevices
        ? 'Recherche du périphérique…'
        : 'Casque introuvable';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'CASQUE DE PRÉ-ÉCOUTE',
                style: AppTextStyles.sectionLabel(context),
              ),
            ),
            IconButton(
              tooltip: 'Actualiser la liste',
              visualDensity: VisualDensity.compact,
              icon: _isLoadingDevices
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(AppIcons.refresh, size: 16),
              onPressed: _isLoadingDevices ? null : _refreshDevices,
            ),
          ],
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String?>(
          // Clé sur la valeur : `initialValue` n'est lu qu'à la création du
          // champ, il faut le recréer quand elle change.
          key: ValueKey(selectedId),
          initialValue: selectedId,
          isExpanded: true,
          icon: const Icon(AppIcons.chevronDown, size: 18),
          decoration: const InputDecoration(isDense: true),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Désactivé'),
            ),
            for (final device in _devices)
              DropdownMenuItem<String?>(
                value: device.id,
                child: Text(device.label, overflow: TextOverflow.ellipsis),
              ),
            if (selectedId != null && !known)
              DropdownMenuItem<String?>(
                value: selectedId,
                child: Text(orphanLabel, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) => unawaited(_selectDevice(value)),
        ),
        const SizedBox(height: 8),
        Text(
          _devicesLoaded && _devices.isEmpty
              ? 'Aucune sortie supplémentaire détectée. Branchez un casque '
                    'puis actualisez la liste.'
              : 'Sans casque, les pré-écoutes sont désactivées en Mode '
                    'Spectacle.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.icon,
    required this.issues,
    this.emphasize = false,
  });

  final String label;
  final IconData icon;
  final List<BoardReadinessIssue> issues;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final color = emphasize ? scheme.error : scheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 12),
        Text(label.toUpperCase(), style: AppTextStyles.sectionLabel(context)),
        const SizedBox(height: 8),
        for (final issue in issues)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 14, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(_describe(issue))),
              ],
            ),
          ),
      ],
    );
  }
}

String _describe(BoardReadinessIssue issue) {
  final label = issue.padLabel ?? '';
  final partial = issue.totalSounds > 1
      ? ' (${issue.affectedSounds}/${issue.totalSounds} sons)'
      : '';
  return switch (issue.kind) {
    ReadinessIssueKind.missingFile => '$label — fichier introuvable$partial',
    ReadinessIssueKind.unsupportedFormat =>
      '$label — format audio non pris en charge$partial',
    ReadinessIssueKind.offline =>
      '$label — hors-ligne, fichier absent du cache$partial',
    ReadinessIssueKind.needsDownload =>
      '$label — pas encore téléchargé$partial',
    ReadinessIssueKind.emptyPad => '$label — pad sans son',
    ReadinessIssueKind.cueNotChosen =>
      'Aucun casque choisi : pas de pré-écoute en Mode Spectacle.',
    ReadinessIssueKind.cueUnavailable =>
      'Le casque de pré-écoute choisi est introuvable : la pré-écoute '
          'sera refusée.',
  };
}
