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
      final allSounds = await _repository.getAllSounds();
      // Sons déjà présents dans un pad de la board (indicatif uniquement)
      final inBoard = await _repository.getSoundIdsInBoard(widget.boardId);

      final availableSounds = allSounds
          .where((s) => s.type == SoundType.soundEffect)
          .toList();

      setState(() {
        _availableSounds = availableSounds;
        _soundsInBoard = inBoard;
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
    try {
      // Crée toujours un nouveau pad (même son autorisé plusieurs fois)
      await _addSoundToBoardUseCase(widget.boardId, sound.id);
      setState(() => _soundsInBoard.add(sound.id));
      if (mounted) {
        Navigator.pop(context, true);
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
      label: Text(tag.name, style: const TextStyle(fontSize: 11)),
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
    final matchInTitle = normalizeForSearch(
      sound.title,
    ).contains(normalizedToken);
    final matchInDisplayName =
        sound.displayName != null &&
        normalizeForSearch(sound.displayName!).contains(normalizedToken);
    final matchInPath = normalizeForSearch(
      sound.filePath,
    ).contains(normalizedToken);
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajouter un bruitage')),
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _isLoading
                  ? const _LibraryLoadingList(key: ValueKey('loading'))
                  : _filteredSounds.isEmpty
                  ? Center(
                      key: const ValueKey('empty'),
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
                      key: const ValueKey('list'),
                      itemCount: _filteredSounds.length,
                      itemBuilder: (context, index) {
                        final sound = _filteredSounds[index];
                        final isInBoard = _soundsInBoard.contains(sound.id);
                        final tags = _soundTags[sound.id] ?? [];

                        return TweenAnimationBuilder<double>(
                          duration: Duration(milliseconds: 160 + (index * 22)),
                          curve: Curves.easeOutCubic,
                          tween: Tween(begin: 0, end: 1),
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, (1 - value) * 10),
                                child: child,
                              ),
                            );
                          },
                          child: Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: Opacity(
                              opacity: isInBoard ? 0.6 : 1.0,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: scheme.primaryContainer,
                                  child: Icon(
                                    Icons.music_note,
                                    color: scheme.primary,
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
                                          for (final tag in tags)
                                            _buildTagChip(tag),
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
                                        color: scheme.primary,
                                      )
                                    : Icon(
                                        Icons.add_circle,
                                        color: Colors.green.shade400,
                                      ),
                                onTap: isInBoard
                                    ? null
                                    : () => _addSoundToBoard(sound),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryLoadingList extends StatelessWidget {
  const _LibraryLoadingList({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 6,
      itemBuilder: (context, index) {
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: _SkeletonCard(),
        );
      },
    );
  }
}

class _SkeletonCard extends StatefulWidget {
  const _SkeletonCard();

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textScaler = MediaQuery.textScalerOf(context);
    final titleHeight = textScaler.scale(12).clamp(12, 20).toDouble();
    final subtitleHeight = textScaler.scale(10).clamp(10, 18).toDouble();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final alpha = 0.14 + (_controller.value * 0.1);
        return Card(
          child: ListTile(
            isThreeLine: true,
            leading: CircleAvatar(
              backgroundColor: scheme.onSurface.withValues(alpha: alpha),
            ),
            title: Container(
              height: titleHeight,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: alpha),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Container(
                  height: subtitleHeight,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: alpha * 0.9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 6),
                FractionallySizedBox(
                  widthFactor: 0.45,
                  child: Container(
                    height: subtitleHeight,
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: alpha * 0.75),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
            trailing: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: alpha * 0.8),
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}
