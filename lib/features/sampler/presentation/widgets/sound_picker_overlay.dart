import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/skeleton.dart';
import '../../../../core/utils/string_utils.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';
import '../providers/sampler_provider.dart';
import '../utils/quick_search_prepare.dart';
import '../utils/sound_type_ui.dart';
import 'scrolling_text.dart';

// ── Modes ─────────────────────────────────────────────────────────────────────

sealed class SoundPickerMode {
  const SoundPickerMode();
}

/// Recherche-éclair (Ctrl+F) : preview + préparer un bruitage/ambiance.
final class QuickSearchMode extends SoundPickerMode {
  const QuickSearchMode();
}

/// Sélecteur de musique : joue ou met en file d'attente.
final class MusicPickerMode extends SoundPickerMode {
  const MusicPickerMode();
}

/// Sélecteur de sons pour un pad existant ou un nouveau pad brouillon.
final class PadPickerMode extends SoundPickerMode {
  final int? padId;
  final int? draftPadId;
  final List<int>? draftSelectedIds;
  final VoidCallback? onPadUpdated;

  const PadPickerMode({
    this.padId,
    this.draftPadId,
    this.draftSelectedIds,
    this.onPadUpdated,
  }) : assert(
         padId != null || draftPadId != null,
         'padId ou draftPadId requis',
       );
}

/// Parcours de la bibliothèque : ajoute un son au plateau courant.
/// Équivalent de SoundLibraryScreen pour les contextes avec SamplerNotifier.
final class LibraryMode extends SoundPickerMode {
  const LibraryMode();
}

/// Gestion de la bibliothèque : tap ouvre le formulaire d'édition du son.
/// L'overlay reste ouvert entre les éditions.
final class ManageMode extends SoundPickerMode {
  final Future<void> Function(
    BuildContext context,
    Sound sound,
    List<TagCategoryWithTags> tagCatalog,
  ) onTap;

  ManageMode({required this.onTap});
}

// ── Widget principal ──────────────────────────────────────────────────────────

/// Overlay flottant unifié pour chercher et sélectionner un son.
///
/// Remplace [QuickSearchMode] (Ctrl+F), [MusicPickerMode] (sélecteur musique),
/// [PadPickerMode] (ajout/retrait sons d'un pad) et [LibraryMode] (ajout au plateau).
///
/// Même UX partout : fuzzy search normalisé, filtres par type, navigation clavier.
class SoundPickerOverlay extends StatefulWidget {
  final SamplerNotifier notifier;
  final SoundPickerMode mode;
  final bool _isFullPage;

  const SoundPickerOverlay._({
    required this.notifier,
    required this.mode,
    bool isFullPage = false,
  }) : _isFullPage = isFullPage;

  static bool _isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600;

  /// Recherche-éclair (Ctrl+F) — renvoie le pad à surligner pour les bruitages.
  static Future<QuickSearchPrepareResult?> show(
    BuildContext context, {
    required SamplerNotifier notifier,
  }) {
    final mobile = _isMobile(context);
    final w = SoundPickerOverlay._(
        notifier: notifier, mode: const QuickSearchMode(), isFullPage: mobile);
    return mobile
        ? _showPage<QuickSearchPrepareResult?>(context, w)
        : _showDialog<QuickSearchPrepareResult?>(context, w);
  }

  /// Sélecteur de musique — joue maintenant ou met en file.
  static Future<void> showForMusic(
    BuildContext context, {
    required SamplerNotifier notifier,
  }) {
    final mobile = _isMobile(context);
    final w = SoundPickerOverlay._(
        notifier: notifier, mode: const MusicPickerMode(), isFullPage: mobile);
    return mobile ? _showPage<void>(context, w) : _showDialog<void>(context, w);
  }

  /// Sélecteur de sons pour un pad existant ou un brouillon.
  static Future<void> showForPad(
    BuildContext context, {
    required SamplerNotifier notifier,
    int? padId,
    int? draftPadId,
    List<int>? draftSelectedIds,
    VoidCallback? onPadUpdated,
  }) {
    final mobile = _isMobile(context);
    final w = SoundPickerOverlay._(
      notifier: notifier,
      mode: PadPickerMode(
        padId: padId,
        draftPadId: draftPadId,
        draftSelectedIds: draftSelectedIds,
        onPadUpdated: onPadUpdated,
      ),
      isFullPage: mobile,
    );
    return mobile ? _showPage<void>(context, w) : _showDialog<void>(context, w);
  }

  /// Parcours bibliothèque — ajoute un son au plateau et renvoie le pad créé/trouvé.
  static Future<QuickSearchPrepareResult?> showForLibrary(
    BuildContext context, {
    required SamplerNotifier notifier,
  }) {
    final mobile = _isMobile(context);
    final w = SoundPickerOverlay._(
        notifier: notifier, mode: const LibraryMode(), isFullPage: mobile);
    return mobile
        ? _showPage<QuickSearchPrepareResult?>(context, w)
        : _showDialog<QuickSearchPrepareResult?>(context, w);
  }

