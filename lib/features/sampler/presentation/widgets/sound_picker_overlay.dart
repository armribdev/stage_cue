import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/skeleton.dart';
import '../../../../core/utils/app_snackbar.dart';
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
  /// Filtre de type pré-appliqué (Ctrl+G/H/J) — modifiable ensuite via les chips.
  final SoundType? initialTypeFilter;

  const QuickSearchMode({this.initialTypeFilter});
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

/// Sélecteur de variante d'un multipad : choisir précisément quel son parmi
/// ceux déjà assignés au pad va être joué. Liste courte et déjà connue → pas
/// de recherche ni de filtres, contrairement aux autres modes.
final class PadVariantMode extends SoundPickerMode {
  final PadItem padItem;

  const PadVariantMode({required this.padItem});
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

  /// Ouvre les réglages sur la section Drive pour renouveler une session Google
  /// expirée. `null` si l'appelant n'a pas de route vers les réglages (l'échec
  /// s'affiche alors sans bouton « Reconnecter »).
  final VoidCallback? onReconnect;

  const SoundPickerOverlay._({
    required this.notifier,
    required this.mode,
    bool isFullPage = false,
    this.onReconnect,
  }) : _isFullPage = isFullPage;

  static bool _isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600;

  /// Recherche-éclair (Ctrl+F) — renvoie le pad à surligner pour les bruitages.
  static Future<QuickSearchPrepareResult?> show(
    BuildContext context, {
    required SamplerNotifier notifier,
    SoundType? initialTypeFilter,
    VoidCallback? onReconnect,
  }) {
    final mobile = _isMobile(context);
    final w = SoundPickerOverlay._(
        notifier: notifier,
        mode: QuickSearchMode(initialTypeFilter: initialTypeFilter),
        isFullPage: mobile,
        onReconnect: onReconnect);
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
    VoidCallback? onReconnect,
  }) {
    final mobile = _isMobile(context);
    final w = SoundPickerOverlay._(
        notifier: notifier,
        mode: const LibraryMode(),
        isFullPage: mobile,
        onReconnect: onReconnect);
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
    VoidCallback? onReconnect,
  }) {
    final mobile = _isMobile(context);
    final w = SoundPickerOverlay._(
        notifier: notifier,
        mode: ManageMode(onTap: onTap),
        isFullPage: mobile,
        onReconnect: onReconnect);
    return mobile ? _showPage<void>(context, w) : _showDialog<void>(context, w);
  }

  /// Variante d'un multipad — liste ses sons déjà assignés, sans recherche
  /// ni filtres, pour en déclencher un précisément.
  static Future<void> showForPadVariant(
    BuildContext context, {
    required SamplerNotifier notifier,
    required PadItem padItem,
  }) {
    final mobile = _isMobile(context);
    final w = SoundPickerOverlay._(
      notifier: notifier,
      mode: PadVariantMode(padItem: padItem),
      isFullPage: mobile,
    );
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

  // Messenger local : en mode dialog l'overlay n'est pas sous le Scaffold de
  // l'écran, donc un snackbar affiché sur le messenger racine serait rendu
  // derrière la barrière modale et ne se fermerait pas proprement. Ce messenger
  // dédié affiche les snackbars au-dessus de l'overlay et les auto-dismisse.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  // Clé par INDICE de liste (jamais par sound.id) : un multipad peut référencer
  // le même son dans plusieurs variantes, et deux items partageant la même clé
  // déclencheraient « Duplicate GlobalKey ». L'indice est unique dans la liste.
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
  bool get _isPadVariant => widget.mode is PadVariantMode;

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

  PadVariantMode? get _padVariantMode =>
      widget.mode is PadVariantMode ? widget.mode as PadVariantMode : null;

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
    PadVariantMode() => '',
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
    PadVariantMode() => '↑↓ sélectionner    ↵/tap jouer',
  };

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _onSearchKey);
    widget.notifier.addListener(_onNotifierChanged);
    if (_isPadPicker) _typeFilter = SoundType.soundEffect;
    if (_isQuickSearch) {
      _typeFilter = (widget.mode as QuickSearchMode).initialTypeFilter;
    }
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
      if (_padVariantMode case final mode?) _all = mode.padItem.pad.sounds;
    });
    _scheduleTagsLoad();
  }

  Future<void> _load() async {
    // Variante d'un multipad : liste déjà connue (sons du pad), pas besoin
    // de charger toute la bibliothèque ni le scope d'un board.
    if (_padVariantMode case final mode?) {
      final tagCatalog = await widget.notifier.loadTagCatalog();
      if (!mounted) return;
      setState(() {
        _all = mode.padItem.pad.sounds;
        _tagCatalog = tagCatalog;
        _loading = false;
      });
      _scheduleTagsLoad();
      return;
    }
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

  /// Vide le champ de recherche — déclenché par la croix, donc immédiat
  /// (pas de débounce à attendre).
  void _clearQuery() {
    _searchDebounce?.cancel();
    _controller.clear();
    setState(() {
      _query = '';
      _selectedIndex = 0;
    });
    unawaited(_runTagSearch(''));
    _scheduleTagsLoad();
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
    // Variante d'un multipad : ordre figé sur les slots du pad (l'index doit
    // rester aligné avec `pad.sounds` pour `playPadSoundAtIndex`) — jamais
    // retrié par score/favori/récence.
    if (_isPadVariant) return _all;
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

    final policy = delta < 0
        ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
        : ScrollPositionAlignmentPolicy.keepVisibleAtEnd;
    final ctx = _itemKey(next).currentContext;

    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: Duration.zero, alignmentPolicy: policy);
      setState(() => _selectedIndex = next);
      return;
    }

    _preScrollToIndex(next, delta);
    setState(() => _selectedIndex = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final lateCtx = _itemKey(next).currentContext;
      if (lateCtx == null) return;
      Scrollable.ensureVisible(lateCtx, duration: Duration.zero, alignmentPolicy: policy);
    });
  }

  GlobalKey _itemKey(int index) =>
      _itemKeys.putIfAbsent(index, GlobalKey.new);

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
    // Pas de champ de recherche pour intercepter Entrée dans ce mode.
    if (_isPadVariant && event.logicalKey == LogicalKeyboardKey.enter) {
      unawaited(_onSubmit());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _onSubmit() async {
    final shown = _shownResults(_results);
    if (shown.isEmpty) return;
    final index = _clampSelectedIndex(shown.length);
    final sound = shown[index];
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
      case PadVariantMode(padItem: final padItem):
        _playPadVariant(padItem, index);
    }
  }

  // QuickSearch
  Future<void> _previewSound(Sound sound) async {
    final ok = await widget.notifier.previewSound(sound.id);
    if (!mounted || ok) return;
    _showPreviewFailureSnackBar();
  }

  Future<void> _toggleLibraryPreview(Sound sound) async {
    final ok = await widget.notifier.toggleLibraryPreview(sound.id);
    if (!mounted || ok) return;
    _showPreviewFailureSnackBar();
  }

  /// Échec de pré-écoute/mise en file. Consomme d'abord l'erreur musique
  /// spécifique (format, introuvable…) si elle existe — l'overlay est la route
  /// active, donc [SamplerScreen] la laisse pour lui plutôt que de l'afficher
  /// derrière la barrière modale. À défaut, message générique distinguant token
  /// expiré et simple indisponibilité réseau.
  void _showPreviewFailureSnackBar() {
    final expired = widget.notifier.driveSessionExpired;
    final specific = widget.notifier.consumeLastMusicPlaybackError();
    final message = specific ??
        (expired
            ? 'Session Google expirée — touchez « Reconnecter »'
            : 'Son indisponible — vérifiez la connexion');
    _showLocalSnackBar(message, withReconnect: expired);
  }

  /// Affiche sur le messenger **local** (au-dessus du dialog) plutôt que via
  /// `.of(context)`, qui remonterait au messenger racine rendu derrière la
  /// barrière modale — d'où un snackbar qui « reste » sans se fermer. Remplace
  /// le courant plutôt que d'empiler.
  void _showLocalSnackBar(String message, {bool withReconnect = false}) {
    final onReconnect = widget.onReconnect;
    final messenger = _messengerKey.currentState ?? ScaffoldMessenger.of(context);
    AppSnackBar.showOn(
      messenger,
      message,
      action: (withReconnect && onReconnect != null)
          ? SnackBarAction(label: 'Reconnecter', onPressed: onReconnect)
          : null,
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
    final padItem = await widget.notifier.enqueueMusicBySoundId(sound.id);
    if (!mounted || padItem != null) return;
    // Échec : surfacer le message ici (route active) plutôt que de le laisser à
    // [SamplerScreen], qui le dessinerait derrière l'overlay sans le fermer.
    _showPreviewFailureSnackBar();
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

  // Pad variant picker
  void _playPadVariant(PadItem padItem, int index) {
    Navigator.of(context).pop();
    unawaited(widget.notifier.playPadSoundAtIndex(padItem, index));
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

    final results = _buildResultsFocusable(scheme, shown, selectedIndex);

    // TextFieldTapRegion : couvre tout l'overlay pour qu'aucun tap interne
    // (filtres, items, boutons) ne compte comme un tap "en dehors" du champ
    // de recherche — ce qui le déconcentrerait automatiquement (comportement
    // par défaut d'EditableText.onTapOutside). Le champ garde ainsi le focus
    // en continu, quoi que l'utilisateur clique dans l'overlay.
    if (widget._isFullPage) {
      return ScaffoldMessenger(
        key: _messengerKey,
        child: CallbackShortcuts(
          bindings: shortcuts,
          child: Scaffold(
            body: SafeArea(
              child: TextFieldTapRegion(
                child: Column(
                  children: [
                    if (!_isPadVariant) ...[
                      _buildSearchField(scheme),
                      _buildTypeFilters(scheme),
                      _buildFilterDivider(scheme),
                    ],
                    Expanded(child: results),
                    _buildHints(scheme, shown.isNotEmpty),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Scaffold transparent : support de rendu pour les snackbars du messenger
    // local, sans masquer la barrière modale (fond transparent, zone autour de
    // la carte non hit-testable).
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: CallbackShortcuts(
          bindings: shortcuts,
          child: Stack(
            children: [
              // Le Scaffold transparent (support du messenger local) recouvre la
              // barrière modale de showGeneralDialog, qui ne reçoit donc plus les
              // taps : on rétablit ici « tap en dehors de la carte = fermer ».
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              Align(
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
                      maxWidth:
                          (mq.size.width - 24).clamp(320.0, _overlayMaxWidth),
                      maxHeight: mq.size.height * 0.7,
                    ),
                    // Absorbe les taps sur la carte pour qu'ils n'atteignent pas
                    // le détecteur de fermeture en dessous. Les enfants
                    // interactifs (champ, boutons) gagnent leur tap normalement
                    // (recognizers ajoutés depuis les feuilles → prioritaires) ;
                    // seuls les taps sur zone vide de la carte sont absorbés.
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: Material(
                        color: scheme.surface,
                        elevation: 8,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: TextFieldTapRegion(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!_isPadVariant) ...[
                                _buildSearchField(scheme),
                                _buildTypeFilters(scheme),
                                _buildFilterDivider(scheme),
                              ],
                              Flexible(child: results),
                              _buildHints(scheme, shown.isNotEmpty),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sans champ de recherche (variante de pad), on rattache [_focusNode] ici
  /// pour garder la navigation clavier (↑↓, Entrée).
  Widget _buildResultsFocusable(
    ColorScheme scheme,
    List<Sound> shown,
    int selectedIndex,
  ) {
    final results = _buildResults(scheme, shown, selectedIndex);
    if (!_isPadVariant) return results;
    return Focus(focusNode: _focusNode, autofocus: true, child: results);
  }

  Widget _buildSearchField(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
      child: Row(
        children: [
          // Page pleine (mobile) : flèche retour, seul moyen de fermer
          // l'overlay puisqu'il n'y a pas de fond à taper.
          if (widget._isFullPage) ...[
            ExcludeFocus(
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
          ],
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
                suffixIcon: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => _controller.text.isEmpty
                      ? const SizedBox.shrink()
                      : ExcludeFocus(
                          child: IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: _clearQuery,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                ),
                suffixIconConstraints: const BoxConstraints(maxHeight: 24, maxWidth: 24),
              ),
              style: const TextStyle(fontSize: 17),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeFilters(ColorScheme scheme) {
    // Musique : type verrouillé → pas de barre de filtres.
    if (_lockedTypeFilter != null) return const SizedBox.shrink();

    // "Tous" uniquement pour QuickSearch, Library et Manage
    final segments = <(String, SoundType?, IconData)>[
      if (_isQuickSearch || _isLibrary || _isManage)
        ('Tous', null, Icons.apps_rounded),
      (SoundType.soundEffect.label, SoundType.soundEffect, SoundType.soundEffect.icon),
      (SoundType.music.label, SoundType.music, SoundType.music.icon),
      (SoundType.ambiance.label, SoundType.ambiance, SoundType.ambiance.icon),
    ];

    Widget segment(String label, SoundType? type, IconData icon, bool isLast) {
      final selected = _effectiveTypeFilter == type;
      final colors = type?.avatarColors(scheme) ??
          (background: scheme.primaryContainer, foreground: scheme.onPrimaryContainer);
      return InkWell(
        canRequestFocus: false,
        onTap: () {
          setState(() {
            _typeFilter = type;
            _selectedIndex = 0;
          });
          _scheduleTagsLoad();
        },
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colors.background : Colors.transparent,
            border: isLast
                ? null
                : Border(
                    right: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? colors.foreground : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? colors.foreground : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final segmentedControl = Material(
      color: Colors.transparent,
      child: Container(
        height: 32,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: AppRadius.radiusMd,
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < segments.length; i++)
              segment(segments[i].$1, segments[i].$2, segments[i].$3,
                  i == segments.length - 1),
          ],
        ),
      ),
    );

    final trailingActions = <Widget>[
      if (_isQuickSearch) ...[
        Container(
          width: 1,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        ),
        _roundIconButton(
          scheme: scheme,
          icon: _favoritesOnly ? Icons.star_rounded : Icons.star_border_rounded,
          iconColor: _favoritesOnly ? scheme.primary : scheme.onSurfaceVariant,
          active: _favoritesOnly,
          flat: true,
          onPressed: () {
            setState(() {
              _favoritesOnly = !_favoritesOnly;
              _selectedIndex = 0;
            });
            _scheduleTagsLoad();
          },
        ),
        _roundIconButton(
          scheme: scheme,
          icon: Icons.offline_bolt_rounded,
          iconColor: _effectiveLocalOnly ? scheme.primary : scheme.onSurfaceVariant,
          active: _effectiveLocalOnly,
          flat: true,
          onPressed: () {
            setState(() {
              _localOnly = !_localOnly;
              _selectedIndex = 0;
            });
            _scheduleTagsLoad();
          },
        ),
      ],
    ];

    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
        // Groupe pilule + actions centré comme un seul bloc ; passe en scroll
        // horizontal (démarrant à gauche) si la largeur manque. Le
        // ConstrainedBox(minWidth) force le Row à occuper toute la largeur
        // disponible quand le contenu est plus étroit, pour que le
        // MainAxisAlignment.center ait un effet visible.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [segmentedControl, ...trailingActions],
              ),
            ),
          ),
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
    final variantMode = _padVariantMode;
    // Polyphonie : plusieurs variantes du pad peuvent jouer en même temps, donc
    // on regarde l'état du lecteur de CE slot plutôt que le seul index le plus
    // récemment déclenché (`currentSoundIndex`, qui ne reflète que le dernier).
    final isCurrentVariant = variantMode != null &&
        index < variantMode.padItem.slots.length &&
        (variantMode.padItem.slots[index].player?.isPlaying ?? false);
    final tags = _soundTags[sound.id] ?? const <TagItem>[];

    Color? bgColor;
    if (onAir || queued || isCurrentVariant) {
      bgColor = scheme.primaryContainer.withValues(alpha: isSelected ? 0.55 : 0.35);
    } else if (isSelected) {
      bgColor = scheme.primary.withValues(alpha: 0.10);
    }

    return Material(
      key: _itemKey(index),
      color: bgColor ?? Colors.transparent,
      child: InkWell(
        canRequestFocus: false,
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
            case PadVariantMode(padItem: final padItem):
              _playPadVariant(padItem, index);
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
                          onAir: onAir,
                          queued: queued,
                          inBoard: inBoard,
                          isCurrentVariant: isCurrentVariant),
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
                  onAir: onAir,
                  queued: queued,
                  onPad: onPad,
                  inBoard: inBoard,
                  isCurrentVariant: isCurrentVariant,
                  index: index),
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
    required bool isCurrentVariant,
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

    if (isCurrentVariant) {
      return Text(
        'En cours de lecture',
        style: TextStyle(
          fontSize: 12,
          color: scheme.primary,
          fontWeight: FontWeight.w600,
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
    required bool isCurrentVariant,
    required int index,
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

      case PadVariantMode():
        if (!isCurrentVariant) return const SizedBox.shrink();
        return SizedBox(
          width: _actionButtonSize,
          height: _actionButtonSize,
          child: Icon(Icons.graphic_eq_rounded, color: scheme.primary),
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
    // Désactive tout fond (actif ou survol) — seule la couleur d'icône
    // porte l'état. Pour les toggles serrés type favoris/hors-ligne.
    bool flat = false,
  }) {
    // ExcludeFocus : empêche ce bouton de voler le focus au champ de
    // recherche (sinon Flutter le regagnerait en sélectionnant tout le
    // texte, comme un Tab desktop).
    return ExcludeFocus(
      child: SizedBox(
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
            backgroundColor: !flat && active
                ? scheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            hoverColor: flat
                ? Colors.transparent
                : scheme.onSurface.withValues(alpha: 0.08),
            foregroundColor: iconColor,
          ),
          constraints: const BoxConstraints.tightFor(
            width: _actionButtonSize,
            height: _actionButtonSize,
          ),
        ),
      ),
    );
  }

  IconData _typeIcon(SoundType? type) =>
      type?.icon ?? Icons.help_outline_rounded;

  String _typeLabel(SoundType? type) => type?.label ?? 'Non classé';
}
