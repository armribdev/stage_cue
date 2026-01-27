import 'package:flutter/material.dart';
import '../../../../core/database/database.dart' as db;
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/sound.dart';
import '../../domain/usecases/add_sound_to_board_usecase.dart';

/// Écran pour ajouter un bruitage à la board
/// Affiche uniquement les bruitages qui ne sont pas déjà dans la board
class SoundLibraryScreen extends StatefulWidget {
  final db.AppDatabase database;

  const SoundLibraryScreen({super.key, required this.database});

  @override
  State<SoundLibraryScreen> createState() => _SoundLibraryScreenState();
}

class _SoundLibraryScreenState extends State<SoundLibraryScreen> {
  late final SoundRepository _repository;
  late final AddSoundToBoardUseCase _addSoundToBoardUseCase;
  List<Sound> _availableSounds = [];
  Set<int> _soundsInBoard = {};
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _initializeRepository();
    _loadSounds();
  }

  void _initializeRepository() {
    _repository = SoundRepository.fromDatabase(widget.database);
    _addSoundToBoardUseCase = AddSoundToBoardUseCase(_repository);
  }

  Future<void> _loadSounds() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Charger tous les sons indexés
      final allSounds = await _repository.getAllSounds();
      
      // Charger les IDs des sons qui sont dans la board
      final boardSounds = await _repository.getBoardSounds();
      final boardSoundIds = boardSounds.map((s) => s.id).toSet();

      // Filtrer : uniquement les bruitages (y compris ceux déjà dans la board)
      final availableSounds = allSounds.where((sound) {
        return sound.type == SoundType.soundEffect;
      }).toList();

      setState(() {
        _availableSounds = availableSounds;
        _soundsInBoard = boardSoundIds;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du chargement: $e')),
        );
      }
    }
  }

  Future<void> _addSoundToBoard(Sound sound) async {
    // Ne rien faire si le son est déjà dans la board
    if (_soundsInBoard.contains(sound.id)) {
      return;
    }
    
    try {
      await _addSoundToBoardUseCase(sound.id);
      // Mettre à jour l'état local pour refléter l'ajout
      setState(() {
        _soundsInBoard.add(sound.id);
      });
      if (mounted) {
        Navigator.pop(context, true); // Retour à la board avec succès
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'ajout: $e')),
        );
      }
    }
  }

  String _getSoundTypeName(SoundType type) {
    switch (type) {
      case SoundType.soundEffect:
        return 'Bruitage';
      case SoundType.music:
        return 'Musique';
      case SoundType.ambiance:
        return 'Son d\'ambiance';
    }
  }

  List<Sound> get _filteredSounds {
    if (_searchQuery.isEmpty) {
      return _availableSounds;
    }
    final query = _searchQuery.toLowerCase();
    return _availableSounds.where((sound) {
      return sound.title.toLowerCase().contains(query) ||
          sound.filePath.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajouter un bruitage'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // Barre de recherche
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Rechercher un bruitage...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          // Liste des sons
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSounds.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.music_off,
                              size: 64,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Aucun bruitage disponible'
                                  : 'Aucun bruitage trouvé',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredSounds.length,
                        itemBuilder: (context, index) {
                          final sound = _filteredSounds[index];
                          final isInBoard = _soundsInBoard.contains(sound.id);

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: Opacity(
                              opacity: isInBoard ? 0.6 : 1.0,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer,
                                  child: Icon(
                                    Icons.music_note,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                title: Text(
                                  sound.title,
                                  style: TextStyle(
                                    fontWeight: isInBoard
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      sound.filePath,
                                      style: const TextStyle(fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Text(
                                          'Type: ${_getSoundTypeName(sound.type)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: isInBoard
                                    ? Icon(
                                        Icons.check_circle,
                                        color: Theme.of(context).colorScheme.primary,
                                      )
                                    : Icon(
                                        Icons.add_circle,
                                        color: Colors.green,
                                      ),
                                onTap: isInBoard
                                    ? null
                                    : () => _addSoundToBoard(sound),
                                
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
