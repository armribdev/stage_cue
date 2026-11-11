import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_dialog.dart';
import 'app_update_info.dart';
import 'app_update_installer.dart';
import 'update_log.dart';

/// Délai entre « installeur lancé » et fermeture de l'app : le temps de lire
/// l'état affiché, et à l'installeur de démarrer avant que l'app disparaisse.
const _quitDelay = Duration(seconds: 2);

/// Flux partagé confirmation → téléchargement → lancement silencieux d'une
/// mise à jour, utilisé aussi bien par la notification de lancement
/// (`SoundboardApp`) que par le bouton manuel de Réglages — évite de dupliquer
/// dialogues et gestion d'erreurs aux deux endroits.
///
/// Ne se déclenche jamais sans ce dialogue de confirmation : le téléchargement
/// et l'installation restent une action explicite de l'utilisateur, jamais
/// automatique (outil de spectacle live — une installation qui se lance
/// d'elle-même en pleine représentation serait inacceptable).
///
/// Une fois confirmé, tout se passe dans **un seul** dialogue (téléchargement,
/// installation, erreur éventuelle) : l'état ne passe jamais par un toast.
/// L'app se ferme d'elle-même après avoir lancé l'installeur (ADR 0037) ;
/// [quitApp] est injectable pour les tests.
Future<void> runUpdateFlow(
  BuildContext context,
  AppUpdateInfo info, {
  AppUpdateInstaller? installer,
  Future<void> Function()? quitApp,
}) async {
  final confirmed = await showAppDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Mise à jour disponible'),
      content: Text(
        'Version ${info.version} disponible. Installer maintenant ? '
        'L\'application se fermera et redémarrera automatiquement.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Plus tard'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Installer'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  final resolvedInstaller = installer ?? AppUpdateInstaller();
  final status = ValueNotifier<_UpdateStatus>(const _UpdateStatus.download());

  final dialogClosed = showAppDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => ValueListenableBuilder<_UpdateStatus>(
      valueListenable: status,
      builder: (_, value, _) => _UpdateProgressDialog(
        info: info,
        status: value,
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    ),
  );

  try {
    final installerPath = await resolvedInstaller.downloadInstaller(
      info,
      onProgress: (received, total) {
        status.value = _UpdateStatus.download(
          progress: (total != null && total > 0) ? received / total : null,
        );
      },
    );

    status.value = const _UpdateStatus.install();
    await resolvedInstaller.launchInstallerSilently(installerPath);

    await Future<void>.delayed(_quitDelay);
    UpdateLog.quittingForInstall();
    await (quitApp ?? windowManager.close)();
  } catch (e) {
    // Déjà journalisé par l'installeur (`downloadFailed` / `installLaunchFailed`).
    status.value = _UpdateStatus.failed(
      status.value.step == _UpdateStep.install
          ? 'Échec de l\'installation'
          : 'Échec du téléchargement',
      '$e',
    );
    await dialogClosed;
    status.dispose();
  }
}

enum _UpdateStep { download, install, failed }

class _UpdateStatus {
  const _UpdateStatus.download({this.progress})
    : step = _UpdateStep.download,
      title = null,
      error = null;

  const _UpdateStatus.install()
    : step = _UpdateStep.install,
      progress = null,
      title = null,
      error = null;

  const _UpdateStatus.failed(String this.title, String this.error)
    : step = _UpdateStep.failed,
      progress = null;

  final _UpdateStep step;

  /// Avancement du téléchargement ; `null` ⇒ indéterminé.
  final double? progress;

  /// Titre et détail de l'échec, uniquement pour [_UpdateStep.failed].
  final String? title;
  final String? error;
}

class _UpdateProgressDialog extends StatelessWidget {
  const _UpdateProgressDialog({
    required this.info,
    required this.status,
    required this.onClose,
  });

  final AppUpdateInfo info;
  final _UpdateStatus status;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    switch (status.step) {
      case _UpdateStep.download:
        return AlertDialog(
          title: Text('Téléchargement de la version ${info.version}'),
          content: LinearProgressIndicator(value: status.progress),
        );
      case _UpdateStep.install:
        return AlertDialog(
          title: const Text('Installation en cours'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              LinearProgressIndicator(),
              SizedBox(height: 16),
              Text('L\'application va se fermer puis redémarrer toute seule.'),
            ],
          ),
        );
      case _UpdateStep.failed:
        final error = status.error ?? '';
        return AlertDialog(
          title: Text(status.title ?? 'Échec de la mise à jour'),
          content: SelectableText(error),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: error)),
              child: const Text('Copier'),
            ),
            FilledButton(onPressed: onClose, child: const Text('Fermer')),
          ],
        );
    }
  }
}
