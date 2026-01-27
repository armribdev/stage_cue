import 'package:flutter/material.dart';
import '../providers/sampler_provider.dart';
import '../widgets/pad_button.dart';
import '../../data/repositories/sound_repository.dart';
import '../../domain/usecases/load_sounds_usecase.dart';
import '../../domain/usecases/remove_sound_from_board_usecase.dart';
import '../../../../core/database/database.dart';
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
  late final SamplerNotifier _notifier;
  late final AppDatabase _database;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _database = AppDatabase();
    _initializeNotifier();
    _notifier.loadSounds();
  }

  void _initializeNotifier() {
    // Initialiser les dépendances
    final repository = SoundRepository.fromDatabase(_database);
    
    final loadSoundsUseCase = LoadSoundsUseCase(repository);
    final removeSoundFromBoardUseCase = RemoveSoundFromBoardUseCase(repository);
    
    _notifier = SamplerNotifier(loadSoundsUseCase, removeSoundFromBoardUseCase);
    
    _notifier.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {});
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
        title: const Text('Stage Cue - Soundboard'),
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
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: state.isLoading
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
                                    builder: (context) => SoundLibraryScreen(database: _database),
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
                                  color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
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
                                      builder: (context) => SoundLibraryScreen(database: _database),
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
                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
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

