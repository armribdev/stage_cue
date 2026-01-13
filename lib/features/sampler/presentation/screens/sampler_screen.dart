import 'package:flutter/material.dart';
import '../providers/sampler_provider.dart';
import '../widgets/pad_button.dart';
import '../../data/repositories/sound_repository.dart';
import '../../data/datasources/local_sound_datasource.dart';
import '../../domain/usecases/load_sounds_usecase.dart';
import '../../../../core/database/database.dart';
import 'settings_screen.dart';
import 'sound_details_screen.dart';

/// Écran principal du sampler
class SamplerScreen extends StatefulWidget {
  const SamplerScreen({super.key});

  @override
  State<SamplerScreen> createState() => _SamplerScreenState();
}

class _SamplerScreenState extends State<SamplerScreen> {
  late final SamplerNotifier _notifier;
  late final AppDatabase _database;

  @override
  void initState() {
    super.initState();
    _database = AppDatabase();
    _initializeNotifier();
    _notifier.loadSounds();
  }

  void _initializeNotifier() {
    // Initialiser les dépendances
    final soundDataSource = LocalSoundDataSource(_database);
    final watchedPathDataSource = LocalWatchedPathDataSource(_database);
    final repository = SoundRepository(soundDataSource, watchedPathDataSource);
    
    final loadSoundsUseCase = LoadSoundsUseCase(repository);
    
    _notifier = SamplerNotifier(loadSoundsUseCase);
    
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

  Future<void> _addDirectoryOrFile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(database: _database),
      ),
    );
    // Recharger les sons après retour des paramètres
    _notifier.loadSounds();
  }

  @override
  Widget build(BuildContext context) {
    final state = _notifier.state;

    return Scaffold(
      appBar: AppBar(
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
      body: state.isLoading
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
                            'Aucun fichier audio indexé',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ajoutez un dossier ou fichier dans les paramètres',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
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
                      itemCount: state.sounds.length,
                      itemBuilder: (context, index) {
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDirectoryOrFile,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
        tooltip: 'Ajouter un dossier ou fichier',
      ),
    );
  }
}

