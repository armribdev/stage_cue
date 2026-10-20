import 'package:flutter/material.dart';

import '../../../../core/database/database.dart' as db;
import '../../../../core/platform/saf_directory_bridge.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/indexed_folder_labels.dart';
import '../../data/models/indexing_progress.dart';
import '../../data/repositories/library_repository.dart';
import '../../domain/entities/library.dart' as domain;

/// Élément de la liste « Éléments indexés » (dossier local ou bibliothèque Drive).
class IndexedFolderItem {
  const IndexedFolderItem.local(this.watchedPath) : library = null;

  const IndexedFolderItem.drive(this.library) : watchedPath = null;

  final db.WatchedPath? watchedPath;
  final domain.Library? library;

  bool get isLocal => watchedPath != null;

  DateTime get addedAt => isLocal ? watchedPath!.addedAt : library!.createdAt;
}

/// Actions du menu ⋮ d'une bibliothèque Drive indexée.
enum _LibraryAction { downloadAll, toggleAutoDownload, remove }

/// Section « Éléments indexés » : liste des dossiers locaux/Drive + pied base.
///
/// L'orchestration OAuth / synchro / confirmations reste dans [SettingsScreen] ;
/// ce widget ne reçoit que les données affichables et des callbacks d'action.
class SettingsIndexedFoldersSection extends StatelessWidget {
  const SettingsIndexedFoldersSection({
    super.key,
    required this.items,
    required this.labelsForItem,
    required this.progressForItem,
    required this.offlineCounts,
    required this.libraryRepository,
    required this.soundCount,
    required this.dbSizeLabel,
    required this.onAddFolder,
    required this.onShowDatabaseState,
    required this.onRemoveLocal,
    required this.onRemoveDrive,
    required this.onDownloadAll,
    required this.onToggleAutoDownload,
  });

  final List<IndexedFolderItem> items;
  final IndexedFolderLabels Function(IndexedFolderItem item) labelsForItem;
  final IndexingProgress Function(IndexedFolderItem item) progressForItem;
  final Map<int, ({int available, int total})> offlineCounts;
  final LibraryRepository libraryRepository;
  final int soundCount;
  final String dbSizeLabel;
  final VoidCallback onAddFolder;
  final VoidCallback onShowDatabaseState;
  final void Function(db.WatchedPath watchedPath) onRemoveLocal;
  final void Function(domain.Library library) onRemoveDrive;
  final void Function(domain.Library library) onDownloadAll;
  final void Function(domain.Library library) onToggleAutoDownload;

