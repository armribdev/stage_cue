part of '../settings_screen.dart';

/// Section « Analyse automatique » : installation du pack de modèles qui permet
/// de poser des tags d'ambiance sur les musiques non traitées (décision 0029).
/// Méthodes de [_SettingsScreenState] extraites via extension dans le même `part`.
extension _SettingsAutoTag on _SettingsScreenState {
  Widget _buildAutoTagSection(AutoTagPackController controller) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsSection(
      icon: AppIcons.sparkles,
      title: 'Analyse automatique',
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final status = controller.status;
          final total = controller.totalBytes;
          final received = controller.receivedBytes;
          final failure = controller.lastError;
          final downloading = status == AutoTagPackStatus.downloading;
          final installed = status == AutoTagPackStatus.installed;

          final String description;
          if (downloading) {
            description =
                'Téléchargement : ${_formatBytes(received)} / '
                '${_formatBytes(total)}';
          } else if (installed) {
            description = 'Installé.';
          } else if (failure != null) {
            description = 'Téléchargement échoué : $failure';
          } else {
            description = 'Non installé.';
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SettingsNote(
                'Suggère des tags d’ambiance (Triste, Tension, Joyeux…) pour '
                'vos musiques, sur cet appareil. À ajouter vous-même depuis la '
                'fiche du son.',
              ),
              const SizedBox(height: AppSpacing.sm),
              SettingsRow(
                title: 'Pack de modèles',
                description: description,
                descriptionColor: !downloading && !installed && failure != null
                    ? scheme.error
                    : null,
                trailing: downloading
                    ? SettingsButton(
                        label: 'Annuler',
                        icon: AppIcons.close,
                        onPressed: controller.cancel,
                      )
                    : installed
                    ? SettingsButton(
                        label: 'Supprimer',
                        icon: AppIcons.delete,
                        onPressed: () =>
                            unawaited(_confirmRemoveAutoTagPack(controller)),
                      )
                    : SettingsButton(
                        label: 'Télécharger (${_formatBytes(total)})',
                        icon: AppIcons.download,
                        onPressed: status == AutoTagPackStatus.unknown
                            ? null
                            : () => unawaited(controller.install()),
                      ),
                below: downloading
                    ? LinearProgressIndicator(
                        value: total > 0 ? received / total : null,
                      )
                    : null,
              ),
              const SizedBox(height: AppSpacing.xs),
              const SettingsNote(
                'Modèle MuQ-MuLan (OpenMuQ, Tencent AI Lab) · CC BY-NC 4.0, '
                'usage non commercial.',
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
    final confirmed = await showAppDialog<bool>(
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
