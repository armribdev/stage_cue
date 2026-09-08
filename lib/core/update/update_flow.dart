import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/app_snackbar.dart';
import 'app_update_info.dart';
import 'app_update_installer.dart';

/// Flux partagé confirmation → téléchargement → lancement silencieux d'une
/// mise à jour, utilisé aussi bien par la notification de lancement
/// (`SoundboardApp`) que par le bouton manuel de Réglages — évite de dupliquer
/// dialogues et gestion d'erreurs aux deux endroits.
///
/// Ne se déclenche jamais sans ce dialogue de confirmation : le téléchargement
/// et l'installation restent une action explicite de l'utilisateur, jamais
/// automatique (outil de spectacle live — une installation qui se lance
/// d'elle-même en pleine représentation serait inacceptable).
Future<void> runUpdateFlow(BuildContext context, AppUpdateInfo info) async {
  final confirmed = await showDialog<bool>(
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

  final installer = AppUpdateInstaller();
  final progress = ValueNotifier<double?>(0);

  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Téléchargement en cours'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (context, value, _) =>
              LinearProgressIndicator(value: value),
        ),
      ),
    ),
  );

  String installerPath;
  try {
    installerPath = await installer.downloadInstaller(
      info,
      onProgress: (received, total) {
        progress.value = (total != null && total > 0)
            ? received / total
            : null;
      },
    );
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      showCopyableSnackBar(context, 'Échec du téléchargement : $e');
    }
    return;
  } finally {
    progress.dispose();
  }

  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();

  try {
    await installer.launchInstallerSilently(installerPath);
  } catch (e) {
    if (context.mounted) {
      showCopyableSnackBar(
        context,
        'Échec du lancement de l\'installeur : $e',
      );
    }
    return;
  }

  if (context.mounted) {
    AppSnackBar.show(
      context,
      'Installation en cours — l\'application va redémarrer…',
      duration: const Duration(seconds: 6),
    );
  }
}