  /// Gestion de bibliothèque — l'overlay reste ouvert, tap appelle [onTap].
  static Future<void> showForManage(
    BuildContext context, {
    required SamplerNotifier notifier,
    required Future<void> Function(
      BuildContext context,
      Sound sound,
      List<TagCategoryWithTags> tagCatalog,
    ) onTap,
  }) {
    final mobile = _isMobile(context);
    final w = SoundPickerOverlay._(
        notifier: notifier, mode: ManageMode(onTap: onTap), isFullPage: mobile);
    return mobile ? _showPage<void>(context, w) : _showDialog<void>(context, w);
  }

  static Future<T?> _showPage<T>(BuildContext context, SoundPickerOverlay child) =>
      Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => child));

  static Future<T?> _showDialog<T>(BuildContext context, SoundPickerOverlay child) =>
      showGeneralDialog<T>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Fermer',
        barrierColor: Colors.black.withValues(alpha: 0.4),
        transitionDuration: const Duration(milliseconds: 120),
        pageBuilder: (ctx, _, _) => child,
        transitionBuilder: (ctx, anim, _, child) {
          final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.03),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );

  @override
  State<SoundPickerOverlay> createState() => _SoundPickerOverlayState();
}

class _SoundPickerOverlayState extends State<SoundPickerOverlay> {
  final _controller = TextEditingController();
  late final FocusNode _focusNode;
  final _scrollController = ScrollController();
  final _itemKeys = <int, GlobalKey>{};

  // ── Données ───────────────────────────────────────────────────────────────
  List<Sound> _all = const [];
  bool _loading = true;
  List<TagCategoryWithTags> _tagCatalog = const [];

  // ── Filtres ───────────────────────────────────────────────────────────────
  String _query = '';
  SoundType? _typeFilter;
  bool _favoritesOnly = false;
  bool _localOnly = false;

  // ── Recherche par tag ─────────────────────────────────────────────────────
  // Un Set<int> par token (ordre identique à _normalizedTokens).
  List<Set<int>> _tagMatchSetsPerToken = const [];
  String _tagToken = '';
  // Débounce partagé : retarde à la fois le scoring flou des titres (coûteux
  // sur toute la bibliothèque) et la requête SQL de recherche par tag, pour
  // ne recalculer qu'une fois l'utilisateur arrêté de taper.
  Timer? _searchDebounce;

  // ── Tags des sons affichés ────────────────────────────────────────────────
  final Map<int, List<TagItem>> _soundTags = {};
  String _tagsLoadToken = '';
  Timer? _tagsLoadDebounce;

  // ── Offline (QuickSearch uniquement) ─────────────────────────────────────
  Set<int>? _localIds;

  // ── Scope d'un board Drive (VUE PARTAGÉE) ────────────────────────────────
  // Ids des sons visibles par la bibliothèque du board actif : ses dossiers,
  // recouvrements de liens compris. null tant que non chargé (repli sur
  // l'appartenance directe `sound.libraryId`).
  Set<int>? _scopeIds;

  // ── Navigation clavier ────────────────────────────────────────────────────
  int _selectedIndex = 0;
  int? _hoveredIndex;

  // ── État du sélecteur de pad ──────────────────────────────────────────────
  Set<int> _padSoundIds = const {};
  final Set<int> _addingSoundIds = {};
  final Set<int> _removingSoundIds = {};

  // ── Helpers de mode ───────────────────────────────────────────────────────

  bool get _isQuickSearch => widget.mode is QuickSearchMode;
  bool get _isMusicPicker => widget.mode is MusicPickerMode;
  bool get _isPadPicker => widget.mode is PadPickerMode;
  bool get _isLibrary => widget.mode is LibraryMode;
  bool get _isManage => widget.mode is ManageMode;

  /// Bibliothèque du board actif : null = board local. Un board rattaché à une
  /// bibliothèque ne propose que les sons de celle-ci. Un board local (null)
  /// n'impose aucune restriction : depuis le modèle folder-based (v23+), tout
  /// son a une bibliothèque, donc scoper sur `libraryId == null` donnerait
  /// toujours un ensemble vide. Le mode gestion parcourt tout de toute façon.
  int? get _boardLibraryId => widget.notifier.state.selectedBoard?.libraryId;

