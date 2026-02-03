import 'package:flutter/material.dart';
import '../providers/sampler_provider.dart';
import '../widgets/pad_button.dart';
import '../../domain/entities/sound_board.dart';
import '../../../../core/app/app_services.dart';
import '../../../../core/database/database.dart' as db;
import 'settings_screen.dart';
import 'sound_details_screen.dart';
import 'sound_library_screen.dart';

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

  @override
  void dispose() {
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

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: 'Menu',
          onPressed: () {
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
        title: Text(
          selectedBoard == null ? 'Soundboard' : selectedBoard.name,
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Paramètres',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(database: _database),
                ),
              );
              _notifier.loadSounds();
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              ListTile(
                leading: const Icon(Icons.library_music),
                title: const Text('Bibliothèque des sons'),
                onTap: selectedBoard == null
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
                        _notifier.loadSounds();
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
                      onPressed: _createBoard,
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
                        onPressed: _createBoard,
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
                    onLongPress: () => _showBoardActions(board),
                    onTap: () => _selectBoard(board),
                  );
                }),
            ],
          ),
        ),
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
                                _notifier.loadSounds();
                              },
                              icon: const Icon(Icons.library_music),
                              label: const Text('Ouvrir la bibliothèque'),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.4,
                        ),
                        itemCount: state.sounds.length + 1, // +1 pour le bouton d'ajout
                        itemBuilder: (context, index) {
                          // Si c'est le dernier item, afficher le bouton d'ajout
                          if (index == state.sounds.length) {
                            return Card(
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
                                  // Recharger les sons après retour de la bibliothèque
                                  _notifier.loadSounds();
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

                          // Sinon, afficher le pad button normal
                          final soundItem = state.sounds[index];
                          return PadButton(
                            soundItem: soundItem,
                            onTap: () => _notifier.toggleSound(soundItem),
                            onLongPress: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SoundDetailScreen(sound: soundItem.sound),
                                ),
                              );
                            },
                            onRemove: () => _notifier.removeSound(soundItem),
                          );
                        },
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