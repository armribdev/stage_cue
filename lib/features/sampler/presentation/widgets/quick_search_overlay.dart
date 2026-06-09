import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/string_utils.dart';
import '../../domain/entities/sound.dart';
import '../providers/sampler_provider.dart';
import '../utils/quick_search_prepare.dart';
import '../utils/sound_type_ui.dart';

/// Recherche-éclair : overlay flottant (pas une route plein écran) pour trouver
/// un son et agir en moins d'une seconde pendant un spectacle (refonte UX P1).
///
/// - résultats dès le 1er caractère, fuzzy + normalisé (accents) ;
/// - tri par pertinence puis récence ;
/// - tap sur une ligne = pré-écoute (audition, reste ouvert) ;
/// - `↑`/`↓` = parcourir les résultats ; `Entrée` = joue la sélection et ferme ;
/// - `Ctrl/Cmd+Entrée` = le prépare et ferme ; `Échap` = ferme.
///
/// Renvoie le résultat de préparation (pad à surligner pour les bruitages).
class QuickSearchOverlay extends StatefulWidget {
  final SamplerNotifier notifier;

  const QuickSearchOverlay({super.key, required this.notifier});

  static Future<QuickSearchPrepareResult?> show(
    BuildContext context, {
    required SamplerNotifier notifier,
  }) {
    return showGeneralDialog<QuickSearchPrepareResult?>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fermer la recherche',
      barrierColor: Colors.black.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (ctx, _, _) => QuickSearchOverlay(notifier: notifier),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.03), end: Offset.zero)
                .animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<QuickSearchOverlay> createState() => _QuickSearchOverlayState();
}

class _QuickSearchOverlayState extends State<QuickSearchOverlay> {
  final _controller = TextEditingController();
  late final FocusNode _focusNode;
  final _scrollController = ScrollController();
  final _itemKeys = <int, GlobalKey>{};
  List<Sound> _all = const [];
  bool _loading = true;
  String _query = '';
  SoundType? _typeFilter;
  bool _favoritesOnly = false;
  bool _localOnly = false;
  int _selectedIndex = 0;

  /// Ids des sons jouables hors-ligne (cache présent / fichier legacy). Chargé
  /// en arrière-plan ; null tant que le calcul n'est pas terminé.
  Set<int>? _localIds;

