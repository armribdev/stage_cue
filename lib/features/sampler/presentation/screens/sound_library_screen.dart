import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/database/database.dart' as db;
import '../../../../core/utils/string_utils.dart';
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';
import '../../domain/usecases/add_sound_to_board_usecase.dart';

/// Écran pour ajouter un bruitage à la board
/// Affiche uniquement les bruitages qui ne sont pas déjà dans la board
class SoundLibraryScreen extends StatefulWidget {
  final db.AppDatabase database;
  final int boardId;

  const SoundLibraryScreen({
    super.key,
    required this.database,
    required this.boardId,
  });

  @override
  State<SoundLibraryScreen> createState() => _SoundLibraryScreenState();
}

class _SoundLibraryScreenState extends State<SoundLibraryScreen> {
  late final SoundRepository _repository;
  late final AddSoundToBoardUseCase _addSoundToBoardUseCase;
  List<Sound> _availableSounds = [];
  Set<int> _soundsInBoard = {};
  /// IDs des sons correspondant à la recherche (AND entre tokens, tag ou titre par token).
  /// null = pas de filtre (requête vide ou tokens vides).
  Set<int>? _searchMatchedSoundIds;
  final Map<int, List<TagItem>> _soundTags = {};
  List<TagCategoryWithTags> _tagCatalog = [];
  bool _isLoading = true;
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _initializeRepository();
    _loadTagCatalog();
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
      final boardSounds = await _repository.getBoardSounds(widget.boardId);
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
      await _loadTagsForSounds(availableSounds);
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
      await _addSoundToBoardUseCase(widget.boardId, sound.id);
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

  Future<void> _loadTagsForSounds(List<Sound> sounds) async {
    if (sounds.isEmpty) {
      setState(() {
        _soundTags.clear();
      });
      return;
    }
    final entries = await Future.wait(
      sounds.map((sound) async {
        final tags = await _repository.getTagsForSound(sound.id);
        return MapEntry(sound.id, tags);
      }),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _soundTags
        ..clear()
        ..addEntries(entries);
    });
  }

  Future<void> _loadTagCatalog() async {
    final catalog = await _repository.getTagCatalog();
    if (!mounted) {
      return;
    }
    setState(() {
      _tagCatalog = catalog;
    });
  }

  Color? _getCategoryColor(int categoryId) {
    for (final category in _tagCatalog) {
      if (category.category.id == categoryId) {
        return Color(category.category.color);
      }
    }
    return null;
  }

  Widget _buildTagChip(TagItem tag) {
    final color = _getCategoryColor(tag.categoryId);
    return Chip(
      label: Text(
        tag.name,
        style: const TextStyle(fontSize: 11),
      ),
      visualDensity: VisualDensity.compact,
      backgroundColor: color?.withAlpha(24),
      side: color == null ? null : BorderSide(color: color),
    );
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

  /// Extrait les tokens de recherche (séparateurs: espaces, virgules).
  /// Exclut les chaînes vides et les tokens de moins de 2 caractères.
  List<String> _parseSearchTokens(String query) {
    return query
        .split(RegExp(r'[\s,]+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty && t.length >= 2)
        .toList();
  }

  /// Vérifie si un son correspond à un token (tag/alias ou titre/displayName/filePath).
  bool _soundMatchesToken(Sound sound, String token) {
    final normalizedToken = normalizeForSearch(token);
    final matchInTitle = normalizeForSearch(sound.title).contains(normalizedToken);
    final matchInDisplayName = sound.displayName != null &&
        normalizeForSearch(sound.displayName!).contains(normalizedToken);
    final matchInPath = normalizeForSearch(sound.filePath).contains(normalizedToken);
    return matchInTitle || matchInDisplayName || matchInPath;
  }

  List<Sound> get _filteredSounds {
    if (_searchQuery.trim().isEmpty) {
      return _availableSounds;
    }
    if (_searchMatchedSoundIds == null) {
      return _availableSounds;
    }
    return _availableSounds
        .where((s) => _searchMatchedSoundIds!.contains(s.id))
        .toList();
  }

  void _scheduleSearch(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchMatchedSoundIds = null;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      final tokens = _parseSearchTokens(query);
      if (tokens.isEmpty) {
        if (!mounted) return;
        setState(() {
          _searchMatchedSoundIds = null;
        });
        return;
      }

      Set<int>? intersection;
      for (final token in tokens) {
        final tagIds = await _repository.findSoundIdsByTagQuery(token);
        final titleIds = _availableSounds
            .where((s) => _soundMatchesToken(s, token))
            .map((s) => s.id)
            .toSet();
        final tokenMatchIds = tagIds.union(titleIds);

        if (intersection == null) {
          intersection = tokenMatchIds;
        } else {
          intersection = intersection.intersection(tokenMatchIds);
        }
      }

      if (!mounted) return;
      setState(() {
        _searchMatchedSoundIds = intersection ?? {};
      });
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
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
                _scheduleSearch(value);
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
                          final tags = _soundTags[sound.id] ?? [];

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
                                    if (tags.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: -6,
                                        children: [
                                          for (final tag in tags) _buildTagChip(tag),
                                        ],
                                      ),
                                    ],
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
