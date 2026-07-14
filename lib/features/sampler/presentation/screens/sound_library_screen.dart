import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/database/database.dart' as db;
import '../../../../core/theme/skeleton.dart';
import '../../../../core/utils/copyable_snackbar.dart';
import '../../../../core/utils/layout_utils.dart';
import '../../../../core/utils/sound_display_paths.dart';
import '../../../../core/utils/string_utils.dart';
import '../../data/datasources/local_library_datasource.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/library.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';
import '../../domain/usecases/add_sound_to_board_usecase.dart';
import '../utils/sound_type_ui.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/sound_picker_actions.dart';

/// Résultat renvoyé à la fermeture de [SoundLibraryScreen].
class SoundLibraryScreenResult {
  final int highlightPadId;
  final bool wasAdded;

  const SoundLibraryScreenResult({
    required this.highlightPadId,
    required this.wasAdded,
  });
}

/// Longueur minimale de la recherche pour ne pas reléguer les sons déjà en board.
const int kMinPreciseSoundLibrarySearchLength = 5;


/// Écran pour ajouter un son à la board.
class SoundLibraryScreen extends StatefulWidget {
  final db.AppDatabase database;
  final int boardId;
  final LibraryRepository? libraryRepository;
  final bool isModal;

  const SoundLibraryScreen({
    super.key,
    required this.database,
    required this.boardId,
    this.libraryRepository,
    this.isModal = false,
  });

  /// Page plein écran sur téléphone, tiroir du bas sur tablette et desktop.
  static Future<SoundLibraryScreenResult?> open(
    BuildContext context, {
    required db.AppDatabase database,
    required int boardId,
    LibraryRepository? libraryRepository,
  }) {
    final isModal = preferModalPresentation(context);
    final screen = SoundLibraryScreen(
      database: database,
      boardId: boardId,
      libraryRepository: libraryRepository,
      isModal: isModal,
    );

    if (isModal) {
      return showAppBottomSheet<SoundLibraryScreenResult>(
        context: context,
        child: screen,
      );
    }

    return Navigator.of(context).push<SoundLibraryScreenResult>(
      MaterialPageRoute(builder: (context) => screen),
    );
  }

  @override
  State<SoundLibraryScreen> createState() => _SoundLibraryScreenState();
}