  Set<int> _tagMatchIds = const {};
  String _tagToken = '';
  Timer? _tagDebounce;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _onSearchKey);
    _load();
  }

  Future<void> _load() async {
    final sounds = await widget.notifier.getAllSounds();
    if (!mounted) return;
    setState(() {
      _all = sounds;
      _loading = false;
    });
    // Disponibilité hors-ligne calculée en tâche de fond (I/O par son).
    final localIds = await widget.notifier.getLocallyAvailableSoundIds();
    if (!mounted) return;
    setState(() => _localIds = localIds);
  }

  /// true si le son est jouable hors-ligne. Tant que le calcul n'est pas fini
  /// (`_localIds` null), on n'exclut rien (optimiste).
  bool _isLocal(Sound s) => _localIds?.contains(s.id) ?? true;

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      _selectedIndex = 0;
    });
    _tagDebounce?.cancel();
    _tagDebounce = Timer(const Duration(milliseconds: 120), () {
      unawaited(_runTagSearch(value));
    });
  }

  Future<void> _runTagSearch(String value) async {
    final norm = normalizeForSearch(value);
    _tagToken = norm;
    if (norm.isEmpty) {
      if (mounted) setState(() => _tagMatchIds = const {});
      return;
    }
    final ids = await widget.notifier.findSoundIdsByTagQuery(value);
    if (!mounted || _tagToken != norm) return;
    setState(() => _tagMatchIds = ids);
  }

  DateTime _recencyKey(Sound s) => s.lastPlayedAt ?? s.createdAt;

  /// Résultats filtrés et classés : pertinence, puis favoris, puis récence.
  /// Requête vide = parcours des favoris et sons récents (les plus utiles).
  List<Sound> get _results {
    final q = normalizeForSearch(_query);
    final scored = <(Sound, int)>[];
    for (final sound in _all) {
      if (_typeFilter != null && !sound.matchesSoundType(_typeFilter!)) continue;
      if (_favoritesOnly && !sound.isFavorite) continue;
      if (_localOnly && !_isLocal(sound)) continue;
      final name = normalizeForSearch(sound.displayName ?? sound.title);
      var score = fuzzyMatchScore(name, q);
      // Repli sur la correspondance par tag si le nom ne matche pas.
      if (score == null && _tagMatchIds.contains(sound.id)) score = 200;
      if (q.isEmpty) score = 0;
      if (score == null) continue;
      scored.add((sound, score));
    }
    scored.sort((a, b) {
      if (a.$2 != b.$2) return b.$2.compareTo(a.$2); // pertinence
      final favA = a.$1.isFavorite, favB = b.$1.isFavorite;
      if (favA != favB) return favA ? -1 : 1; // favoris d'abord
      return _recencyKey(b.$1).compareTo(_recencyKey(a.$1)); // récence
    });
    return [for (final e in scored) e.$1];
  }

  /// Liste affichée (sous-ensemble en mode parcours favoris/récents).
  List<Sound> _shownResults(List<Sound> results) {
    final isBrowse = _query.isEmpty && !_favoritesOnly;
    if (!isBrowse) return results;
    return results
        .where((s) => s.isFavorite || s.lastPlayedAt != null)
        .take(25)
        .toList();
  }

  int _clampSelectedIndex(int count) =>
      count == 0 ? 0 : _selectedIndex.clamp(0, count - 1);

  /// Hauteur fixe des lignes — aligne le scroll clavier et évite le « saut » visuel.
  static const _itemExtent = 64.0;

  void _moveSelection(int delta) {
    final shown = _shownResults(_results);
    if (shown.isEmpty) return;
    final next = (_selectedIndex + delta).clamp(0, shown.length - 1);
    if (next == _selectedIndex) return;

    final soundId = shown[next].id;
    final policy = delta < 0
        ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
        : ScrollPositionAlignmentPolicy.keepVisibleAtEnd;
    final ctx = _itemKey(soundId).currentContext;

    if (ctx != null) {
      // Ligne déjà rendue : scroll d'abord, puis surlignage (même frame).
      Scrollable.ensureVisible(
        ctx,
        duration: Duration.zero,
        alignmentPolicy: policy,
      );
      setState(() => _selectedIndex = next);
      return;
    }

    // Ligne hors écran (ListView.builder) : pré-scroll, puis rendu + ajustement fin.
    _preScrollToIndex(next, delta);
    setState(() => _selectedIndex = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final lateCtx = _itemKey(soundId).currentContext;
      if (lateCtx == null) return;
      Scrollable.ensureVisible(
        lateCtx,
        duration: Duration.zero,
        alignmentPolicy: policy,
      );
    });
  }

  GlobalKey _itemKey(int soundId) =>
      _itemKeys.putIfAbsent(soundId, GlobalKey.new);

  void _preScrollToIndex(int index, int delta) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final viewport = position.viewportDimension;
    final current = position.pixels;
    final max = position.maxScrollExtent;
    final itemTop = index * _itemExtent;
    final itemBottom = itemTop + _itemExtent;

    if (delta > 0 && itemBottom > current + viewport) {
      _scrollController.jumpTo((itemBottom - viewport).clamp(0.0, max));
    } else if (delta < 0 && itemTop < current) {
      _scrollController.jumpTo(itemTop.clamp(0.0, max));
    }
  }

  Future<void> _play(Sound sound) async {
    final ok = await widget.notifier.previewSound(sound.id);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Son indisponible — vérifiez la connexion'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _playSelectedAndClose() async {
    final shown = _shownResults(_results);
    if (shown.isEmpty) return;
    final index = _clampSelectedIndex(shown.length);
    await widget.notifier.previewSound(shown[index].id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _prepareAndClose(Sound sound) async {
    final result = await widget.notifier.prepareSoundFromQuickSearch(sound.id);
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> _prepareSelectedAndClose() async {
    final shown = _shownResults(_results);
    if (shown.isEmpty) return;
    await _prepareAndClose(shown[_clampSelectedIndex(shown.length)]);
  }

  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _tagDebounce?.cancel();
    _focusNode.dispose();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    final results = _results;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            unawaited(_prepareSelectedAndClose()),
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
            unawaited(_prepareSelectedAndClose()),
      },
      child: Align(
        alignment: Alignment.center,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            mq.padding.top + 12,
            12,
            mq.padding.bottom + 12,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: mq.size.height * 0.7,
            ),
            child: Material(
              color: scheme.surface,
              elevation: 8,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSearchField(scheme),
                  _buildTypeFilters(scheme),
                  const Divider(height: 1),
                  Flexible(child: _buildResults(scheme, results)),
                  _buildHints(scheme, results.isNotEmpty),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              textInputAction: TextInputAction.go,
              onChanged: _onQueryChanged,
              onSubmitted: (_) => unawaited(_playSelectedAndClose()),
              decoration: const InputDecoration(
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                hintText: 'Chercher un son…',
                isCollapsed: true,
              ),
              style: const TextStyle(fontSize: 17),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Fermer',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeFilters(ColorScheme scheme) {
    Widget chip(String label, SoundType? type) {
      final selected = _typeFilter == type;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FilterChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          onSelected: (_) =>
              setState(() {
                _typeFilter = type;
                _selectedIndex = 0;
              }),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  chip('Tous', null),
                  chip('SFX', SoundType.soundEffect),
                  chip('Musique', SoundType.music),
                  chip('Ambiance', SoundType.ambiance),
                ],
              ),
            ),
            _roundActionButton(
              scheme: scheme,
              icon: _favoritesOnly
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
              tooltip: 'Favoris uniquement',
              iconColor: _favoritesOnly
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
              onPressed: () => setState(() {
                _favoritesOnly = !_favoritesOnly;
                _selectedIndex = 0;
              }),
            ),
            const SizedBox(width: 4),
            _roundActionButton(
              scheme: scheme,
              icon: Icons.offline_bolt_rounded,
              tooltip: 'Local uniquement',
              iconColor:
                  _localOnly ? scheme.primary : scheme.onSurfaceVariant,
              onPressed: () => setState(() {
                _localOnly = !_localOnly;
                _selectedIndex = 0;
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(ColorScheme scheme, List<Sound> results) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // À l'ouverture (requête vide, hors filtre favoris) : accès direct aux
    // favoris et sons récemment joués, plutôt que tout déverser.
    final isBrowse = _query.isEmpty && !_favoritesOnly;
    final shown = _shownResults(results);
    final selectedIndex = _clampSelectedIndex(shown.length);

    if (shown.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            isBrowse
                ? 'Tapez pour chercher vos sons'
                : 'Aucun son',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isBrowse)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              'FAVORIS & RÉCENTS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        Expanded(
          child: ClipRect(
            child: ListView.builder(
              controller: _scrollController,
              itemExtent: _itemExtent,
              padding: EdgeInsets.zero,
              itemCount: shown.length,
              itemBuilder: (context, index) {
                final sound = shown[index];
                final isSelected = index == selectedIndex;
                final fav = sound.isFavorite;
                return Material(
                  key: _itemKey(sound.id),
                  color: isSelected
                      ? scheme.primary.withValues(alpha: 0.10)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() => _selectedIndex = index);
                      unawaited(_play(sound));
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            _typeIcon(sound.type),
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  sound.displayName ?? sound.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Row(
                                  children: [
                                    Text(
                                      _typeLabel(sound.type),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    if (_localIds != null &&
                                        !_isLocal(sound)) ...[
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.cloud_outlined,
                                        size: 13,
                                        color: scheme.onSurfaceVariant
                                            .withValues(alpha: 0.7),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (fav) ...[
                                Tooltip(
                                  message: 'Favori',
                                  child: SizedBox(
                                    width: _actionButtonSize,
                                    height: _actionButtonSize,
                                    child: Icon(
                                      Icons.star_rounded,
                                      size: 18,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              _roundActionButton(
                                scheme: scheme,
                                icon: sound.type == SoundType.music
                                    ? Icons.playlist_add_rounded
                                    : Icons.layers_rounded,
                                tooltip: 'Préparer',
                                iconColor: scheme.primary,
                                onPressed: () =>
                                    unawaited(_prepareAndClose(sound)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  static const _actionButtonSize = 30.0;

  Widget _roundActionButton({
    required ColorScheme scheme,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required Color iconColor,
  }) {
    return SizedBox(
      width: _actionButtonSize,
      height: _actionButtonSize,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          hoverColor: scheme.onSurface.withValues(alpha: 0.08),
          foregroundColor: iconColor,
        ),
        constraints: const BoxConstraints.tightFor(
          width: _actionButtonSize,
          height: _actionButtonSize,
        ),
      ),
    );
  }

  Widget _buildHints(ColorScheme scheme, bool hasResults) {
    if (!hasResults) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Text(
        '↑↓ sélectionner    ↵ jouer    ⌘/Ctrl+↵ préparer    tap audition',
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
    );
  }

  IconData _typeIcon(SoundType type) => switch (type) {
        SoundType.soundEffect => Icons.graphic_eq_rounded,
        SoundType.music => Icons.music_note_rounded,
        SoundType.ambiance => Icons.waves_rounded,
      };

  String _typeLabel(SoundType type) => switch (type) {
        SoundType.soundEffect => 'Effet',
        SoundType.music => 'Musique',
        SoundType.ambiance => 'Ambiance',
      };
}
