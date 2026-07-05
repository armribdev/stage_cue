import 'package:flutter/material.dart';

import '../../data/repositories/library_repository.dart';
import '../../domain/entities/library.dart';
import '../providers/sync_controller.dart';

/// Indique une session Google expirée signalée par [SyncController].
bool isDriveAuthExpired(SyncState state) => state.authExpired;

/// Bandeau d'état de synchronisation Drive (Paramètres, section Google Drive).
class SyncStatusBanner extends StatelessWidget {
  final SyncState state;

  const SyncStatusBanner({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (state.status) {
      SyncStatus.idle => (
          Icons.cloud_queue,
          'Prêt',
          scheme.onSurfaceVariant,
        ),
      SyncStatus.syncing => (
          Icons.sync,
          'Synchronisation…',
          scheme.primary,
        ),
      SyncStatus.synced => (
          Icons.check_circle,
          'Synchronisé',
          scheme.primary,
        ),
      SyncStatus.offline => (
          Icons.cloud_off,
          'Hors-ligne',
          scheme.tertiary,
        ),
      SyncStatus.conflict => (
          Icons.warning,
          'Conflit',
          scheme.error,
        ),
      SyncStatus.error => (
          Icons.error,
          'Erreur',
          scheme.error,
        ),
    };

    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: color)),
        if (state.message != null) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              state.message!,
              style: TextStyle(fontSize: 12, color: scheme.error),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

/// Affiche le dialog de résolution de conflit et applique le choix.
Future<void> showSyncConflictDialog({
  required BuildContext context,
  required SyncController syncController,
  required Library library,
  Future<void> Function()? onResolved,
}) async {
  final choice = await showDialog<String>(
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

/// Résout un conflit depuis la pastille : cible la bibliothèque mémorisée
/// ou propose un choix si plusieurs bibliothèques Drive sont liées.
Future<void> resolveSyncConflictFromPill({
  required BuildContext context,
  required SyncController syncController,
  required LibraryRepository libraryRepository,
  Future<void> Function()? onResolved,
}) async {
  final conflictId = syncController.state.conflictLibraryId;
  if (conflictId != null) {
    final library = await libraryRepository.getLibraryById(conflictId);
    if (library != null && context.mounted) {
      await showSyncConflictDialog(
        context: context,
        syncController: syncController,
        library: library,
        onResolved: onResolved,
      );
      return;
    }
  }

  final libraries = await libraryRepository.getLibraries();
  final connected =
      libraries.where((library) => library.isConnectedToDrive).toList();

  if (!context.mounted) return;

  if (connected.isEmpty) {
    return;
  }

  if (connected.length == 1) {
    await showSyncConflictDialog(
      context: context,
      syncController: syncController,
      library: connected.first,
      onResolved: onResolved,
    );
    return;
  }

  final picked = await showDialog<Library>(
    context: context,
    builder: (dialogContext) {
      return SimpleDialog(
        title: const Text('Conflit de synchronisation'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Quelle bibliothèque Drive est concernée ?',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final library in connected)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(library),
              child: Text(library.name),
            ),
        ],
      );
    },
  );

  if (!context.mounted || picked == null) return;

  await showSyncConflictDialog(
    context: context,
    syncController: syncController,
    library: picked,
    onResolved: onResolved,
  );
}