class _SoundLibraryScreenState extends State<SoundLibraryScreen> {
  late final SoundRepository _repository;
  late final AddSoundToBoardUseCase _addSoundToBoardUseCase;
  List<Sound> _availableSounds = [];
  Set<int> _soundsInBoard = {};
  Map<int, int> _soundIdToPadId = {};
  /// IDs des sons correspondant à la recherche (AND entre tokens, tag ou titre par token).
  /// null = pas de filtre (requête vide ou tokens vides).
  Set<int>? _searchMatchedSoundIds;
  final Map<int, List<TagItem>> _soundTags = {};
  List<TagCategoryWithTags> _tagCatalog = [];
  Map<int, Library> _librariesById = {};
  bool _isLoading = true;
  SoundType _selectedType = SoundType.soundEffect;
  String _searchQuery = '';
  Timer? _searchDebounce;
  late final TextEditingController _searchController;
  final FocusNode _searchFocusNode = FocusNode();
  bool _searchFocusedBeforeTabTap = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _initializeRepository();
    _loadTagCatalog();
    _loadSounds();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_searchFocusNode.canRequestFocus) return;
      _searchFocusNode.requestFocus();
    });
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
      await widget.libraryRepository?.refreshLibraryOwnerEmails();
      final libraries = await LocalLibraryDataSource(widget.database)
          .getAllLibraries();
      final allSounds = await _repository.getAllSounds();
      // Sons déjà présents dans un pad de la board (indicatif uniquement)
      final inBoard = await _repository.getSoundIdsInBoard(widget.boardId);
      final soundIdToPadId =
          await _repository.getSoundIdToFirstPadIdInBoard(widget.boardId);

      final availableSounds = allSounds.where((s) => s.isClassifiedForTypeFilter).toList();

      setState(() {
        _librariesById = {for (final lib in libraries) lib.id: lib};
        _availableSounds = availableSounds;
        _soundsInBoard = inBoard;
        _soundIdToPadId = soundIdToPadId;
        _isLoading = false;
      });
      await _loadTagsForSounds(availableSounds);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        showCopyableSnackBar(context, 'Erreur lors du chargement: $e');
      }
    }
  }

  bool get _isSearchPreciseEnough =>
      _searchQuery.trim().length >= kMinPreciseSoundLibrarySearchLength;

  Future<void> _handleAdd(Sound sound) async {
    final isInBoard = _soundsInBoard.contains(sound.id);
    if (isInBoard) {
      final padId = _soundIdToPadId[sound.id];
      if (padId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pad introuvable pour ce son')),
          );
        }
        return;
      }
      if (!mounted) return;
      Navigator.pop(
        context,
        SoundLibraryScreenResult(highlightPadId: padId, wasAdded: false),
      );
      return;
    }

    try {
      final padId = await _addSoundToBoardUseCase(widget.boardId, sound.id);
      setState(() {
        _soundsInBoard.add(sound.id);
        _soundIdToPadId[sound.id] = padId;
      });
      if (!mounted) return;
      Navigator.pop(
        context,
        SoundLibraryScreenResult(highlightPadId: padId, wasAdded: true),
      );
    } catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, 'Erreur lors de l\'ajout: $e');
      }
    }
  }

  Future<void> _handleAddAsPad(Sound sound) async {
    if (_soundsInBoard.contains(sound.id)) return;

    try {
      final padId = await _addSoundToBoardUseCase(widget.boardId, sound.id);
      if (!mounted) return;
      setState(() {
        _soundsInBoard.add(sound.id);
        _soundIdToPadId[sound.id] = padId;
      });
    } catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, 'Erreur lors de l\'ajout: $e');
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

  List<String> get _normalizedSearchTokens {
    if (_searchQuery.trim().isEmpty) return const [];
    return _parseSearchTokens(_searchQuery)
        .map(normalizeForSearch)
        .where((t) => t.isNotEmpty)
        .toList();
  }

  Widget _buildTagChip(TagItem tag, {List<String> highlightTokens = const []}) {
    final color = _getCategoryColor(tag.categoryId);
    final matchingTokens = highlightTokens
        .where((t) => tag.normalizedName.contains(t))
        .toList();
    return Chip(
      label: Text.rich(
        buildHighlightedSpan(tag.name, matchingTokens),
        style: const TextStyle(fontSize: 11),
      ),
      visualDensity: VisualDensity.compact,
      backgroundColor: color?.withAlpha(24),
      side: color == null ? null : BorderSide(color: color),
    );
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

  String _displayPath(Sound sound) {
    return SoundDisplayPaths.forSound(
      sound,
      library: sound.libraryId != null
          ? _librariesById[sound.libraryId]
          : null,
    );
  }

  /// Vérifie si un son correspond à un token (tag/alias ou titre/displayName/chemin).
  bool _soundMatchesToken(Sound sound, String token) {
    final normalizedToken = normalizeForSearch(token);
    final matchInTitle = normalizeForSearch(
      sound.title,
    ).contains(normalizedToken);
    final matchInDisplayName =
        sound.displayName != null &&
        normalizeForSearch(sound.displayName!).contains(normalizedToken);
    final matchInPath = normalizeForSearch(
      _displayPath(sound),
    ).contains(normalizedToken);
    return matchInTitle || matchInDisplayName || matchInPath;
  }

  List<Sound> get _soundsForSelectedType => _availableSounds
      .where((sound) => sound.matchesSoundType(_selectedType))
      .toList();

  void _onTypeChanged(SoundType type) {
    if (_selectedType == type) return;
    final restoreSearchFocus = _searchFocusedBeforeTabTap;
    setState(() {
      _selectedType = type;
    });
    _scheduleSearch(_searchQuery);
    if (!restoreSearchFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_searchFocusNode.canRequestFocus) return;
      _searchFocusNode.requestFocus();
    });
  }

  List<Sound> get _filteredSounds {
    final typeSounds = _soundsForSelectedType;
    List<Sound> sounds;
    if (_searchQuery.trim().isEmpty) {
      sounds = typeSounds;
    } else if (_searchMatchedSoundIds == null) {
      sounds = typeSounds;
    } else {
      sounds = typeSounds
          .where((s) => _searchMatchedSoundIds!.contains(s.id))
          .toList();
    }

    if (!_isSearchPreciseEnough) {
      sounds = List<Sound>.from(sounds)
        ..sort((a, b) {
          final aInBoard = _soundsInBoard.contains(a.id);
          final bInBoard = _soundsInBoard.contains(b.id);
          if (aInBoard == bInBoard) return 0;
          return aInBoard ? 1 : -1;
        });
    }
    return sounds;
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
        final titleIds = _soundsForSelectedType
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

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
    });
    _scheduleSearch('');
    if (_searchFocusNode.canRequestFocus) {
      _searchFocusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Widget _buildTypeSelector() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, widget.isModal ? 8 : 16, 16, 8),
      child: Listener(
        onPointerDown: (_) {
          _searchFocusedBeforeTabTap = _searchFocusNode.hasFocus;
        },
        child: SegmentedButton<SoundType>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: SoundType.soundEffect,
              icon: Icon(SoundType.soundEffect.icon, size: 16),
              label: Text(SoundType.soundEffect.label),
            ),
            ButtonSegment(
              value: SoundType.ambiance,
              icon: Icon(SoundType.ambiance.icon, size: 16),
              label: Text(SoundType.ambiance.label),
            ),
            ButtonSegment(
              value: SoundType.music,
              icon: Icon(SoundType.music.icon, size: 16),
              label: Text(SoundType.music.label),
            ),
          ],
          selected: {_selectedType},
          onSelectionChanged: (selection) => _onTypeChanged(selection.first),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, widget.isModal ? 12 : 16),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Rechercher un son...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  onPressed: _clearSearch,
                  icon: const Icon(Icons.close_rounded),
                )
              : null,
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
    );
  }

  Widget _buildSoundList({ScrollController? scrollController}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _isLoading
          ? _LibraryLoadingList(
              key: const ValueKey('loading'),
              scrollController: scrollController,
            )
          : _filteredSounds.isEmpty
              ? Center(
                  key: ValueKey('empty_${_selectedType.name}'),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _selectedType.icon,
                        size: 64,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty
                            ? 'Aucun ${_selectedType.label.toLowerCase()} disponible'
                            : 'Aucun ${_selectedType.label.toLowerCase()} trouvé',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  key: ValueKey('list_${_selectedType.name}'),
                  controller: scrollController,
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
                            leading: SoundTypeAvatar(type: sound.type),
                            title: Text.rich(
                              buildHighlightedSpan(
                                sound.title,
                                _normalizedSearchTokens,
                              ),
                              style: TextStyle(
                                fontWeight: isInBoard
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  _displayPath(sound),
                                  style: const TextStyle(fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (tags.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      for (final tag in tags)
                                        _buildTagChip(
                                          tag,
                                          highlightTokens: _normalizedSearchTokens,
                                        ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      'Type: ${sound.typeDisplayLabel}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: SoundPickerActionButtons(
                              onGo: () => _handleAdd(sound),
                              secondaryEnabled: !isInBoard,
                              onSecondary: () => _handleAddAsPad(sound),
                              secondaryIcon: isInBoard
                                  ? Icons.check_rounded
                                  : Icons.view_comfy_alt_rounded,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildBody({ScrollController? listScrollController}) {
    return Column(
      children: [
        if (!widget.isModal) ...[
          _buildTypeSelector(),
          _buildSearchField(),
        ],
        Expanded(child: _buildSoundList(scrollController: listScrollController)),
      ],
    );
  }

  Widget _buildModalHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTypeSelector(),
        _buildSearchField(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isModal) {
      return AppBottomSheetShell(
        title: 'Ajouter un son',
        header: _buildModalHeader(),
        bodyBuilder: (context, scrollController) =>
            _buildBody(listScrollController: scrollController),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ajouter un son')),
      body: _buildBody(),
    );
  }
}

class _LibraryLoadingList extends StatelessWidget {
  const _LibraryLoadingList({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final titleHeight = textScaler.scale(12).clamp(12, 20).toDouble();
    final subtitleHeight = textScaler.scale(10).clamp(10, 18).toDouble();
    // Un seul contrôleur pour toute la liste : les cartes pulsent en phase.
    return Skeleton(
      child: ListView.builder(
        controller: scrollController,
        itemCount: 6,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Card(
              child: ListTile(
                isThreeLine: true,
                leading: const SkeletonBox(
                  width: 40,
                  height: 40,
                  shape: BoxShape.circle,
                ),
                title: SkeletonBox(height: titleHeight),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    SkeletonBox(height: subtitleHeight, intensity: 0.9),
                    const SizedBox(height: 6),
                    SkeletonLine(
                      widthFactor: 0.45,
                      height: subtitleHeight,
                      intensity: 0.75,
                    ),
                  ],
                ),
                trailing: const SkeletonBox(
                  width: 24,
                  height: 24,
                  shape: BoxShape.circle,
                  intensity: 0.8,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
