part of 'sampler_screen_chrome.dart';

// ---------- Liste des scènes (drawer mobile/tablette) ----------

/// Liste des scènes + actions (live / bibliothèque / paramètres) pour le
/// tiroir mobile/tablette.
class BoardsList extends StatelessWidget {
  final List<SoundBoard> boards;
  final SoundBoard? selectedBoard;
  final bool isBoardsLoading;
  final bool isPerformanceMode;
  final Future<void> Function(SoundBoard board) onSelectBoard;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function(SoundBoard board)? onBoardLongPress;
  final VoidCallback onTogglePerformanceMode;
  final Future<void> Function()? onOpenLibrary;
  final Future<void> Function() onOpenSettings;

  const BoardsList({super.key, 
    required this.boards,
    required this.selectedBoard,
    required this.isBoardsLoading,
    required this.isPerformanceMode,
    required this.onSelectBoard,
    required this.onCreateBoard,
    this.onBoardLongPress,
    required this.onTogglePerformanceMode,
    required this.onOpenLibrary,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final liveTile = ListTile(
      leading: Icon(
        Icons.theater_comedy_rounded,
        color: isPerformanceMode ? scheme.error : null,
      ),
      title: Text(
        isPerformanceMode
            ? 'Quitter la session live'
            : 'Démarrer une session live',
        style: isPerformanceMode
            ? TextStyle(color: scheme.error, fontWeight: FontWeight.w600)
            : null,
      ),
      onTap: onTogglePerformanceMode,
    );

    // Mode Spectacle : le tiroir ne propose que la sortie du mode. Rien
    // d'éditable ni de navigable — on préserve le verrouillage anti-modif du
    // live, tout en gardant l'unique porte de sortie accessible.
    if (isPerformanceMode) {
      return Column(
        children: [const SizedBox(height: 8), liveTile],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(Icons.theater_comedy_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              const Text(
                'Scènes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              if (isBoardsLoading)
                const BoardsListSkeleton()
              else if (boards.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Aucune scène',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                ...boards.map(
                  (board) => ListTile(
                    leading: board.color != null
                        ? BoardTileIcon(color: board.color!)
                        : null,
                    title: Text(board.name),
                    onTap: () => onSelectBoard(board),
                    onLongPress: onBoardLongPress == null
                        ? null
                        : () => onBoardLongPress!(board),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Nouvelle scène'),
                onTap: () => onCreateBoard(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Ordre demandé : mode live, puis bibliothèque, puis paramètres.
        liveTile,
        ListTile(
          leading: const Icon(Icons.library_books_rounded),
          title: const Text('Gérer la bibliothèque'),
          onTap: onOpenLibrary == null ? null : () => onOpenLibrary!(),
        ),
        ListTile(
          leading: const Icon(Icons.settings),
          title: const Text('Paramètres'),
          onTap: () => onOpenSettings(),
        ),
      ],
    );
  }
}

// ---------- Drawer (mobile/tablette) ----------

/// Tiroir latéral encapsulant [BoardsList] dans un [Drawer] + [SafeArea].
class BoardsDrawer extends StatelessWidget {
  final List<SoundBoard> boards;
  final SoundBoard? selectedBoard;
  final bool isBoardsLoading;
  final bool isPerformanceMode;
  final Future<void> Function(SoundBoard board) onSelectBoard;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function(SoundBoard board) onBoardLongPress;
  final VoidCallback onTogglePerformanceMode;
  final Future<void> Function()? onOpenLibrary;
  final Future<void> Function() onOpenSettings;

  const BoardsDrawer({super.key, 
    required this.boards,
    required this.selectedBoard,
    required this.isBoardsLoading,
    required this.isPerformanceMode,
    required this.onSelectBoard,
    required this.onCreateBoard,
    required this.onBoardLongPress,
    required this.onTogglePerformanceMode,
    required this.onOpenLibrary,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: BoardsList(
          boards: boards,
          selectedBoard: selectedBoard,
          isBoardsLoading: isBoardsLoading,
          isPerformanceMode: isPerformanceMode,
          onSelectBoard: onSelectBoard,
          onCreateBoard: onCreateBoard,
          onBoardLongPress: onBoardLongPress,
          onTogglePerformanceMode: onTogglePerformanceMode,
          onOpenLibrary: onOpenLibrary,
          onOpenSettings: onOpenSettings,
        ),
      ),
    );
  }
}

// ---------- Sélecteur de scène (desktop) ----------

/// Menu déroulant desktop pour choisir / créer une scène.
class BoardSceneSelector extends StatelessWidget {
  final List<SoundBoard> boards;
  final SoundBoard? selectedBoard;
  final bool isBoardsLoading;
  final Future<void> Function(SoundBoard board) onSelectBoard;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function(SoundBoard board, Offset position)
  onBoardContextMenu;

  const BoardSceneSelector({super.key, 
    required this.boards,
    required this.selectedBoard,
    required this.isBoardsLoading,
    required this.onSelectBoard,
    required this.onCreateBoard,
    required this.onBoardContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<Object>(
        tooltip: '',
        offset: const Offset(0, 48),
        popUpAnimationStyle: AnimationStyle.noAnimation,
        onSelected: (value) async {
          if (value is SoundBoard) {
            await onSelectBoard(value);
          } else if (value == 'create') {
            await onCreateBoard();
          }
        },
        itemBuilder: (context) => [
          if (isBoardsLoading)
            const PopupMenuItem<Object>(
              enabled: false,
              child: Skeleton(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(widthFactor: 0.7),
                    SizedBox(height: 14),
                    SkeletonLine(widthFactor: 0.5),
                    SizedBox(height: 14),
                    SkeletonLine(widthFactor: 0.6),
                  ],
                ),
              ),
            )
          else if (boards.isEmpty)
            const PopupMenuItem<Object>(
              enabled: false,
              child: Text('Aucune scène'),
            )
          else
            ...boards.map(
              (board) => PopupMenuItem<Object>(
                value: board,
                height: AppMenu.itemHeight,
                padding: AppMenu.itemPadding,
                child: Row(
                  children: [
                    if (board.id == selectedBoard?.id)
                      Icon(Icons.check_rounded, size: 18, color: scheme.primary)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: AppSpacing.sm),
                    if (board.color != null) ...[
                      BoardTileIcon(color: board.color!),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(child: Text(board.name)),
                  ],
                ),
              ),
            ),
          const PopupMenuDivider(),
          PopupMenuItem<Object>(
            value: 'create',
            height: AppMenu.itemHeight,
            padding: AppMenu.itemPadding,
            child: const Row(
              children: [
                Icon(Icons.add, size: 18),
                SizedBox(width: AppSpacing.sm),
                Text('Nouvelle scène'),
              ],
            ),
          ),
        ],
        child: GestureDetector(
          onSecondaryTapDown: selectedBoard != null
              ? (details) =>
                    onBoardContextMenu(selectedBoard!, details.globalPosition)
              : null,
          child: BoardTitleLabel(
            board: selectedBoard,
            trailing: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Titre de scène dans l'AppBar (icône + nom) ----------

/// Pastille titre de scène (point couleur + nom) pour l'AppBar.
class BoardTitleLabel extends StatelessWidget {
  const BoardTitleLabel({super.key, this.board, this.trailing});

  final SoundBoard? board;

  /// Chevron du sélecteur desktop — absent sur le titre mobile (pas de menu
  /// déroulant, le tiroir des scènes s'ouvre par le hamburger).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dotColor = board?.color != null
        ? Color(board!.color!)
        : scheme.onSurfaceVariant.withValues(alpha: 0.5);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: AppRadius.radiusMd,
        border: Border.fromBorderSide(AppElevation.border(scheme)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              board?.name ?? 'Scène',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// ---------- Icône de scène (couleur + icône) ----------

/// Pastille couleur d'une scène dans les listes / menus.
class BoardTileIcon extends StatelessWidget {
  const BoardTileIcon({super.key, required this.color});

  final int color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: Color(color),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
    );
  }
}

// ---------- Placeholders de chargement ----------

/// Liste de scènes factices pour le tiroir latéral pendant le chargement.
class BoardsListSkeleton extends StatelessWidget {
  const BoardsListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Column(
        children: [
          for (int i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              child: Row(
                children: [
                  const SkeletonBox(
                    width: 18,
                    height: 18,
                    borderRadius: AppRadius.radiusXs,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SkeletonLine(widthFactor: i.isEven ? 0.6 : 0.45),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
