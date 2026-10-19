// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../sampler_screen.dart';

/// Gestion des scènes : sélection, création, renommage, duplication, suppression.
/// Méthodes de [_SamplerScreenState] extraites via extension dans le même `part`.
extension _SamplerScreenBoards on _SamplerScreenState {

  /// Sélectionne un board et ferme le drawer (mobile).
  Future<void> _selectBoard(SoundBoard board) async {
    Navigator.pop(context);
    await _notifier.selectBoard(board);
  }

  /// Sélectionne un board sans fermer de drawer (sidebar desktop).
  Future<void> _selectBoardDirect(SoundBoard board) async {
    await _notifier.selectBoard(board);
  }

  Future<void> _createBoard() async {
    if (!mounted) return;

    final suggestedName = _buildSuggestedBoardName(_notifier.state.boards);
    final libraries = await _notifier.getConnectedLibraries();
    if (!mounted) return;
    // Une seule bibliothèque : pré-sélectionnée (conserve l'ancien comportement
    // auto). Sinon défaut « Local » et l'opérateur choisit explicitement.
    final initialLibraryId = libraries.length == 1 ? libraries.first.id : null;
    final result = await AppBoardCreationDialog.show(
      context,
      suggestedName: suggestedName,
      libraries: [
        for (final library in libraries) (id: library.id, name: library.name),
      ],
      initialLibraryId: initialLibraryId,
    );

    if (result == null || !mounted) return;
    // Ferme le drawer s'il est ouvert (mobile — no-op si pas de drawer).
    final scaffoldState = _scaffoldKey.currentState;
    if (scaffoldState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }

    final newBoard = await _notifier.createBoard(
      result.name,
      color: result.color,
      libraryId: result.libraryId,
    );
    if (!mounted) return;
    if (newBoard == null) {
      showCopyableSnackBar(context, 'Erreur lors de la création de la scène');
    }
  }

  String _buildSuggestedBoardName(List<SoundBoard> boards) {
    final existingNames = boards
        .map((b) => b.name.trim().toLowerCase())
        .where((n) => n.isNotEmpty)
        .toSet();
    var index = 1;
    while (existingNames.contains('scène $index')) {
      index++;
    }
    return 'Scène $index';
  }

  String _buildSuggestedDuplicateBoardName(
    String sourceName,
    List<SoundBoard> boards,
  ) {
    final existingNames = boards
        .map((b) => b.name.trim().toLowerCase())
        .where((n) => n.isNotEmpty)
        .toSet();
    final baseName = '$sourceName (copie)';
    if (!existingNames.contains(baseName.toLowerCase())) {
      return baseName;
    }
    var index = 2;
    while (existingNames.contains('$baseName $index'.toLowerCase())) {
      index++;
    }
    return '$baseName $index';
  }

  /// Actions sur une scène via bottom sheet — pattern tactile (mobile/tablette).
  Future<void> _showBoardActions(SoundBoard board) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Renommer'),
                onTap: () {
                  Navigator.pop(context);
                  _renameBoard(board);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Dupliquer'),
                onTap: () {
                  Navigator.pop(context);
                  _duplicateBoard(board);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.error),
                title: Text('Supprimer', style: TextStyle(color: scheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteBoard(board);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Actions sur une scène via menu contextuel — clic droit sur le titre (desktop).
  Future<void> _showBoardContextMenu(
    SoundBoard board,
    Offset globalPosition,
  ) async {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    final screenSize = MediaQuery.sizeOf(context);
    final position = RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      screenSize.width - globalPosition.dx,
      screenSize.height - globalPosition.dy,
    );

    final value = await showMenu<String>(
      context: context,
      position: position,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      items: [
        PopupMenuItem(
          value: 'rename',
          height: AppMenu.itemHeight,
          padding: AppMenu.itemPadding,
          child: Row(
            children: [
              Icon(Icons.edit_rounded, size: 18, color: scheme.onSurface),
              const SizedBox(width: AppSpacing.sm),
              const Text('Renommer'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'duplicate',
          height: AppMenu.itemHeight,
          padding: AppMenu.itemPadding,
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 18, color: scheme.onSurface),
              const SizedBox(width: AppSpacing.sm),
              const Text('Dupliquer'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          height: AppMenu.itemHeight,
          padding: AppMenu.itemPadding,
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: scheme.error),
              const SizedBox(width: AppSpacing.sm),
              Text('Supprimer', style: TextStyle(color: scheme.error)),
            ],
          ),
        ),
      ],
    );

    if (!mounted) return;
    if (value == 'rename') {
      await _renameBoard(board);
    } else if (value == 'duplicate') {
      await _duplicateBoard(board);
    } else if (value == 'delete') {
      await _deleteBoard(board);
    }
  }

  Future<void> _renameBoard(SoundBoard board) async {
    final name = await AppTextInputDialog.show(
      context,
      title: 'Renommer la scène',
      confirmLabel: 'Renommer',
      initialValue: board.name,
      hint: board.name,
      icon: Icons.text_fields_rounded,
    );

    final trimmedName = name?.trim();
    if (trimmedName == null ||
        trimmedName.isEmpty ||
        trimmedName == board.name) {
      return;
    }

    final ok = await _notifier.renameBoard(board, trimmedName);
    if (!mounted) return;
    if (!ok) {
      showCopyableSnackBar(context, 'Erreur lors du renommage de la scène');
    }
  }

  Future<void> _duplicateBoard(SoundBoard board) async {
    final suggestedName = _buildSuggestedDuplicateBoardName(
      board.name,
      _notifier.state.boards,
    );
    final name = await AppTextInputDialog.show(
      context,
      title: 'Dupliquer la scène',
      confirmLabel: 'Dupliquer',
      initialValue: suggestedName,
      hint: suggestedName,
      icon: Icons.copy_rounded,
    );

    final trimmedName = name?.trim();
    if (trimmedName == null || trimmedName.isEmpty) return;

    final duplicated = await _notifier.duplicateBoard(board, trimmedName);
    if (!mounted) return;
    if (duplicated == null) {
      showCopyableSnackBar(
        context,
        'Erreur lors de la duplication de la scène',
      );
    }
  }

  Future<void> _deleteBoard(SoundBoard board) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Supprimer la scène',
      message: 'Supprimer "${board.name}" ? Cette action est irréversible.',
      confirmLabel: 'Supprimer',
      isDestructive: true,
    );

    if (!confirmed) return;

    final ok = await _notifier.deleteBoard(board);
    if (!mounted) return;
    if (!ok) {
      showCopyableSnackBar(
        context,
        'Erreur lors de la suppression de la scène',
      );
    }
  }
}
