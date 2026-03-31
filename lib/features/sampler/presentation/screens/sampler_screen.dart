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

  const SamplerScreen({
    super.key,
    required this.services,
  });

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
      Navigator.of(context).pop(); // Ferme le drawer avant d'ouvrir la boîte de dialogue
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (!mounted) {
      return;
    }

    final name = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const _CreateSoundBoardScreen(),
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Soundboard "${newBoard.name}" créée')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de la création de la soundboard')),
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
    if (trimmedName == null || trimmedName.isEmpty || trimmedName == board.name) {
      return;
    }

    final ok = await _notifier.renameBoard(board, trimmedName);
    if (!mounted) {
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors du renommage de la soundboard')),
      );
    }
  }

  Future<void> _deleteBoard(SoundBoard board) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Supprimer la soundboard'),
          content: Text('Supprimer "${board.name}" ? Cette action est irréversible.'),
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
        const SnackBar(content: Text('Erreur lors de la suppression de la soundboard')),
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
    return Card(
      key: const ValueKey('add_button'),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
          style: BorderStyle.solid,
          width: 2,
        ),
      ),
      color: Theme.of(context).colorScheme.surface,
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
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Icon(
            Icons.add,
            size: 48,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
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
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.4,
        );

        if (_isEditMode) {
          return ReorderableGridView.builder(
            key: const ValueKey('pads_reorder_grid'),
            controller: _gridScrollController,
            padding: const EdgeInsets.all(12),
            gridDelegate: gridDelegate,
            itemCount: state.sounds.length,
            dragEnabled: true,
            // Desktop (souris) a besoin d'un démarrage immédiat pour un drag fiable.
            dragStartDelay: Duration.zero,
            dragWidgetBuilder: (index, child) {
              return Material(
                type: MaterialType.transparency,
                child: Opacity(
                  opacity: 0.95,
                  child: child,
                ),
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
          padding: const EdgeInsets.all(12),
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
              SingleActivator(LogicalKeyboardKey.keyZ, control: true): _UndoPadIntent(),
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
        title: selectedBoard == null ? 'Soundboard' : selectedBoard.name,
        isEditMode: _isEditMode,
        canToggleEditMode: state.sounds.isNotEmpty,
        onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
        onToggleEditMode: () {
          setState(() {
            _isEditMode = !_isEditMode;
          });
        },
        onOpenSettings: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SettingsScreen(database: _database),
            ),
          );
          await _notifier.loadSounds();
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
      ),
            body: SafeArea(
        child: selectedBoard == null
            ? Center(
                child: isBoardsLoading
                    ? const CircularProgressIndicator()
                    : const Text('Aucune soundboard disponible'),
              )
            : state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : state.error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red[600],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Erreur: ${state.error}',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.red[600],
                          ),
                        ),
                      ],
                    ),
                  )
                : state.sounds.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.music_note,
                              size: 64,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Aucun son dans la board',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Ajoutez des sons depuis la bibliothèque',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                            const SizedBox(height: 24),
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
                              icon: const Icon(Icons.library_music),
                              label: const Text('Ouvrir la bibliothèque'),
                            ),
                          ],
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
  final VoidCallback onOpenSettings;

  const _SamplerAppBar({
    required this.title,
    required this.isEditMode,
    required this.canToggleEditMode,
    required this.onOpenMenu,
    required this.onToggleEditMode,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.menu),
        tooltip: 'Menu',
        onPressed: onOpenMenu,
      ),
      title: Text(title),
      backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      actions: [
        IconButton(
          icon: Icon(
            isEditMode ? Icons.check : Icons.edit,
            color: isEditMode ? Theme.of(context).colorScheme.primary : null,
          ),
          tooltip: isEditMode ? 'Terminer l’édition' : 'Modifier la grille',
          onPressed: canToggleEditMode ? onToggleEditMode : null,
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Paramètres',
          onPressed: onOpenSettings,
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

  const _BoardsDrawer({
    required this.boards,
    required this.selectedBoard,
    required this.isBoardsLoading,
    required this.onCreateBoard,
    required this.onSelectBoard,
    required this.onBoardLongPress,
    required this.onOpenLibrary,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            ListTile(
              leading: const Icon(Icons.library_music),
              title: const Text('Bibliothèque des sons'),
              onTap: onOpenLibrary == null
                  ? null
                  : () async {
                      await onOpenLibrary!();
                    },
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Soundboards (${boards.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Créer une soundboard',
                    onPressed: () => onCreateBoard(),
                  ),
                ],
              ),
            ),
            if (isBoardsLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (boards.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(
                      Icons.library_music_outlined,
                      size: 36,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Aucune soundboard',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => onCreateBoard(),
                      icon: const Icon(Icons.add),
                      label: const Text('Créer une soundboard'),
                    ),
                  ],
                ),
              )
            else
              ...boards.map((board) {
                return ListTile(
                  leading: const Icon(Icons.grid_view),
                  title: Text(board.name),
                  selected: selectedBoard?.id == board.id,
                  onLongPress: () => onBoardLongPress(board),
                  onTap: () => onSelectBoard(board),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _MasterVolumeBar extends StatelessWidget {
  final double masterVolume;
  final ValueChanged<double> onChanged;

  const _MasterVolumeBar({
    required this.masterVolume,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.volume_up,
                color: Theme.of(context).colorScheme.primary,
              ),
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
              Text('${(masterVolume * 100).round()}%'),
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
  State<_CreateSoundBoardScreen> createState() => _CreateSoundBoardScreenState();
}

class _RenameSoundBoardScreen extends StatefulWidget {
  final String initialName;

  const _RenameSoundBoardScreen({required this.initialName});

  @override
  State<_RenameSoundBoardScreen> createState() => _RenameSoundBoardScreenState();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Renommer la soundboard'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Nom de la soundboard',
                border: OutlineInputBorder(),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouvelle soundboard'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Nom de la soundboard',
                border: OutlineInputBorder(),
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