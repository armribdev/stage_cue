import 'package:flutter/material.dart';
import '../providers/sampler_provider.dart';
import '../widgets/pad_button.dart';
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/sound_board.dart';
import '../../domain/usecases/load_sounds_usecase.dart';
import '../../domain/usecases/remove_sound_from_board_usecase.dart';
import '../../../../core/database/database.dart' as db;
import 'settings_screen.dart';
import 'sound_details_screen.dart';
import 'sound_library_screen.dart';

/// Écran principal du sampler
class SamplerScreen extends StatefulWidget {
  const SamplerScreen({super.key});

  @override
  State<SamplerScreen> createState() => _SamplerScreenState();
}

class _SamplerScreenState extends State<SamplerScreen> {
  late final SoundRepository _repository;
  late final SamplerNotifier _notifier;
  late final db.AppDatabase _database;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<SoundBoard> _boards = [];
  SoundBoard? _selectedBoard;
  bool _isBoardsLoading = true;

  @override
  void initState() {
    super.initState();
    _database = db.AppDatabase();
    _initializeNotifier();
    _loadBoards();
  }

  void _initializeNotifier() {
    // Initialiser les dépendances
    _repository = SoundRepository.fromDatabase(_database);
    
    final loadSoundsUseCase = LoadSoundsUseCase(_repository);
    final removeSoundFromBoardUseCase = RemoveSoundFromBoardUseCase(_repository);
    
    _notifier = SamplerNotifier(loadSoundsUseCase, removeSoundFromBoardUseCase);
    
    _notifier.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadBoards({int? selectBoardId}) async {
    if (mounted) {
      setState(() {
        _isBoardsLoading = true;
      });
    }

    try {
      var boards = await _repository.getSoundBoards();
      if (boards.isEmpty) {
        final newBoardId = await _repository.createSoundBoard('Board 1');
        boards = await _repository.getSoundBoards();
        selectBoardId = newBoardId;
      }

      final targetId = selectBoardId ?? _selectedBoard?.id ?? boards.first.id;
      final selected = boards.firstWhere(
        (board) => board.id == targetId,
        orElse: () => boards.first,
      );

      if (mounted) {
        setState(() {
          _boards = boards;
          _selectedBoard = selected;
          _isBoardsLoading = false;
        });
      }

      _notifier.setActiveBoard(selected.id);
      await _notifier.loadSounds();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isBoardsLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du chargement des soundboards: $e')),
        );
      }
    }
  }

  Future<void> _selectBoard(SoundBoard board) async {
    Navigator.pop(context);
    setState(() {
      _selectedBoard = board;
    });
    _notifier.setActiveBoard(board.id);
    await _notifier.loadSounds();
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

    try {
      final newBoardId = await _repository.createSoundBoard(trimmedName);
      if (!mounted) {
        return;
      }
      final newBoard = SoundBoard(
        id: newBoardId,
        name: trimmedName,
        createdAt: DateTime.now(),
      );
      setState(() {
        _boards = [..._boards, newBoard];
        _selectedBoard = newBoard;
        _isBoardsLoading = false;
      });
      _notifier.setActiveBoard(newBoardId);
      _notifier.loadSounds();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Soundboard "${newBoard.name}" créée')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la création: $e')),
        );
      }
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

    try {
      await _repository.renameSoundBoard(board.id, trimmedName);
      if (!mounted) {
        return;
      }
      setState(() {
        _boards = _boards
            .map((b) => b.id == board.id
                ? SoundBoard(id: b.id, name: trimmedName, createdAt: b.createdAt)
                : b)
            .toList();
        if (_selectedBoard?.id == board.id) {
          _selectedBoard =
              SoundBoard(id: board.id, name: trimmedName, createdAt: board.createdAt);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du renommage: $e')),
        );
      }
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

    try {
      await _repository.deleteSoundBoard(board.id);
      if (!mounted) {
        return;
      }

      final updatedBoards = _boards.where((b) => b.id != board.id).toList();
      SoundBoard? nextSelected = _selectedBoard;
      if (_selectedBoard?.id == board.id) {
        nextSelected = updatedBoards.isNotEmpty ? updatedBoards.first : null;
      }

      setState(() {
        _boards = updatedBoards;
        _selectedBoard = nextSelected;
      });

      if (nextSelected == null) {
        _notifier.setActiveBoard(null);
        await _notifier.loadSounds();
      } else {
        _notifier.setActiveBoard(nextSelected.id);
        await _notifier.loadSounds();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la suppression: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _notifier.removeListener(_onStateChanged);
    _notifier.dispose();
    _database.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _notifier.state;
    final selectedBoard = _selectedBoard;

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
                      'Soundboards (${_boards.length})',
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
              if (_isBoardsLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_boards.isEmpty)
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
                ..._boards.map((board) {
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
                child: _isBoardsLoading
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