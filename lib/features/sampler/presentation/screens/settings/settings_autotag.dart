part of '../settings_screen.dart';

/// Section « Analyse automatique » : installation du pack de modèles qui permet
/// de poser des tags d'ambiance sur les musiques non traitées (décision 0029).
/// Méthodes de [_SettingsScreenState] extraites via extension dans le même `part`.
extension _SettingsAutoTag on _SettingsScreenState {
  // Pas de Card : libellé de section, contenu, puis le séparateur posé par
  // `_buildSettingsBody` (direction « Console Linear », ADR 0023).
  Widget _buildAutoTagSection(AutoTagPackController controller) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    // Boutons : `minimumSize` surchargé (le thème donne sinon une largeur infinie).
    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(64, 42),
    );

    return _buildSettingsSectionCard(
      title: _buildSectionTitleRow(
        icon: Icons.auto_awesome_outlined,
        title: 'Analyse automatique',
      ),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final status = controller.status;
          final total = controller.totalBytes;
          final received = controller.receivedBytes;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pose des tags d’ambiance (Triste, Tension, Joyeux…) sur vos '
                'musiques, d’après le son, directement sur cet appareil, dès '
                'qu’elles sont indexées. Ces tags sont à part des vôtres : '
                'vous pouvez les masquer (ils restent en mémoire et l’IA ne '
                'les repose pas). Un son que vous passez en « traité » n’est '
                'plus analysé. L’analyse se fait en arrière-plan, jamais en '
                'Mode Spectacle.',
                style: muted,
              ),
              const SizedBox(height: 12),
              if (status == AutoTagPackStatus.downloading) ...[
                LinearProgressIndicator(
                  value: total > 0 ? received / total : null,
                ),
                const SizedBox(height: 6),
                Text(
                  'Téléchargement du pack : ${_formatBytes(received)} / '
                  '${_formatBytes(total)}',
                  style: muted,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: buttonStyle,
                  onPressed: controller.cancel,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Annuler'),
                ),
              ] else if (status == AutoTagPackStatus.installed) ...[
                Text('Pack de modèles installé.', style: muted),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: buttonStyle,
                  onPressed: () =>
                      unawaited(_confirmRemoveAutoTagPack(controller)),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Supprimer le pack'),
                ),
              ] else ...[
                Text(
                  'Nécessite un pack de modèles d\'environ '
                  '${_formatBytes(total)}, téléchargé une fois.',
                  style: muted,
                ),
                if (controller.lastError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Téléchargement échoué : ${controller.lastError}',
                    style: muted?.copyWith(color: scheme.error),
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: buttonStyle,
                  onPressed: status == AutoTagPackStatus.unknown
                      ? null
                      : () => unawaited(controller.install()),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: Text('Télécharger le pack (${_formatBytes(total)})'),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Modèle MuQ-MuLan (OpenMuQ, Tencent AI Lab), licence '
                'CC BY-NC 4.0 : usage non commercial uniquement.',
                style: muted,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmRemoveAutoTagPack(
    AutoTagPackController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le pack ?'),
        content: const Text(
          'Les tags déjà posés sont conservés. Les nouvelles musiques ne '
          'seront plus analysées tant que le pack n\'est pas retéléchargé.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await controller.remove();
  }
}