  bool _matchesBoardScope(Sound sound) {
    if (_isManage) return true;
    final libraryId = _boardLibraryId;
    if (libraryId == null) return true;
    // VUE PARTAGÉE : visibilité par appartenance de dossier (inclut les sons
    // partagés d'un dossier recouvert), pas seulement `sound.libraryId`. Repli
    // sur l'appartenance directe tant que le scope n'est pas chargé.
    final scope = _scopeIds;
    if (scope != null) return scope.contains(sound.id);
    return sound.libraryId == libraryId;
  }

  PadPickerMode? get _padMode =>
      widget.mode is PadPickerMode ? widget.mode as PadPickerMode : null;

  ManageMode? get _manageMode =>
      widget.mode is ManageMode ? widget.mode as ManageMode : null;

  /// Type verrouillé pour le sélecteur de musique.
  SoundType? get _lockedTypeFilter => _isMusicPicker ? SoundType.music : null;
  SoundType? get _effectiveTypeFilter => _lockedTypeFilter ?? _typeFilter;

  bool get _effectiveLocalOnly => _isQuickSearch && _localOnly;

  bool _isLocal(Sound s) {
    if (_localIds == null) return !_effectiveLocalOnly;
    return _localIds!.contains(s.id);
  }

  bool get _awaitingLocalIds => _isQuickSearch && _effectiveLocalOnly && _localIds == null;

  String get _hintText => switch (widget.mode) {
    QuickSearchMode() => 'Chercher un son…',
    MusicPickerMode() => 'Chercher une musique…',
    PadPickerMode() || LibraryMode() || ManageMode() => 'Chercher un son…',
  };

  String get _emptyMessage {
    if (_isQuickSearch) {
      if (_effectiveLocalOnly) return 'Aucun son disponible hors-ligne';
      if (_query.isEmpty && !_favoritesOnly) return 'Tapez pour chercher vos sons';
    }
    return 'Aucun son';
  }

