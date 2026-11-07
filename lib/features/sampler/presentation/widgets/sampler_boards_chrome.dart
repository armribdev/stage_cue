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

  const BoardsList({
    super.key,
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
        AppIcons.theater,
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
      return Column(children: [const SizedBox(height: 8), liveTile]);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(AppIcons.theater, color: scheme.primary),
              const SizedBox(width: 8),
              const Text(
                'Scènes',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: AppTypography.titleLetterSpacing,
                ),
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
                leading: const Icon(AppIcons.add),
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
          leading: const Icon(AppIcons.library),
          title: const Text('Gérer la bibliothèque'),
          onTap: onOpenLibrary == null ? null : () => onOpenLibrary!(),
        ),
        ListTile(
          leading: const Icon(AppIcons.settings),
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

  const BoardsDrawer({
    super.key,
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
///
/// Ouvert via `showMenu` plutôt que `PopupMenuButton.child` : ce dernier pose
/// son propre `InkWell`, dont le fond de survol (couleur du thème) ne peut pas
/// être neutralisé sans aussi retirer le survol des lignes du menu. Ici le
/// survol ne change que la couleur du texte et du chevron.
class BoardSceneSelector extends StatefulWidget {
  final List<SoundBoard> boards;
  final SoundBoard? selectedBoard;
  final bool isBoardsLoading;
  final Future<void> Function(SoundBoard board) onSelectBoard;
  final Future<void> Function() onCreateBoard;
  final Future<bool> Function(SoundBoard board, Offset position)
  onBoardContextMenu;

  const BoardSceneSelector({
    super.key,
    required this.boards,
    required this.selectedBoard,
    required this.isBoardsLoading,
    required this.onSelectBoard,
    required this.onCreateBoard,
    required this.onBoardContextMenu,
  });

  @override
  State<BoardSceneSelector> createState() => _BoardSceneSelectorState();
}

class _BoardSceneSelectorState extends State<BoardSceneSelector> {
  bool _hovered = false;

  Future<void> _openMenu(BuildContext context) async {
    final scheme = Theme.of(context).colorScheme;
    final selectedId = widget.selectedBoard?.id;

    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(
          Offset(0, button.size.height + 8),
          ancestor: overlay,
        ),
        button.localToGlobal(
          button.size.bottomRight(const Offset(0, 8)),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final value = await showMenu<Object>(
      context: context,
      position: position,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      items: [
        if (widget.isBoardsLoading)
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
        else if (widget.boards.isEmpty)
          const PopupMenuItem<Object>(
            enabled: false,
            child: Text('Aucune scène'),
          )
        else
          ...widget.boards.map(
            (board) => PopupMenuItem<Object>(
              value: board,
              height: AppMenu.itemHeight,
              padding: AppMenu.itemPadding,
              // Clic droit sur une scène de la liste : ses actions (renommer,
              // dupliquer, supprimer) s'ouvrent par-dessus le menu, qui reste
              // ouvert si on les écarte. Une action choisie change la liste
              // (nom, suppression) : le menu, devenu périmé, se ferme alors.
              child: Builder(
                builder: (itemContext) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onSecondaryTapDown: (details) async {
                    final acted = await widget.onBoardContextMenu(
                      board,
                      details.globalPosition,
                    );
                    if (acted && itemContext.mounted) {
                      Navigator.of(itemContext).pop();
                    }
                  },
                  child: SizedBox(
                    height: AppMenu.itemHeight,
                    child: Row(
                      children: [
                        if (board.id == selectedId)
                          Icon(AppIcons.check, size: 18, color: scheme.primary)
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
              Icon(AppIcons.add, size: 18),
              SizedBox(width: AppSpacing.sm),
              Text('Nouvelle scène'),
            ],
          ),
        ),
      ],
    );

    if (!mounted || value == null) return;
    if (value is SoundBoard) {
      await widget.onSelectBoard(value);
    } else if (value == 'create') {
      await widget.onCreateBoard();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _hovered ? scheme.onSurface : scheme.onSurfaceVariant;
    final board = widget.selectedBoard;

    return Align(
      alignment: Alignment.centerLeft,
      // `Builder` : le contexte doit mesurer l'étiquette, pas l'`Align` pleine
      // largeur, pour ancrer le menu juste sous le nom de la scène.
      child: Builder(
        builder: (context) => MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_openMenu(context)),
            child: BoardTitleLabel(
              board: board,
              framed: false,
              color: color,
              trailing: Icon(AppIcons.chevronDown, size: 18, color: color),
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
  const BoardTitleLabel({
    super.key,
    this.board,
    this.trailing,
    this.framed = true,
    this.color,
  });

  final SoundBoard? board;

  /// Couleur du nom (défaut : celle du titre d'AppBar).
  final Color? color;

  /// `false` : ni fond ni bordure, juste point de couleur + nom.
  final bool framed;

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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: 6,
      ),
      decoration: framed
          ? BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: AppRadius.radiusMd,
              border: Border.fromBorderSide(AppElevation.border(scheme)),
            )
          : null,
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
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
