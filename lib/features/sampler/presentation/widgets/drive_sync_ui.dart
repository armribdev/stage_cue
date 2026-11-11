import 'package:flutter/material.dart';

import '../../../../core/theme/app_dialog.dart';
import '../../domain/entities/library.dart';
import '../providers/sync_controller.dart';

/// Indique une session Google expirée signalée par [SyncController].
bool isDriveAuthExpired(SyncState state) => state.authExpired;

/// Affiche le dialog de résolution de conflit et applique le choix.
Future<void> showSyncConflictDialog({
  required BuildContext context,
  required SyncController syncController,
  required Library library,
  Future<void> Function()? onResolved,
}) async {
  final choice = await showAppDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Conflit de synchronisation'),
        content: const Text(
          'Une version plus récente existe sur Drive. Quelle version garder ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('remote'),
            child: const Text('Prendre Drive'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('local'),
            child: const Text('Garder local'),
          ),
        ],
      );
    },
  );

  if (!context.mounted || choice == null) return;

  if (choice == 'local') {
    await syncController.keepLocal(library);
  } else if (choice == 'remote') {
    await syncController.takeRemote(library);
  }

  if (context.mounted) {
    await onResolved?.call();
  }
}
