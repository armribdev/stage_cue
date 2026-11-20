import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_dialog.dart';
import '../utils/app_snackbar.dart';
import 'app_update_info.dart';
import 'app_update_installer.dart';
import 'update_log.dart';

/// Délai entre « installeur lancé » et fermeture de l'app : le temps de lire
/// l'état affiché, et à l'installeur de démarrer avant que l'app disparaisse.
const _quitDelay = Duration(seconds: 2);

/// Une seule mise à jour à la fois : la progression étant une notification et
/// non plus un dialogue modal, l'app reste utilisable pendant le téléchargement
/// et un second clic (toast de lancement, bouton de Réglages) le relancerait.
bool _updateInProgress = false;

/// Flux partagé confirmation → téléchargement → lancement silencieux d'une
/// mise à jour, utilisé aussi bien par la notification de lancement
/// (`SoundboardApp`) que par le bouton manuel de Réglages — évite de dupliquer
/// dialogue et gestion d'erreurs aux deux endroits.
///
/// Ne se déclenche jamais sans le dialogue de confirmation : le téléchargement
/// et l'installation restent une action explicite de l'utilisateur, jamais
/// automatique (outil de spectacle live — une installation qui se lance
/// d'elle-même en pleine représentation serait inacceptable).
///
/// Une fois confirmé, l'état (téléchargement avec sa barre, installation,
/// erreur éventuelle) vit dans **une notification permanente**
/// ([AppToastController.persistent]) : elle ne bloque pas l'app et ne disparaît
/// pas seule (ADR 0052). L'app se ferme d'elle-même après avoir lancé
/// l'installeur (ADR 0037) ; [quitApp] est injectable pour les tests.
Future<void> runUpdateFlow(
  BuildContext context,
  AppUpdateInfo info, {
  AppUpdateInstaller? installer,
  Future<void> Function()? quitApp,
}) async {
  if (_updateInProgress) return;
  _updateInProgress = true;
  try {
    await _runUpdateFlow(context, info, installer: installer, quitApp: quitApp);
  } finally {
    _updateInProgress = false;
  }
}

Future<void> _runUpdateFlow(
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
  final notification = AppSnackBar.controller.persistent;
  var installing = false;

  notification.value = AppPersistentToast(
    message: 'Téléchargement de la version ${info.version}',
    showsProgress: true,
  );

  try {
    final installerPath = await resolvedInstaller.downloadInstaller(
      info,
      onProgress: (received, total) {
        notification.value = AppPersistentToast(
          message: 'Téléchargement de la version ${info.version}',
          showsProgress: true,
          progress: (total != null && total > 0) ? received / total : null,
        );
      },
    );

    installing = true;
    notification.value = const AppPersistentToast(
      message: 'Installation en cours — l\'application va redémarrer.',
      showsProgress: true,
    );
    await resolvedInstaller.launchInstallerSilently(installerPath);

    await Future<void>.delayed(_quitDelay);
    UpdateLog.quittingForInstall();
    await (quitApp ?? windowManager.close)();
  } catch (e) {
    // Déjà journalisé par l'installeur (`downloadFailed` / `installLaunchFailed`).
    notification.value = AppPersistentToast(
      message:
          '${installing ? 'Échec de l\'installation' : 'Échec du téléchargement'}'
          ' : $e',
      severity: AppToastSeverity.error,
      dismissible: true,
    );
  }
}