  /// Hauteur réservée pour la zone statut : méta (repos) ou barre + libellé
  /// (activité), sans que le passage de l'un à l'autre ne change la hauteur.
  static const double _statusSlotHeight = 30;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.folder_copy, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              'Éléments indexés'.toUpperCase(),
              style: AppTextStyles.sectionLabel(context),
            ),
            const Spacer(),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              visualDensity: VisualDensity.compact,
              tooltip: 'Ajouter un dossier',
              icon: const Icon(Icons.add),
              onPressed: onAddFolder,
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          _buildEmptyIndexedState(context)
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (context, index) => Divider(
              height: 17,
              thickness: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.45),
            ),
            itemBuilder: (context, index) =>
                _buildIndexedItemRow(context, items[index]),
          ),
        _buildDatabaseSummaryFooter(context),
      ],
    );
  }

  Widget _buildEmptyIndexedState(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.folder_off, size: 48, color: muted),
          const SizedBox(height: 8),
          Text(
            'Aucun dossier indexé',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: muted),
          ),
          const SizedBox(height: 8),
          Text(
            'Ajoutez un dossier local ou un dossier Drive',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: muted.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildIndexedItemRow(BuildContext context, IndexedFolderItem item) {
    final labels = labelsForItem(item);
    final progress = progressForItem(item);
    // Même emplacement, même hauteur : activité en cours OU ligne méta au
    // repos, jamais les deux.
    final statusLine =
        _buildItemActivity(context, item, progress) ??
        _buildItemMetaRow(context, item, progress);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            item.isLocal &&
                    SafDirectoryBridge.isSafTreeUri(item.watchedPath!.path)
                ? Icons.cloud
                : item.isLocal
                ? Icons.folder
                : Icons.cloud,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                labels.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                labels.subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: _statusSlotHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: statusLine,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _buildItemTrailing(context, item),
      ],
    );
  }

  /// Libellé compact du nombre de fichiers indexés (état au repos).
  String _fileCountLabel(IndexingProgress progress) {
    final count = progress.total > 0 ? progress.total : progress.current;
    return count <= 1 ? '$count fichier' : '$count fichiers';
  }

  String _formatDriveSyncTimestamp(DateTime syncedAt) {
    final local = syncedAt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final syncDay = DateTime(local.year, local.month, local.day);
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${two(local.hour)}:${two(local.minute)}';

    if (syncDay == today) {
      return "aujourd'hui à $time";
    }
    if (syncDay == today.subtract(const Duration(days: 1))) {
      return 'hier à $time';
    }
    return 'le ${two(local.day)}/${two(local.month)} à $time';
  }

  Widget _buildDriveSyncStatus(BuildContext context, domain.Library library) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant.withValues(alpha: 0.75);
    final lastSync = library.lastSyncedAt;

    if (lastSync == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 13, color: muted),
          const SizedBox(width: 4),
          Text(
            'Pas encore synchronisé',
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.cloud_done_outlined,
          size: 13,
          color: scheme.primary.withValues(alpha: 0.85),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            'Synchronisé ${_formatDriveSyncTimestamp(lastSync)}',
            style: TextStyle(fontSize: 11, color: muted),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Ligne d'information au repos : statut de synchro Drive + nombre de
  /// fichiers indexés, sur une seule ligne compacte (pas de barre pleine).
  Widget _buildItemMetaRow(
    BuildContext context,
    IndexedFolderItem item,
    IndexingProgress indexing,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant.withValues(alpha: 0.75);

    Widget chip(IconData icon, String label, {Color? color}) {
      final c = color ?? muted;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: c)),
        ],
      );
    }

    final fileCount = chip(
      Icons.audiotrack_outlined,
      _fileCountLabel(indexing),
    );

    if (item.isLocal) {
      return fileCount;
    }

    // Indicateur de téléchargement : on affiche TOUJOURS « dispo/total » — le
    // total donne le nombre de fichiers, et « 13/13 » signale aussi que tout
    // est téléchargé.
    final offline = offlineCounts[item.library!.id];
    final Widget availability;
    if (offline == null || offline.total == 0) {
      // Décompte pas encore calculé (ou dossier vide) : nombre de fichiers seul.
      availability = fileCount;
    } else {
      final complete = offline.available >= offline.total;
      availability = chip(
        complete ? Icons.download_done_outlined : Icons.download_outlined,
        '${offline.available}/${offline.total} téléchargés',
        color: complete ? scheme.primary.withValues(alpha: 0.85) : null,
      );
    }

    return Row(
      children: [
        Flexible(child: _buildDriveSyncStatus(context, item.library!)),
        const SizedBox(width: 12),
        availability,
      ],
    );
  }

  /// Zone d'activité unifiée : **une seule** barre de progression à la fois.
  /// Priorité à l'indexation, puis au téléchargement ; au repos, aucune barre
  /// (le décompte de fichiers vit dans [_buildItemMetaRow]).
  Widget? _buildItemActivity(
    BuildContext context,
    IndexedFolderItem item,
    IndexingProgress indexing,
  ) {
    final scheme = Theme.of(context).colorScheme;

    // 1. Indexation en cours (local ou Drive) — prioritaire.
    if (!indexing.isComplete || indexing.error != null) {
      final hasError = indexing.error != null;
      return _buildActivityBlock(
        context,
        value: hasError ? 1.0 : (indexing.total > 0 ? indexing.progress : null),
        color: hasError ? scheme.error : scheme.primary,
        label: hasError
            ? 'Erreur : ${indexing.error}'
            : 'Indexation ${indexing.current}/'
                  '${indexing.total > 0 ? indexing.total : '…'}',
        isError: hasError,
      );
    }

    // 2. Téléchargement des variantes audio (Drive uniquement).
    if (!item.isLocal) {
      final download = libraryRepository.libraryDownloadProgress(
        item.library!.id,
      );
      if (download != null && !download.isComplete) {
        return _buildActivityBlock(
          context,
          value: download.total > 0 ? download.progress : null,
          color: scheme.tertiary,
          label:
              'Téléchargement ${download.current}/'
              '${download.total > 0 ? download.total : '…'}',
          onCancel: () =>
              libraryRepository.cancelLibraryDownload(item.library!.id),
        );
      }
      if (download?.error != null) {
        return _buildActivityBlock(
          context,
          value: 1.0,
          color: scheme.error,
          label: 'Erreur : ${download!.error}',
          isError: true,
        );
      }
    }

    // 3. Au repos : rien à afficher ici.
    return null;
  }

  /// Bloc d'activité empilé : barre de progression **puis libellé en dessous**.
  /// Rendu dans le même emplacement de hauteur fixe ([_statusSlotHeight]) que la
  /// ligne méta, pour que le passage repos ↔ activité ne bouge pas la hauteur.
  /// Erreur : libellé seul (avec ellipsis).
  Widget _buildActivityBlock(
    BuildContext context, {
    required double? value,
    required Color color,
    required String label,
    VoidCallback? onCancel,
    bool isError = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(
      fontSize: 11,
      color: isError ? scheme.error : scheme.onSurfaceVariant,
    );

    if (isError) {
      return Text(
        label,
        style: labelStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 5,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: Text(label, style: labelStyle)),
            if (onCancel != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onCancel,
                behavior: HitTestBehavior.opaque,
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// Zone d'actions d'un élément indexé. Pour un dossier Drive, toutes les
  /// actions secondaires (tout télécharger, téléchargement auto, retirer) sont
  /// regroupées dans un unique menu ⋮ ; un dossier local n'a que « Retirer ».
  Widget _buildItemTrailing(BuildContext context, IndexedFolderItem item) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant.withValues(alpha: 0.7);

    if (item.isLocal) {
      // Même geste (menu ⋮) que pour un dossier Drive, avec ici une seule
      // entrée, pour homogénéiser l'action « Retirer » entre les deux types.
      return PopupMenuButton<_LibraryAction>(
        tooltip: 'Options',
        icon: Icon(Icons.more_vert, color: muted),
        popUpAnimationStyle: AnimationStyle.noAnimation,
        onSelected: (action) {
          if (action == _LibraryAction.remove) {
            onRemoveLocal(item.watchedPath!);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem<_LibraryAction>(
            value: _LibraryAction.remove,
            height: AppMenu.itemHeight,
            padding: AppMenu.itemPadding,
            child: _menuRow(
              Icons.delete_outline,
              'Retirer',
              iconColor: scheme.error,
              textColor: scheme.error,
            ),
          ),
        ],
      );
    }

    final library = item.library!;
    final downloadProgress = libraryRepository.libraryDownloadProgress(
      library.id,
    );
    final isDownloading =
        downloadProgress != null && !downloadProgress.isComplete;
    final offline = offlineCounts[library.id];
    final fullyOffline =
        offline != null &&
        offline.total > 0 &&
        offline.available >= offline.total;

    final String downloadLabel;
    if (isDownloading) {
      downloadLabel = 'Téléchargement en cours…';
    } else if (fullyOffline) {
      downloadLabel = 'Déjà tout téléchargé';
    } else {
      downloadLabel = 'Tout télécharger';
    }

    return PopupMenuButton<_LibraryAction>(
      tooltip: 'Options',
      icon: Icon(Icons.more_vert, color: muted),
      popUpAnimationStyle: AnimationStyle.noAnimation,
      onSelected: (action) {
        switch (action) {
          case _LibraryAction.downloadAll:
            onDownloadAll(library);
          case _LibraryAction.toggleAutoDownload:
            onToggleAutoDownload(library);
          case _LibraryAction.remove:
            onRemoveDrive(library);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<_LibraryAction>(
          value: _LibraryAction.downloadAll,
          enabled: !isDownloading && !fullyOffline,
          height: AppMenu.itemHeight,
          padding: AppMenu.itemPadding,
          child: _menuRow(
            fullyOffline
                ? Icons.download_done_outlined
                : Icons.download_outlined,
            downloadLabel,
          ),
        ),
        PopupMenuItem<_LibraryAction>(
          value: _LibraryAction.toggleAutoDownload,
          height: AppMenu.itemHeight,
          padding: AppMenu.itemPadding,
          child: _menuRow(
            library.autoDownload
                ? Icons.check_box_outlined
                : Icons.check_box_outline_blank,
            'Téléchargement auto',
            iconColor: library.autoDownload ? scheme.primary : null,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_LibraryAction>(
          value: _LibraryAction.remove,
          height: AppMenu.itemHeight,
          padding: AppMenu.itemPadding,
          child: _menuRow(
            Icons.delete_outline,
            'Retirer',
            iconColor: scheme.error,
            textColor: scheme.error,
          ),
        ),
      ],
    );
  }

  /// Ligne icône + libellé pour une entrée du menu ⋮ (mise en page homogène).
  Widget _menuRow(
    IconData icon,
    String label, {
    Color? iconColor,
    Color? textColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: textColor)),
      ],
    );
  }

  /// Pied de carte résumant l'état de la base — remplace l'ancienne icône « i »
  /// peu découvrable : le décompte est désormais visible, et le tap ouvre le
  /// détail complet (taille, chemin copiable).
  Widget _buildDatabaseSummaryFooter(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final soundLabel = '$soundCount son${soundCount > 1 ? 's' : ''}';
    return Column(
      children: [
        const Divider(height: 24),
        InkWell(
          onTap: onShowDatabaseState,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                Icon(Icons.storage_outlined, size: 16, color: muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$soundLabel · $dbSizeLabel',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
                Icon(Icons.info_outline, size: 16, color: muted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
