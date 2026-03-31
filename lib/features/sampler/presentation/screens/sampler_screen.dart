import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import '../providers/sampler_provider.dart';
import '../widgets/pad_item.dart';
import '../../domain/entities/sound_board.dart';
import '../../../../core/app/app_services.dart';
import '../../../../core/database/database.dart' as db;
import 'settings_screen.dart';
import 'sound_details_screen.dart';
import 'sound_library_screen.dart';

/// Marqueur pour le bouton d'ajout dans la grille
const _addButtonMarker = _AddButtonMarker();

class _AddButtonMarker {
  const _AddButtonMarker();
}

class _UndoPadIntent extends Intent {
  const _UndoPadIntent();
}

/// Écran principal du sampler
class SamplerScreen extends StatefulWidget {
  final AppServices services;

  const SamplerScreen({super.key, required this.services});

  @override
  State<SamplerScreen> createState() => _SamplerScreenState();
}

class _SamplerScreenState extends State<SamplerScreen> {
  late final SamplerNotifier _notifier;
  late final db.AppDatabase _database;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _gridScrollController = ScrollController();
  bool _isEditMode = false;
  int? _recentlyRestoredSoundId;
  bool get _isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    _database = widget.services.database;
    _initializeNotifier();
    _notifier.loadBoards();
  }

  void _initializeNotifier() {
    // Initialiser les dépendances
    _notifier = SamplerNotifier(
      widget.services.soundRepository,
      widget.services.loadSoundsUseCase,
      widget.services.removeSoundFromBoardUseCase,
    );

    _notifier.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _selectBoard(SoundBoard board) async {
    Navigator.pop(context);
    await _notifier.selectBoard(board);
  }

  Future<void> _createBoard() async {
    final scaffoldState = _scaffoldKey.currentState;
    if (scaffoldState?.isDrawerOpen ?? false) {
      Navigator.of(
        context,
      ).pop(); // Ferme le drawer avant d'ouvrir la boîte de dialogue
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (!mounted) {
      return;
    }

    final name = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const _CreateSoundBoardScreen()),
    );

    final trimmedName = name?.trim();
    if (trimmedName == null || trimmedName.isEmpty) {
      return;
    }

    final newBoard = await _notifier.createBoard(trimmedName);
    if (!mounted) {
      return;
    }
    if (newBoard != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Scène "${newBoard.name}" créée')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de la création de la scène')),
      );
    }
  }

  Future<void> _showBoardActions(SoundBoard board) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
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
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Supprimer'),
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

  Future<void> _renameBoard(SoundBoard board) async {
    final name = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => _RenameSoundBoardScreen(initialName: board.name),
      ),
    );

    final trimmedName = name?.trim();
    if (trimmedName == null ||
        trimmedName.isEmpty ||
        trimmedName == board.name) {
      return;
    }

    final ok = await _notifier.renameBoard(board, trimmedName);
    if (!mounted) {
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors du renommage de la scène')),
      );
    }
  }

  Future<void> _deleteBoard(SoundBoard board) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Supprimer la scène'),
          content: Text(
            'Supprimer "${board.name}" ? Cette action est irréversible.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final ok = await _notifier.deleteBoard(board);
    if (!mounted) {
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erreur lors de la suppression de la scène'),
        ),
      );
    }
  }

  Future<void> _handleUndoShortcut() async {
    if (!_isDesktopPlatform || !mounted) {
      return;
    }
    final restoredSoundId = await _notifier.undoLastRemoval();
    if (!mounted || restoredSoundId == null) {
      return;
    }
    setState(() {
      _recentlyRestoredSoundId = restoredSoundId;
    });
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 650), () {
        if (!mounted || _recentlyRestoredSoundId != restoredSoundId) {
          return;
        }
        setState(() {
          _recentlyRestoredSoundId = null;
        });
      }),
    );
  }

  static const double _itemWidth = 180;

  Widget _buildAddButtonCard(BuildContext context, SoundBoard selectedBoard) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('add_button'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: scheme.primary.withValues(alpha: 0.45),
          style: BorderStyle.solid,
          width: 1.4,
        ),
      ),
      color: scheme.primaryContainer.withValues(alpha: 0.15),
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SoundLibraryScreen(
                database: _database,
                boardId: selectedBoard.id,
              ),
            ),
          );
          await _notifier.loadSounds();
        },
        borderRadius: BorderRadius.circular(14),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 42, color: scheme.primary),
              const SizedBox(height: 10),
              Text(
                'Ajouter un son',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPadsGrid(
    BuildContext context,
    SamplerState state,
    SoundBoard selectedBoard,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        int crossAxisCount = (screenWidth / _itemWidth).floor();
        crossAxisCount = max(2, crossAxisCount);
        final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 1.4,
        );

        if (_isEditMode) {
          return ReorderableGridView.builder(
            key: const ValueKey('pads_reorder_grid'),
            controller: _gridScrollController,
            padding: const EdgeInsets.all(16),
            gridDelegate: gridDelegate,
            itemCount: state.sounds.length,
            dragEnabled: true,
            // Desktop (souris) a besoin d'un démarrage immédiat pour un drag fiable.
            dragStartDelay: Duration.zero,
            dragWidgetBuilder: (index, child) {
              return Material(
                type: MaterialType.transparency,
                child: Opacity(opacity: 0.95, child: child),
              );
            },
            onDragStart: (index) {
              HapticFeedback.selectionClick();
            },
            onReorder: (oldIndex, newIndex) {
              if (oldIndex == newIndex) {
                return;
              }
              final reordered = List<SoundItem>.from(state.sounds);
              final moved = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, moved);
              _notifier.reorderSoundsFromList(reordered);
            },
            itemBuilder: (context, index) {
              final soundItem = state.sounds[index];
              return _buildPadCard(context, state, soundItem);
            },
          );
        }

        final gridItems = <Object>[...state.sounds, _addButtonMarker];
        return GridView.builder(
          controller: _gridScrollController,
          padding: const EdgeInsets.all(16),
          gridDelegate: gridDelegate,
          itemCount: gridItems.length,
          itemBuilder: (context, index) {
            final item = gridItems[index];
            if (item == _addButtonMarker) {
              return _buildAddButtonCard(context, selectedBoard);
            }
            return _buildPadCard(context, state, item as SoundItem);
          },
        );
      },
    );
  }

  Widget _buildPadCard(
    BuildContext context,
    SamplerState state,
    SoundItem soundItem,
  ) {
    return PadItem(
      key: ValueKey<int>(soundItem.sound.id),
      soundItem: soundItem,
      isEditMode: _isEditMode,
      animateOnRestore: _recentlyRestoredSoundId == soundItem.sound.id,
      onTap: _isEditMode ? null : () => _notifier.toggleSound(soundItem),
      onLongPress: _isEditMode
          ? null
          : () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SoundDetailScreen(
                    soundItem: soundItem,
                    notifier: _notifier,
                  ),
                ),
              );
            },
      onRemove: _isEditMode
          ? () async {
              final removed = await _notifier.removeSound(soundItem);
              if (!mounted || !removed) {
                return;
              }
            }
          : null,
    );
  }

  @override
  void dispose() {
    _gridScrollController.dispose();
    _notifier.removeListener(_onStateChanged);
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _notifier.state;
    final selectedBoard = state.selectedBoard;
    final boards = state.boards;
    final isBoardsLoading = state.isBoardsLoading;
    final masterVolume = _notifier.masterVolume;

    return Shortcuts(
      shortcuts: _isDesktopPlatform
          ? const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                  _UndoPadIntent(),
            }
          : const <ShortcutActivator, Intent>{},
      child: Actions(
        actions: <Type, Action<Intent>>{
          _UndoPadIntent: CallbackAction<_UndoPadIntent>(
            onInvoke: (intent) {
              unawaited(_handleUndoShortcut());
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            key: _scaffoldKey,
            appBar: _SamplerAppBar(
              title: selectedBoard == null ? 'Scène' : selectedBoard.name,
              isEditMode: _isEditMode,
              canToggleEditMode: state.sounds.isNotEmpty,
              onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
              onToggleEditMode: () {
                setState(() {
                  _isEditMode = !_isEditMode;
                });
              },
            ),
            drawer: _BoardsDrawer(
              boards: boards,
              selectedBoard: selectedBoard,
              isBoardsLoading: isBoardsLoading,
              onCreateBoard: _createBoard,
              onSelectBoard: _selectBoard,
              onBoardLongPress: _showBoardActions,
              onOpenLibrary: selectedBoard == null
                  ? null
                  : () async {
                      Navigator.pop(context);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SoundLibraryScreen(
                            database: _database,
                            boardId: selectedBoard.id,
                          ),
                        ),
                      );
                      await _notifier.loadSounds();
                    },
              onOpenSettings: () async {
                Navigator.pop(context);
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SettingsScreen(database: _database),
                  ),
                );
                await _notifier.loadSounds();
              },
            ),
            body: SafeArea(
              child: selectedBoard == null
                  ? Center(
                      child: isBoardsLoading
                          ? const CircularProgressIndicator()
                          : const Text('Aucune scène disponible'),
                    )
                  : state.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : state.error != null
                  ? Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                size: 48,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Erreur: ${state.error}',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : state.sounds.isEmpty
                  ? Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.graphic_eq_rounded,
                                size: 48,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Aucun son dans la scène',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Ajoutez des sons depuis la bibliothèque',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => SoundLibraryScreen(
                                        database: _database,
                                        boardId: selectedBoard.id,
                                      ),
                                    ),
                                  );
                                  await _notifier.loadSounds();
                                },
                                icon: const Icon(Icons.library_music_rounded),
                                label: const Text('Ouvrir la bibliothèque'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : _buildPadsGrid(context, state, selectedBoard),
            ),
            bottomNavigationBar: _MasterVolumeBar(
              masterVolume: masterVolume,
              onChanged: (value) => _notifier.setMasterVolume(value),
            ),
          ),
        ),
      ),
    );
  }
}