  String get _hintsText => switch (widget.mode) {
    QuickSearchMode() =>
      '↑↓ sélectionner    ↵ jouer    ⌘/Ctrl+↵ préparer    tap audition',
    MusicPickerMode() =>
      '↑↓ sélectionner    ↵/tap ajouter à la file',
    PadPickerMode() =>
      '↑↓ sélectionner    ↵ ajouter/retirer',
    LibraryMode() =>
      '↑↓ sélectionner    ↵/tap éditer',
    ManageMode() =>
      '↑↓ sélectionner    ↵/tap éditer    ▶ aperçu depuis le point d\'entrée',
  };

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _onSearchKey);
    widget.notifier.addListener(_onNotifierChanged);
    if (_isPadPicker) _typeFilter = SoundType.soundEffect;
    if (_isQuickSearch && widget.notifier.isLiveOfflineMode) {
      _localOnly = true;
    }
    _load();
  }

  void _onNotifierChanged() {
    if (!mounted) return;
    setState(() {
      if (_isQuickSearch) _selectedIndex = 0;
      if (_isPadPicker) _syncPadSoundIds();
    });
    _scheduleTagsLoad();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      widget.notifier.getAllSounds(),
      widget.notifier.loadTagCatalog(),
    ]);
    if (!mounted) return;
    setState(() {
      _all = results[0] as List<Sound>;
      _tagCatalog = results[1] as List<TagCategoryWithTags>;
      _loading = false;
      if (_isPadPicker) _syncPadSoundIds();
    });
    _scheduleTagsLoad();
    // Scope d'un board Drive : sons visibles par sa bibliothèque (vue partagée).
    final scopeLibraryId = _boardLibraryId;
    if (scopeLibraryId != null && !_isManage) {
      final scopeIds =
          await widget.notifier.getSoundIdsVisibleToLibrary(scopeLibraryId);
      if (!mounted) return;
      setState(() => _scopeIds = scopeIds);
    }
    if (_isQuickSearch) {
      final localIds = await widget.notifier.getLocallyAvailableSoundIds();
      if (!mounted) return;
      setState(() => _localIds = localIds);
    }
  }

  void _syncPadSoundIds() {
    final mode = _padMode;
    if (mode == null) return;
    final draftIds = mode.draftSelectedIds;
    if (draftIds != null) {
      _padSoundIds = draftIds.toSet();
      return;
    }
    final padItem = widget.notifier.state.pads
        .where((p) => p.pad.id == mode.padId)
        .firstOrNull;
    _padSoundIds = padItem?.pad.sounds.map((s) => s.id).toSet() ?? const {};
  }

  @override
  void dispose() {
    if (_isManage) {
      // Pas de notify : évite setState sur SamplerScreen pendant le pop.
      widget.notifier.stopLibraryPreview(notify: false);
    }
    widget.notifier.removeListener(_onNotifierChanged);
    _searchDebounce?.cancel();
    _tagsLoadDebounce?.cancel();
    _focusNode.dispose();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  // ── Recherche ─────────────────────────────────────────────────────────────

  void _onQueryChanged(String value) {
    // Le champ de texte gère son propre affichage via _controller : retarder
    // la mise à jour de _query ne fait pas lagger la frappe, seulement le
    // recalcul du scoring flou (sur toute la bibliothèque) et la recherche
    // de tags — inutile de les relancer à chaque caractère tapé.
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      setState(() {
        _query = value;
        _selectedIndex = 0;
      });
      unawaited(_runTagSearch(value));
    });
  }

  /// Tokens normalisés (≥ 2 chars) extraits de [_query].
  List<String> get _normalizedTokens {
    if (_query.trim().isEmpty) return const [];
    return _query
        .split(RegExp(r'[\s,]+'))
        .map((t) => normalizeForSearch(t.trim()))
        .where((t) => t.length >= 2)
        .toList();
  }

  /// Tokens à mettre en gras : les tokens normalisés si disponibles,
  /// sinon la requête entière normalisée (pour les mots courts / 1 token).
  List<String> get _highlightTokens {
    final tokens = _normalizedTokens;
    if (tokens.isNotEmpty) return tokens;
    final q = normalizeForSearch(_query);
    return q.isEmpty ? const [] : [q];
  }

  Future<void> _runTagSearch(String value) async {
    final norm = normalizeForSearch(value);
    _tagToken = norm;
    if (norm.isEmpty) {
      if (mounted) setState(() => _tagMatchSetsPerToken = const []);
      return;
    }
    final tokens = value
        .split(RegExp(r'[\s,]+'))
        .map((t) => t.trim())
        .where((t) => t.length >= 2)
        .toList();
    // Si aucun token valide (requête < 2 chars), cherche la requête entière.
    final queries = tokens.isEmpty ? [value] : tokens;
    final sets = await Future.wait(
      queries.map((t) => widget.notifier.findSoundIdsByTagQuery(t)),
    );
    if (!mounted || _tagToken != norm) return;
    setState(() => _tagMatchSetsPerToken = sets);
    _scheduleTagsLoad();
  }

  void _scheduleTagsLoad() {
    _tagsLoadDebounce?.cancel();
    _tagsLoadDebounce = Timer(const Duration(milliseconds: 120), () {
      unawaited(_loadTagsForShownResults());
    });
  }

  Future<void> _loadTagsForShownResults() async {
    final shown = _shownResults(_results);
    if (shown.isEmpty) {
      if (!mounted) return;
      setState(() => _soundTags.clear());
      return;
    }
    final token = shown.map((s) => s.id).join(',');
    _tagsLoadToken = token;
    final entries = await Future.wait(
      shown.map((sound) async {
        final tags = await widget.notifier.getTagsForSound(sound.id);
        return MapEntry(sound.id, tags);
      }),
    );
    if (!mounted || _tagsLoadToken != token) return;
    setState(() {
      _soundTags
        ..clear()
        ..addEntries(entries);
    });
  }

  // ── Résultats ─────────────────────────────────────────────────────────────

  DateTime _recencyKey(Sound s) => s.lastPlayedAt ?? s.createdAt;

  List<Sound> get _results {
    final q = normalizeForSearch(_query);
    final tokens = _normalizedTokens;
    final scored = <(Sound, int)>[];
    for (final sound in _all) {
      if (!_matchesBoardScope(sound)) { continue; }
      if (_effectiveTypeFilter != null &&
          !sound.matchesSoundType(_effectiveTypeFilter!)) { continue; }
      if (_favoritesOnly && !sound.isFavorite) { continue; }
      if (_effectiveLocalOnly && !_isLocal(sound)) { continue; }

      int? score;
      if (q.isEmpty) {
        score = 0;
      } else if (tokens.isEmpty) {
        // Requête sans token valide (ex : 1 char) → fuzzy entier + tag fallback.
        final name = normalizeForSearch(sound.displayName ?? sound.title);
        score = fuzzyMatchScore(name, q);
        if (score == null && _tagMatchSetsPerToken.isNotEmpty &&
            _tagMatchSetsPerToken[0].contains(sound.id)) { score = 200; }
      } else {
        // Logique AND par token : chaque token doit matcher titre OU tag.
        final name = normalizeForSearch(sound.displayName ?? sound.title);
        var total = 0;
        var allMatch = true;
        for (var i = 0; i < tokens.length; i++) {
          final ts = fuzzyMatchScore(name, tokens[i]);
          if (ts != null) {
            total += ts;
          } else if (i < _tagMatchSetsPerToken.length &&
                     _tagMatchSetsPerToken[i].contains(sound.id)) {
            total += 200;
          } else {
            allMatch = false;
            break;
          }
        }
        if (allMatch) score = total;
      }

      if (score == null) continue;
      scored.add((sound, score));
    }
    scored.sort((a, b) {
      if (a.$2 != b.$2) return b.$2.compareTo(a.$2);
      final favA = a.$1.isFavorite, favB = b.$1.isFavorite;
      if (favA != favB) return favA ? -1 : 1;
      return _recencyKey(b.$1).compareTo(_recencyKey(a.$1));
    });
    return [for (final e in scored) e.$1];
  }

  /// Mode parcours : favoris + récents uniquement (QuickSearch, requête vide).
  List<Sound> _shownResults(List<Sound> results) {
    final isBrowse = _isQuickSearch && _query.isEmpty && !_favoritesOnly;
    if (!isBrowse) return results;
    return results
        .where((s) => s.isFavorite || s.lastPlayedAt != null)
        .take(25)
        .toList();
  }

  bool get _isBrowseMode => _isQuickSearch && _query.isEmpty && !_favoritesOnly;

  // ── Navigation clavier ────────────────────────────────────────────────────

  int _clampSelectedIndex(int count) =>
      count == 0 ? 0 : _selectedIndex.clamp(0, count - 1);

  static const _itemExtent = 72.0;
  static const _actionButtonSize = 30.0;
  static const _overlayMaxWidth = 720.0;
  static const _maxVisibleTags = 3;

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
      Scrollable.ensureVisible(ctx, duration: Duration.zero, alignmentPolicy: policy);
      setState(() => _selectedIndex = next);
      return;
    }

    _preScrollToIndex(next, delta);
    setState(() => _selectedIndex = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final lateCtx = _itemKey(soundId).currentContext;
      if (lateCtx == null) return;
      Scrollable.ensureVisible(lateCtx, duration: Duration.zero, alignmentPolicy: policy);
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

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _onSubmit() async {
    final shown = _shownResults(_results);
    if (shown.isEmpty) return;
    final sound = shown[_clampSelectedIndex(shown.length)];
    switch (widget.mode) {
      case QuickSearchMode():
        await widget.notifier.previewSound(sound.id);
        if (mounted) Navigator.of(context).pop();
      case MusicPickerMode():
        await _enqueueMusic(sound);
      case PadPickerMode():
        await _togglePadSound(sound);
      case LibraryMode():
        await _prepareAndClose(sound);
      case ManageMode():
        await _handleManageTap(sound);
    }
  }

  // QuickSearch
  Future<void> _previewSound(Sound sound) async {
    final ok = await widget.notifier.previewSound(sound.id);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Son indisponible — vérifiez la connexion'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleLibraryPreview(Sound sound) async {
    final ok = await widget.notifier.toggleLibraryPreview(sound.id);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Son indisponible — vérifiez la connexion'),
        behavior: SnackBarBehavior.floating,
      ),
    );
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

  // Music picker
  Future<void> _enqueueMusic(Sound sound) async {
    await widget.notifier.enqueueMusicBySoundId(sound.id);
  }

  bool _isMusicOnAir(Sound sound) {
    final padItem = widget.notifier.findMusicPadForSound(sound.id);
    if (padItem == null) return false;
    final current = widget.notifier.state.currentMusicPad;
    return current?.pad.id == padItem.pad.id && (current?.isPlaying ?? false);
  }

  bool _isMusicQueued(Sound sound) {
    final padItem = widget.notifier.findMusicPadForSound(sound.id);
    if (padItem == null) return false;
    return widget.notifier.state.musicQueuePadIds.contains(padItem.pad.id);
  }

  bool _isMusicOnBoard(Sound sound) => widget.notifier.state.pads
      .any((p) => p.pad.sounds.any((s) => s.id == sound.id));

  // Pad picker
  Future<void> _togglePadSound(Sound sound) async {
    final mode = _padMode!;
    if (_addingSoundIds.contains(sound.id) ||
        _removingSoundIds.contains(sound.id)) { return; }
    if (_padSoundIds.contains(sound.id)) {
      await _removePadSound(sound, mode);
    } else {
      await _addPadSound(sound, mode);
    }
  }

  Future<void> _addPadSound(Sound sound, PadPickerMode mode) async {
    if (_padSoundIds.contains(sound.id)) return;
    final draftIds = mode.draftSelectedIds;
    if (draftIds != null) {
      draftIds.add(sound.id);
      await widget.notifier.updateDraftPadSounds(mode.draftPadId!, draftIds);
      if (!mounted) return;
      setState(_syncPadSoundIds);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() => _addingSoundIds.add(sound.id));
    await widget.notifier.addSoundToPad(mode.padId!, sound.id);
    if (!mounted) return;
    setState(() {
      _addingSoundIds.remove(sound.id);
      _syncPadSoundIds();
    });
    mode.onPadUpdated?.call();
  }

  Future<void> _removePadSound(Sound sound, PadPickerMode mode) async {
    if (!_padSoundIds.contains(sound.id)) return;
    final draftIds = mode.draftSelectedIds;
    if (draftIds != null) {
      draftIds.remove(sound.id);
      await widget.notifier.updateDraftPadSounds(mode.draftPadId!, draftIds);
      if (!mounted) return;
      setState(_syncPadSoundIds);
      return;
    }
    if (_padSoundIds.length <= 1) return;
    setState(() => _removingSoundIds.add(sound.id));
    await widget.notifier.removeSoundFromPad(mode.padId!, sound.id);
    if (!mounted) return;
    setState(() {
      _removingSoundIds.remove(sound.id);
      _syncPadSoundIds();
    });
    mode.onPadUpdated?.call();
  }

  // Manage
  Future<void> _handleManageTap(Sound sound) async {
    await _manageMode!.onTap(context, sound, _tagCatalog);
    if (!mounted) return;
    await _reloadSounds();
  }

  Future<void> _reloadSounds() async {
    final sounds = await widget.notifier.getAllSounds();
    if (!mounted) return;
    setState(() => _all = sounds);
    _scheduleTagsLoad();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    final shown = _loading || _awaitingLocalIds
        ? const <Sound>[]
        : _shownResults(_results);
    final selectedIndex = _clampSelectedIndex(shown.length);

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.of(context).pop(),
      if (_isQuickSearch) ...<ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            unawaited(_prepareSelectedAndClose()),
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
            unawaited(_prepareSelectedAndClose()),
      },
    };

    if (widget._isFullPage) {
      return CallbackShortcuts(
        bindings: shortcuts,
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _buildSearchField(scheme),
                _buildTypeFilters(scheme),
                _buildFilterDivider(scheme),
                Expanded(child: _buildResults(scheme, shown, selectedIndex)),
                _buildHints(scheme, shown.isNotEmpty),
              ],
            ),
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: shortcuts,
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
              maxWidth: (mq.size.width - 24).clamp(320.0, _overlayMaxWidth),
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
                  _buildFilterDivider(scheme),
                  Flexible(child: _buildResults(scheme, shown, selectedIndex)),
                  _buildHints(scheme, shown.isNotEmpty),
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
          Icon(
            _isMusicPicker ? SoundType.music.icon : Icons.search_rounded,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              textInputAction: TextInputAction.go,
              onChanged: _onQueryChanged,
              onSubmitted: (_) => unawaited(_onSubmit()),
              decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                hintText: _hintText,
                isCollapsed: true,
              ),
              style: const TextStyle(fontSize: 17),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeFilters(ColorScheme scheme) {
    // Musique : type verrouillé → pas de barre de filtres.
    if (_lockedTypeFilter != null) return const SizedBox.shrink();

    Widget chip(String label, SoundType? type, IconData icon) {
      final selected = _effectiveTypeFilter == type;
      final colors = type?.avatarColors(scheme) ??
          (background: scheme.primaryContainer, foreground: scheme.onPrimaryContainer);
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FilterChip(
          avatar: Icon(
            icon,
            size: 16,
            color: selected ? colors.foreground : scheme.onSurfaceVariant,
          ),
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          backgroundColor: scheme.surface,
          selectedColor: colors.background,
          side: BorderSide(
            color: selected
                ? Colors.transparent
                : scheme.outlineVariant.withValues(alpha: 0.6),
          ),
          shape: const StadiumBorder(),
          labelStyle: TextStyle(
            color: selected ? colors.foreground : scheme.onSurfaceVariant,
          ),
          onSelected: (_) {
            setState(() {
              _typeFilter = type;
              _selectedIndex = 0;
            });
            _scheduleTagsLoad();
            _focusNode.requestFocus();
          },
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
        child: Row(
          children: [
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  // "Tous" uniquement pour QuickSearch, Library et Manage
                  if (_isQuickSearch || _isLibrary || _isManage)
                    chip('Tous', null, Icons.apps_rounded),
                  chip(SoundType.soundEffect.label, SoundType.soundEffect,
                      SoundType.soundEffect.icon),
                  chip(SoundType.music.label, SoundType.music, SoundType.music.icon),
                  chip(SoundType.ambiance.label, SoundType.ambiance,
                      SoundType.ambiance.icon),
                ],
              ),
            ),
            if (_isQuickSearch) ...[
              Container(
                width: 1,
                height: 22,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
              _roundIconButton(
                scheme: scheme,
                icon: _favoritesOnly
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                iconColor: _favoritesOnly
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
                active: _favoritesOnly,
                onPressed: () {
                  setState(() {
                    _favoritesOnly = !_favoritesOnly;
                    _selectedIndex = 0;
                  });
                  _scheduleTagsLoad();
                  _focusNode.requestFocus();
                },
              ),
              const SizedBox(width: 4),
              _roundIconButton(
                scheme: scheme,
                icon: Icons.offline_bolt_rounded,
                iconColor: _effectiveLocalOnly
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
                active: _effectiveLocalOnly,
                onPressed: () {
                  setState(() {
                    _localOnly = !_localOnly;
                    _selectedIndex = 0;
                  });
                  _scheduleTagsLoad();
                  _focusNode.requestFocus();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Ligne de séparation fine et atténuée sous la barre de filtres — un
  /// `Divider` plein-largeur par défaut tranche trop avec les chips arrondis.
  Widget _buildFilterDivider(ColorScheme scheme) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: scheme.outlineVariant.withValues(alpha: 0.4),
    );
  }

  Widget _buildResults(ColorScheme scheme, List<Sound> shown, int selectedIndex) {
    if (_loading || _awaitingLocalIds) {
      return _buildLoadingSkeleton();
    }

    if (shown.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            _emptyMessage,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isBrowseMode)
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
              itemBuilder: (context, index) =>
                  _buildItem(shown[index], index, index == selectedIndex, scheme),
            ),
          ),
        ),
      ],
    );
  }

  /// Placeholders animés qui épousent la forme des items de résultat
  /// (icône + titre + sous-titre + bouton d'action) le temps du chargement.
  Widget _buildLoadingSkeleton() {
    return Skeleton(
      child: ListView.builder(
        itemExtent: _itemExtent,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 7,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const SkeletonBox(width: 24, height: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(widthFactor: index.isEven ? 0.7 : 0.5),
                    const SizedBox(height: 7),
                    SkeletonLine(
                      widthFactor: index.isEven ? 0.3 : 0.4,
                      height: 10,
                      intensity: 0.75,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const SkeletonBox(
                width: _actionButtonSize,
                height: _actionButtonSize,
                shape: BoxShape.circle,
                intensity: 0.8,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItem(Sound sound, int index, bool isSelected, ColorScheme scheme) {
    final onAir = _isMusicPicker && _isMusicOnAir(sound);
    final queued = _isMusicPicker && _isMusicQueued(sound);
    final onPad = _isPadPicker && _padSoundIds.contains(sound.id);
    final inBoard = _isLibrary && _isMusicOnBoard(sound);
    final tags = _soundTags[sound.id] ?? const <TagItem>[];

    Color? bgColor;
    if (onAir || queued) {
      bgColor = scheme.primaryContainer.withValues(alpha: isSelected ? 0.55 : 0.35);
    } else if (isSelected) {
      bgColor = scheme.primary.withValues(alpha: 0.10);
    }

    return Material(
      key: _itemKey(sound.id),
      color: bgColor ?? Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() => _selectedIndex = index);
          switch (widget.mode) {
            case QuickSearchMode():
              unawaited(_previewSound(sound));
            case MusicPickerMode():
              unawaited(_enqueueMusic(sound));
            case PadPickerMode():
              unawaited(_togglePadSound(sound));
            case LibraryMode():
              unawaited(_prepareAndClose(sound));
            case ManageMode():
              unawaited(_handleManageTap(sound));
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(_typeIcon(sound.type), color: scheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hoveredIndex = index),
                  onExit: (_) {
                    if (_hoveredIndex == index) {
                      setState(() => _hoveredIndex = null);
                    }
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ScrollingTextSpan(
                        animate: isSelected || _hoveredIndex == index,
                        span: buildHighlightedSpan(
                          sound.displayName ?? sound.title,
                          _highlightTokens,
                        ),
                      ),
                      _buildSubtitle(sound, scheme,
                          onAir: onAir, queued: queued, inBoard: inBoard),
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        _buildTagRow(scheme, tags),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildTrailing(sound, scheme,
                  onAir: onAir, queued: queued, onPad: onPad, inBoard: inBoard),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitle(
    Sound sound,
    ColorScheme scheme, {
    required bool onAir,
    required bool queued,
    required bool inBoard,
  }) {
    if (_isMusicPicker) {
      final onBoard = _isMusicOnBoard(sound);
      final label = onAir
          ? 'À l\'antenne'
          : queued
          ? 'En file de passage'
          : onBoard
          ? 'Pad sur la scène'
          : null;
      if (label == null) return const SizedBox.shrink();
      return Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: onAir || queued ? scheme.primary : scheme.onSurfaceVariant,
          fontWeight: onAir || queued ? FontWeight.w600 : FontWeight.normal,
        ),
      );
    }

    return Row(
      children: [
        Text(
          _typeLabel(sound.type),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        if (_isLibrary && inBoard) ...[
          const SizedBox(width: 6),
          Text(
            '· sur le plateau',
            style: TextStyle(
              fontSize: 12,
              color: scheme.primary.withValues(alpha: 0.8),
            ),
          ),
        ],
        if (_isQuickSearch && _localIds != null && !_isLocal(sound)) ...[
          const SizedBox(width: 6),
          Icon(
            Icons.cloud_outlined,
            size: 13,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ],
      ],
    );
  }

  Widget _buildTrailing(
    Sound sound,
    ColorScheme scheme, {
    required bool onAir,
    required bool queued,
    required bool onPad,
    required bool inBoard,
  }) {
    switch (widget.mode) {
      case QuickSearchMode():
        final fav = sound.isFavorite;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (fav) ...[
              SizedBox(
                width: _actionButtonSize,
                height: _actionButtonSize,
                child: Icon(Icons.star_rounded, size: 18, color: scheme.primary),
              ),
              const SizedBox(width: 4),
            ],
            _roundIconButton(
              scheme: scheme,
              icon: sound.type == SoundType.music
                  ? Icons.playlist_add_rounded
                  : Icons.layers_rounded,
              iconColor: scheme.primary,
              onPressed: () => unawaited(_prepareAndClose(sound)),
            ),
          ],
        );

      case MusicPickerMode():
        if (onAir || queued) {
          return SizedBox(
            width: _actionButtonSize,
            height: _actionButtonSize,
            child: Icon(
              onAir ? Icons.sensors_rounded : Icons.check_rounded,
              size: 18,
              color: scheme.primary,
            ),
          );
        }
        return const SizedBox.shrink();

      case PadPickerMode():
        final isAdding = _addingSoundIds.contains(sound.id);
        final isRemoving = _removingSoundIds.contains(sound.id);
        if (isAdding || isRemoving) {
          return SizedBox(
            width: _actionButtonSize,
            height: _actionButtonSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          );
        }
        return SizedBox(
          width: _actionButtonSize,
          height: _actionButtonSize,
          child: Icon(
            onPad ? Icons.check_rounded : Icons.add_rounded,
            color: onPad ? scheme.primary : scheme.onSurfaceVariant,
          ),
        );

      case LibraryMode():
        return _roundIconButton(
          scheme: scheme,
          icon: sound.type == SoundType.music
              ? Icons.playlist_add_rounded
              : Icons.layers_rounded,
          iconColor: inBoard ? scheme.primary : scheme.onSurfaceVariant,
          onPressed: () => unawaited(_prepareAndClose(sound)),
        );

      case ManageMode():
        final isPlaying = widget.notifier.libraryPreviewIsPlaying(sound.id);
        return Tooltip(
          message: isPlaying
              ? 'Pause'
              : 'Aperçu depuis le point d\'entrée',
          child: _roundIconButton(
            scheme: scheme,
            icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            iconColor: scheme.primary,
            onPressed: () => unawaited(_toggleLibraryPreview(sound)),
          ),
        );
    }
  }

  Widget _buildHints(ColorScheme scheme, bool hasResults) {
    if (!hasResults) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Text(
        _hintsText,
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
    );
  }

  // ── Affichage des tags ────────────────────────────────────────────────────

  Color? _categoryColor(int categoryId) {
    for (final group in _tagCatalog) {
      if (group.category.id == categoryId) return Color(group.category.color);
    }
    return null;
  }

  Widget _buildTagRow(ColorScheme scheme, List<TagItem> tags) {
    final visible = tags.take(_maxVisibleTags).toList();
    final overflow = tags.length - visible.length;
    return Row(
      children: [
        for (final tag in visible) ...[
          _buildTagChip(scheme, tag),
          const SizedBox(width: 4),
        ],
        if (overflow > 0)
          Text(
            '+$overflow',
            style: TextStyle(
              fontSize: 10,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
      ],
    );
  }

  Widget _buildTagChip(ColorScheme scheme, TagItem tag) {
    final color = _categoryColor(tag.categoryId);
    final matchingTokens = _highlightTokens
        .where((t) => tag.normalizedName.contains(t))
        .toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color?.withAlpha(24),
        borderRadius: BorderRadius.circular(4),
        border: color == null ? null : Border.all(color: color),
      ),
      child: Text.rich(
        buildHighlightedSpan(tag.name, matchingTokens),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10, color: color ?? scheme.onSurfaceVariant),
      ),
    );
  }

  // ── Bouton icône rond partagé ─────────────────────────────────────────────

  Widget _roundIconButton({
    required ColorScheme scheme,
    required IconData icon,
    required VoidCallback? onPressed,
    required Color iconColor,
    bool active = false,
  }) {
    return SizedBox(
      width: _actionButtonSize,
      height: _actionButtonSize,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: active
              ? scheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
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

  IconData _typeIcon(SoundType? type) =>
      type?.icon ?? Icons.help_outline_rounded;

  String _typeLabel(SoundType? type) => type?.label ?? 'Non classé';
}
