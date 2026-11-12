import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/database/database.dart' as db;
import '../../../../core/platform/saf_directory_bridge.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/indexed_folder_labels.dart';
import '../../../../core/utils/sync_time_label.dart';
import '../../data/models/indexing_progress.dart';
import '../../data/repositories/library_repository.dart';
import '../../domain/entities/library.dart' as domain;
import '../../../../core/sync/auto_sync_coordinator.dart'
    show LibraryPassOutcome, SyncPassStage;
import 'boxed_icon_button.dart';
import 'settings_layout.dart';
import '../../../../core/theme/stroke_icon.dart';

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

/// « Synchronisé il y a 3 min » : se redessine à chaque changement de minute
/// tant que la date est dans la fenêtre relative, puis s'arrête — au-delà, le
/// format absolu ne bouge plus. Le minuteur est un tir unique replanifié, pas
/// un `Timer.periodic`, pour tomber pile sur le passage à la minute suivante.
class _SyncAgeText extends StatefulWidget {
  const _SyncAgeText({required this.syncedAt, required this.style});

  final DateTime syncedAt;
  final TextStyle style;

  @override
  State<_SyncAgeText> createState() => _SyncAgeTextState();
}

class _SyncAgeTextState extends State<_SyncAgeText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(_SyncAgeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncedAt != widget.syncedAt) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final age = syncAge(widget.syncedAt);
    if (age >= kRelativeSyncWindow) {
      _timer = null;
      return;
    }
    // Prochain changement de libellé : la minute entière suivante.
    _timer = Timer(Duration(seconds: 60 - age.inSeconds % 60), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      'Synchronisé ${formatDriveSyncTimestamp(widget.syncedAt)}',
      style: widget.style,
      overflow: TextOverflow.ellipsis,
    );
  }
}

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
    required this.networkAllowed,
    required this.autoSyncPaused,
    required this.refreshingLibraryIds,
    required this.passOutcomes,
    required this.passStages,
    required this.conflictLibraryId,
    required this.onRefresh,
    required this.onRefreshLibrary,
    required this.onResolveConflict,
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

  /// Le mode réseau autorise la synchro : sinon l'actualisation est grisée,
  /// avec la raison en infobulle plutôt qu'un refus après coup.
  final bool networkAllowed;

  /// Mode Spectacle : la synchro **automatique** (veille, push) est suspendue.
  /// L'actualisation manuelle, geste explicite, reste possible.
  final bool autoSyncPaused;

  /// Bibliothèques visées par la passe manuelle en cours (vide : aucune passe).
  /// Chacune l'indique par un spinner sur sa ligne ; le bouton d'actualisation,
  /// lui, ne change pas d'aspect.
  final Set<int> refreshingLibraryIds;

  /// Bilan de la dernière passe par bibliothèque (clé : `Library.id`) : ce qui
  /// a changé, ou l'échec avec « Réessayer » (qui relance [onRefreshLibrary]).
  final Map<int, LibraryPassOutcome> passOutcomes;

  /// Étape en cours de la passe, par bibliothèque. Une bibliothèque sans entrée
  /// n'a pas été atteinte (ou la passe rejointe n'a rien remonté) : libellé
  /// générique.
  final Map<int, SyncPassStage> passStages;

  /// Bibliothèque dont le dernier push est en conflit (choix utilisateur requis).
  final int? conflictLibraryId;

  /// Actualise toutes les bibliothèques Drive. Le bouton n'existe que s'il y en
  /// a au moins une.
  final VoidCallback onRefresh;

  /// Actualise une seule bibliothèque (clic sur sa date de synchro).
  final void Function(domain.Library library) onRefreshLibrary;
  final void Function(domain.Library library) onResolveConflict;
  final VoidCallback onAddFolder;
  final VoidCallback onShowDatabaseState;
  final void Function(db.WatchedPath watchedPath) onRemoveLocal;
  final void Function(domain.Library library) onRemoveDrive;
  final void Function(domain.Library library) onDownloadAll;
  final void Function(domain.Library library) onToggleAutoDownload;

  /// Hauteur réservée pour la zone statut : méta (repos) ou barre + libellé
  /// (activité), sans que le passage de l'un à l'autre ne change la hauteur.
  static const double _statusSlotHeight = 30;

  /// Une passe manuelle tourne : pas de seconde en parallèle.
  bool get _isRefreshing => refreshingLibraryIds.isNotEmpty;

  /// Une actualisation est lançable : réseau autorisé et aucune passe en cours.
  bool get _canRefresh => networkAllowed && !_isRefreshing;

  /// Marge intérieure des infos de la ligne méta : c'est elle qui dessine le
  /// fond de survol autour du texte. Appliquée aussi quand l'info n'est pas
  /// cliquable, pour que la mise en page ne bouge pas quand elle le devient.
  static const EdgeInsets _metaPadding = EdgeInsets.symmetric(
    horizontal: 6,
    vertical: 3,
  );

  /// Info de la ligne méta, cliquable si [onTap] est fourni (sans cadre ni
  /// ripple, infobulle et curseur main). `onTap` nul : même encombrement,
  /// aucune interaction.
  Widget _metaInfo({
    required Widget child,
    String? tooltip,
    VoidCallback? onTap,
  }) {
    if (onTap == null) return Padding(padding: _metaPadding, child: child);
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        borderRadius: AppRadius.radiusSm,
        onTap: onTap,
        child: Padding(padding: _metaPadding, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(
          icon: AppIcons.folders,
          title: 'Éléments indexés',
          trailing: [
            if (items.any((item) => !item.isLocal)) _buildRefreshButton(),
            BoxedIconButton(
              icon: AppIcons.add,
              tooltip: 'Ajouter un dossier',
              framed: false,
              compact: true,
              onPressed: onAddFolder,
            ),
          ],
        ),
        _buildSuspendedLine(context),
        const SizedBox(height: AppSpacing.md),
        if (items.isEmpty)
          _buildEmptyIndexedState(context)
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (context, index) => const Divider(height: 17),
            itemBuilder: (context, index) =>
                _buildIndexedItemRow(context, items[index]),
          ),
        _buildDatabaseSummaryFooter(context),
      ],
    );
  }

  /// Pourquoi la synchro automatique ne tourne pas, quand elle ne tourne pas.
  /// Une ligne d'état et non un toast : la raison doit rester lisible tant
  /// qu'elle dure, y compris au toucher où l'infobulle du bouton n'existe pas.
  /// Muette sans bibliothèque Drive (rien à suspendre) ; l'app en arrière-plan
  /// n'y figure pas — cet écran n'est visible qu'au premier plan.
  Widget _buildSuspendedLine(BuildContext context) {
    if (!items.any((item) => !item.isLocal)) return const SizedBox.shrink();
    final (StrokeIconData icon, String label)? reason = !networkAllowed
        ? (AppIcons.cloudOff, 'Mode hors ligne · synchronisation désactivée')
        : autoSyncPaused
        ? (
            AppIcons.theater,
            'Mode Spectacle · synchronisation automatique suspendue',
          )
        : null;
    if (reason == null) return const SizedBox.shrink();

    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          StrokeIcon(reason.$1, size: AppIconSize.sm, color: muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              reason.$2,
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ),
        ],
      ),
    );
  }

  /// Actualisation manuelle des bibliothèques Drive : une action, pas un état.
  /// L'état de chaque bibliothèque (dernière synchro, indexation, conflit) vit
  /// sur sa propre ligne ; ce bouton ne fait que relancer la séquence complète
  /// (utile quand la veille, qui ne fait jamais de scan complet, y renonce).
  Widget _buildRefreshButton() {
    return BoxedIconButton(
      icon: AppIcons.refresh,
      tooltip: networkAllowed
          ? 'Actualiser depuis Drive'
          : 'Mode hors ligne — passez en mode Connecté pour actualiser',
      framed: false,
      compact: true,
      // Désactivé pendant la passe : pas de seconde passe en parallèle.
      onPressed: _canRefresh ? onRefresh : null,
    );
  }

  Widget _buildEmptyIndexedState(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          StrokeIcon(AppIcons.folderOff, size: 48, color: muted),
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
    // Même emplacement, même hauteur : activité en cours, sinon conflit à
    // résoudre, sinon ligne méta au repos — jamais plusieurs à la fois.
    final statusLine =
        _buildItemActivity(context, item, progress) ??
        _buildConflictLine(context, item) ??
        _buildPassOutcomeLine(context, item) ??
        _buildItemMetaRow(context, item, progress);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: StrokeIcon(
            item.isLocal &&
                    SafDirectoryBridge.isSafTreeUri(item.watchedPath!.path)
                ? AppIcons.cloud
                : item.isLocal
                ? AppIcons.folder
                : AppIcons.cloud,
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

  /// Conflit de synchro sur cette bibliothèque : seul état qui exige un geste de
  /// l'utilisateur, donc seul à être cliquable sur la ligne.
  Widget? _buildConflictLine(BuildContext context, IndexedFolderItem item) {
    final library = item.library;
    if (library == null || library.id != conflictLibraryId) return null;
    final color = Theme.of(context).colorScheme.error;
    return InkWell(
      onTap: () => onResolveConflict(library),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StrokeIcon(AppIcons.merge, size: AppIconSize.sm, color: color),
          const SizedBox(width: 4),
          Text(
            'Conflit de synchronisation · Résoudre',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Bilan de la dernière passe pour cette bibliothèque : échec (cliquable pour
  /// réessayer) ou résumé des changements. `null` s'il n'y a rien à dire — la
  /// ligne retombe alors sur la méta « Synchronisé … ».
  Widget? _buildPassOutcomeLine(BuildContext context, IndexedFolderItem item) {
    final library = item.library;
    if (library == null) return null;
    final outcome = passOutcomes[library.id];
    if (outcome == null) return null;
    final scheme = Theme.of(context).colorScheme;

    if (outcome.failed) {
      final color = scheme.error;
      final label = outcome.authExpired
          ? 'Session Google expirée · Renouveler ci-dessus'
          : 'Non actualisé · Réessayer';
      final content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StrokeIcon(AppIcons.error, size: AppIconSize.sm, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      );
      // Une session expirée se règle ailleurs : relancer la passe n'y ferait rien.
      // « Réessayer » ne relance que CETTE bibliothèque : les autres ont réussi.
      return outcome.authExpired
          ? content
          : InkWell(
              onTap: _canRefresh ? () => onRefreshLibrary(library) : null,
              child: content,
            );
    }

    if (!outcome.hasChanges) return null;
    final parts = [
      if (outcome.added > 0)
        outcome.added == 1
            ? '1 ajouté ou modifié'
            : '${outcome.added} ajoutés ou modifiés',
      if (outcome.removed > 0)
        outcome.removed == 1 ? '1 retiré' : '${outcome.removed} retirés',
    ];
    final color = scheme.primary.withValues(alpha: 0.85);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StrokeIcon(AppIcons.cloudDone, size: AppIconSize.sm, color: color),
        const SizedBox(width: 4),
        Text(parts.join(' · '), style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }

  /// Libellé compact du nombre de fichiers indexés (état au repos).
  String _fileCountLabel(IndexingProgress progress) {
    final count = progress.total > 0 ? progress.total : progress.current;
    return count <= 1 ? '$count fichier' : '$count fichiers';
  }

  Widget _buildDriveSyncStatus(BuildContext context, domain.Library library) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant.withValues(alpha: 0.75);
    final lastSync = library.lastSyncedAt;

    final Widget content;
    if (lastSync == null) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StrokeIcon(AppIcons.cloudOff, size: AppIconSize.sm, color: muted),
          const SizedBox(width: 4),
          Text(
            'Pas encore synchronisé',
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ],
      );
    } else {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StrokeIcon(
            AppIcons.cloudDone,
            size: AppIconSize.sm,
            color: scheme.primary.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: _SyncAgeText(
              syncedAt: lastSync,
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ),
        ],
      );
    }

    // Un clic relance la synchro de cette bibliothèque seule. Grisé (non
    // cliquable) hors ligne ou pendant une passe : la ligne d'état de la
    // section et le spinner de la ligne disent déjà pourquoi.
    return _metaInfo(
      tooltip: 'Actualiser ce dossier',
      onTap: _canRefresh ? () => onRefreshLibrary(library) : null,
      child: content,
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

    Widget chip(StrokeIconData icon, String label, {Color? color}) {
      final c = color ?? muted;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StrokeIcon(icon, size: AppIconSize.sm, color: c),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: c)),
        ],
      );
    }

    final fileCount = chip(AppIcons.audioFile, _fileCountLabel(indexing));

    if (item.isLocal) {
      return fileCount;
    }

    // Indicateur de téléchargement : on affiche TOUJOURS « dispo/total » — le
    // total donne le nombre de fichiers, et « 13/13 » signale aussi que tout
    // est téléchargé.
    final library = item.library!;
    final offline = offlineCounts[library.id];
    final Widget availability;
    if (offline == null || offline.total == 0) {
      // Décompte pas encore calculé (ou dossier vide) : nombre de fichiers seul.
      availability = _metaInfo(child: fileCount);
    } else {
      final complete = offline.available >= offline.total;
      final downloadProgress = libraryRepository.libraryDownloadProgress(
        library.id,
      );
      final isDownloading =
          downloadProgress != null && !downloadProgress.isComplete;
      availability = _metaInfo(
        tooltip: 'Tout télécharger',
        // Même condition que l'entrée « Tout télécharger » du menu ⋮ : rien à
        // lancer si tout est déjà là ou si un téléchargement est en cours.
        onTap: complete || isDownloading ? null : () => onDownloadAll(library),
        child: chip(
          complete ? AppIcons.downloadDone : AppIcons.download,
          '${offline.available}/${offline.total} téléchargés',
          color: complete ? scheme.primary.withValues(alpha: 0.85) : null,
        ),
      );
    }

    // Décalée de la marge intérieure vers la gauche : le fond de survol déborde
    // du texte, qui reste aligné sur le titre de la ligne. Les deux infos se
    // touchent : leurs marges (2 × 6 px) font l'écart entre les textes.
    return Transform.translate(
      offset: Offset(-_metaPadding.left, 0),
      child: Row(
        children: [
          Flexible(child: _buildDriveSyncStatus(context, item.library!)),
          availability,
        ],
      ),
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

    // 3. Passe de synchro manuelle en cours, sans indexation ni téléchargement
    // à montrer (les étapes sans progression chiffrée : pull, ré-élagage).
    if (!item.isLocal && refreshingLibraryIds.contains(item.library!.id)) {
      final muted = scheme.onSurfaceVariant;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(switch (passStages[item.library!.id]) {
            SyncPassStage.detecting => 'Recherche des changements…',
            SyncPassStage.scanning => 'Analyse complète de Drive…',
            SyncPassStage.pulling => 'Récupération des scènes…',
            null => 'Synchronisation…',
          }, style: TextStyle(fontSize: 11, color: muted)),
        ],
      );
    }

    // 4. Au repos : rien à afficher ici.
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
                child: StrokeIcon(
                  AppIcons.close,
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
        icon: StrokeIcon(AppIcons.more, color: muted),
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
              AppIcons.delete,
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

    final downloadLabel = isDownloading
        ? 'Téléchargement en cours…'
        : 'Tout télécharger';

    return PopupMenuButton<_LibraryAction>(
      tooltip: 'Options',
      icon: StrokeIcon(AppIcons.more, color: muted),
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
        // Tout est déjà là : l'entrée n'a plus rien à proposer, on la retire
        // plutôt que de l'afficher grisée.
        if (!fullyOffline)
          PopupMenuItem<_LibraryAction>(
            value: _LibraryAction.downloadAll,
            enabled: !isDownloading,
            height: AppMenu.itemHeight,
            padding: AppMenu.itemPadding,
            child: _menuRow(AppIcons.download, downloadLabel),
          ),
        PopupMenuItem<_LibraryAction>(
          value: _LibraryAction.toggleAutoDownload,
          height: AppMenu.itemHeight,
          padding: AppMenu.itemPadding,
          child: _menuRow(
            library.autoDownload ? AppIcons.checkboxOn : AppIcons.checkboxOff,
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
            AppIcons.delete,
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
    StrokeIconData icon,
    String label, {
    Color? iconColor,
    Color? textColor,
  }) {
    return Row(
      children: [
        StrokeIcon(icon, size: 20, color: iconColor),
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
                StrokeIcon(AppIcons.storage, size: 16, color: muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$soundLabel · $dbSizeLabel',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
                StrokeIcon(AppIcons.info, size: 16, color: muted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