class _SamplerAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool isEditMode;
  final bool canToggleEditMode;
  final VoidCallback onOpenMenu;
  final VoidCallback onToggleEditMode;

  const _SamplerAppBar({
    required this.title,
    required this.isEditMode,
    required this.canToggleEditMode,
    required this.onOpenMenu,
    required this.onToggleEditMode,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.menu_rounded),
        tooltip: 'Menu',
        onPressed: onOpenMenu,
      ),
      title: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
          height: 1,
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            isEditMode ? Icons.done_rounded : Icons.grid_view_rounded,
            color: isEditMode ? scheme.primary : null,
          ),
          tooltip: isEditMode ? 'Terminer l’édition' : 'Modifier la grille',
          onPressed: canToggleEditMode ? onToggleEditMode : null,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _BoardsDrawer extends StatelessWidget {
  final List<SoundBoard> boards;
  final SoundBoard? selectedBoard;
  final bool isBoardsLoading;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function(SoundBoard board) onSelectBoard;
  final Future<void> Function(SoundBoard board) onBoardLongPress;
  final Future<void> Function()? onOpenLibrary;
  final Future<void> Function() onOpenSettings;

  const _BoardsDrawer({
    required this.boards,
    required this.selectedBoard,
    required this.isBoardsLoading,
    required this.onCreateBoard,
    required this.onSelectBoard,
    required this.onBoardLongPress,
    required this.onOpenLibrary,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.theater_comedy_rounded, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Scènes',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
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
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (boards.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Aucune scène',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    )
                  else
                    ...boards.map((board) {
                      return ListTile(
                        title: Text(board.name),
                        selected: selectedBoard?.id == board.id,
                        onLongPress: () => onBoardLongPress(board),
                        onTap: () => onSelectBoard(board),
                      );
                    }),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Nouvelle scène'),
                    onTap: () => onCreateBoard(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.library_music),
              title: const Text('Bibliothèque des sons'),
              onTap: onOpenLibrary == null
                  ? null
                  : () async {
                      await onOpenLibrary!();
                    },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Paramètres'),
              onTap: () async {
                await onOpenSettings();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MasterVolumeBar extends StatelessWidget {
  final double masterVolume;
  final ValueChanged<double> onChanged;

  const _MasterVolumeBar({required this.masterVolume, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.volume_up, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Slider(
                  value: masterVolume,
                  min: 0.0,
                  max: 1.0,
                  label: '${(masterVolume * 100).round()}%',
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(masterVolume * 100).round()}%',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateSoundBoardScreen extends StatefulWidget {
  const _CreateSoundBoardScreen();

  @override
  State<_CreateSoundBoardScreen> createState() =>
      _CreateSoundBoardScreenState();
}

class _RenameSoundBoardScreen extends StatefulWidget {
  final String initialName;

  const _RenameSoundBoardScreen({required this.initialName});

  @override
  State<_RenameSoundBoardScreen> createState() =>
      _RenameSoundBoardScreenState();
}

class _RenameSoundBoardScreenState extends State<_RenameSoundBoardScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Renommer la scène')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'Nom de la scène',
                prefixIcon: Icon(
                  Icons.text_fields_rounded,
                  color: scheme.primary.withValues(alpha: 0.9),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _controller.text),
                    child: const Text('Renommer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateSoundBoardScreenState extends State<_CreateSoundBoardScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle scène')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'Nom de la scène',
                prefixIcon: Icon(
                  Icons.auto_awesome_rounded,
                  color: scheme.primary.withValues(alpha: 0.9),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _controller.text),
                    child: const Text('Créer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
