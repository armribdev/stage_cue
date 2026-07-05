import 'package:flutter/material.dart';

import '../../data/repositories/library_repository.dart';
import '../../domain/entities/library.dart';
import '../providers/sync_controller.dart';

/// Indique une session Google expirée signalée par [SyncController].
bool isDriveAuthExpired(SyncState state) => state.authExpired;

/// Indicateur de synchro Drive compact et non bloquant, destiné à la barre de
/// la page Paramètres.
///
/// Caché tant que la synchro est `idle` (aucun bruit pour un usage 100 % local) ;
/// dès qu'une bibliothèque Drive est en jeu, il rend l'état d'un coup d'œil
/// (couleur + libellé court) et déclenche [onTap] (résolution de conflit ou
/// défilement vers la section Drive).
class SyncStatusPill extends StatelessWidget {
  final SyncController syncController;
  final VoidCallback onTap;

  const SyncStatusPill({
    super.key,
    required this.syncController,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: syncController,
      builder: (context, _) {
        final status = syncController.state.status;
        if (status == SyncStatus.idle) return const SizedBox.shrink();

        final scheme = Theme.of(context).colorScheme;
        final (color, label, icon, spinning) = _visuals(status, scheme);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Tooltip(
            message: 'Synchronisation Drive',
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (spinning)
                      SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    else
                      Icon(icon, size: 15, color: color),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  (Color, String, IconData, bool) _visuals(
    SyncStatus status,
    ColorScheme scheme,
  ) {
    return switch (status) {
      SyncStatus.syncing => (
          scheme.primary,
          'Synchro…',
          Icons.sync_rounded,
          true,
        ),
      SyncStatus.synced => (
          scheme.primary,
          'À jour',
          Icons.cloud_done_outlined,
          false,
        ),
      // Hors-ligne : neutre, jamais alarmiste — le travail local est normal.
      SyncStatus.offline => (
          scheme.onSurfaceVariant,
          'Hors-ligne',
          Icons.cloud_off_outlined,
          false,
        ),
      SyncStatus.conflict => (
          scheme.error,
          'Conflit',
          Icons.merge_type_rounded,
          false,
        ),
      SyncStatus.error => (
          scheme.error,
          'Erreur sync',
          Icons.error_outline_rounded,
          false,
        ),
      SyncStatus.idle => (
          scheme.onSurfaceVariant,
          '',
          Icons.cloud_outlined,
          false,
        ),
    };
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
