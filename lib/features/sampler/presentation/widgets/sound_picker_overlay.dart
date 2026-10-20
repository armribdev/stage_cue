import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/skeleton.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/string_utils.dart';
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';
import '../providers/sampler_provider.dart';
import '../providers/sound_search_index.dart';
import '../screens/sound_details_screen.dart';
import '../utils/quick_search_prepare.dart';
import '../utils/sound_type_ui.dart';
import 'app_form_dialog.dart';
import 'scrolling_text.dart';
import 'sound_edit_form.dart';
import 'sound_picker/sound_picker_mode.dart';

export 'sound_picker/sound_picker_mode.dart';

part 'sound_picker/sound_picker_search.dart';
part 'sound_picker/sound_picker_navigation.dart';
part 'sound_picker/sound_picker_actions.dart';
part 'sound_picker/sound_picker_queue.dart';
part 'sound_picker/sound_picker_layout.dart';
part 'sound_picker/sound_picker_results.dart';
part 'sound_picker/sound_picker_parts.dart';

// ── Widget principal ──────────────────────────────────────────────────────────

/// Overlay flottant unifié pour chercher et sélectionner un son.
///
/// Remplace [QuickSearchMode] (Ctrl+F), [MusicPickerMode] (sélecteur musique),
/// [AmbiancePickerMode] (sélecteur d'ambiance de la régie),
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

  /// Sélecteur de musique — joue maintenant ([playNow]) ou met en file.
  static Future<void> showForMusic(
    BuildContext context, {
    required SamplerNotifier notifier,
    bool playNow = false,
  }) {
    final mobile = _isMobile(context);
    final w = SoundPickerOverlay._(
        notifier: notifier,
        mode: MusicPickerMode(playNow: playNow),
        isFullPage: mobile);
    return mobile ? _showPage<void>(context, w) : _showDialog<void>(context, w);
  }

  /// Sélecteur d'ambiance — lance immédiatement l'ambiance choisie.
  static Future<void> showForAmbiance(
    BuildContext context, {
    required SamplerNotifier notifier,
  }) {
    final mobile = _isMobile(context);
    final w = SoundPickerOverlay._(
        notifier: notifier,
        mode: const AmbiancePickerMode(),
        isFullPage: mobile);
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

  /// Gestion de bibliothèque — toujours en page plein écran (jamais en modale) :
  /// le volet scindé de l'édition a besoin de la place d'un écran entier.
  static Future<void> showForManage(
    BuildContext context, {
    required SamplerNotifier notifier,
    required SoundRepository repository,
    VoidCallback? onReconnect,
  }) {
    final w = SoundPickerOverlay._(
        notifier: notifier,
        mode: ManageMode(repository: repository),
        isFullPage: true,
        onReconnect: onReconnect);
    return _showPage<void>(context, w);
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

// Dimensions partagées entre le `State` et ses extensions (`part`) : une
// extension ne peut pas référencer un membre statique du `State` sans le qualifier.
const _itemExtent = 72.0;
const _actionButtonSize = 30.0;
const _overlayMaxWidth = 720.0;
const _splitMaxWidth = 1280.0;
const _maxVisibleTags = 3;

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
  // Chargés en bloc avec l'index de recherche : la liste peut compter des
  // centaines de résultats, et une requête par son ferait ramer chaque frappe.
  Map<int, List<TagItem>> _soundTags = const {};

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

  // ── Mode gestion (volet d'édition) ────────────────────────────────────────
  Sound? _editingSound;
  bool _editDirty = false;
  final _editController = SoundEditFormController();

  /// File de traitement : ne montre que les sons jamais enregistrés depuis la
  /// bibliothèque (`Sound.isProcessed == false`). Mode gestion uniquement.
  bool _unprocessedOnly = false;

  /// En file de traitement (vue scindée), joue le son ouvert depuis son point
  /// d'entrée : trier se fait à l'oreille. Désactivable depuis la barre.
  bool _autoPreview = true;

  // ── État du sélecteur de pad ──────────────────────────────────────────────
  Set<int> _padSoundIds = const {};
  final Set<int> _addingSoundIds = {};
  final Set<int> _removingSoundIds = {};

  // ── Helpers de mode ───────────────────────────────────────────────────────

  bool get _isQuickSearch => widget.mode is QuickSearchMode;
  bool get _isMusicPicker => widget.mode is MusicPickerMode;
  bool get _isAmbiancePicker => widget.mode is AmbiancePickerMode;
  bool get _isPadPicker => widget.mode is PadPickerMode;
  bool get _isLibrary => widget.mode is LibraryMode;
  bool get _isManage => widget.mode is ManageMode;

  /// Gestion en volet scindé (liste + édition) : tablette et desktop, mêmes
  /// seuil de largeur que le reste des sélecteurs.
  bool get _isSplitLayout =>
      _isManage && !SoundPickerOverlay._isMobile(context);
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

  /// Type verrouillé pour les sélecteurs de musique et d'ambiance.
  SoundType? get _lockedTypeFilter => _isMusicPicker
      ? SoundType.music
      : _isAmbiancePicker
      ? SoundType.ambiance
      : null;
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
    AmbiancePickerMode() => 'Chercher une ambiance…',
    PadPickerMode() || LibraryMode() || ManageMode() => 'Chercher un son…',
    PadVariantMode() => '',
  };

  /// Sons de toute la bibliothèque encore à traiter (indépendant des filtres et
  /// de la recherche : c'est le « reste à faire » global).
  int get _unprocessedCount => _all.where((s) => !s.isProcessed).length;

  String get _emptyMessage {
    if (_isManage && _unprocessedOnly && _query.isEmpty) {
      return 'Tous les sons sont traités';
    }
    if (_isQuickSearch) {
      if (_effectiveLocalOnly) return 'Aucun son disponible hors-ligne';
      if (_query.isEmpty && !_favoritesOnly) {
        return 'Tapez pour chercher vos sons';
      }
    }
    return 'Aucun son';
  }

  String get _hintsText => switch (widget.mode) {
    QuickSearchMode() =>
      '↑↓ sélectionner    ↵ jouer    ⌘/Ctrl+↵ préparer    tap audition',
    MusicPickerMode(playNow: true) => '↑↓ sélectionner    ↵/tap jouer',
    MusicPickerMode() =>
      '↑↓ sélectionner    ↵/tap ajouter à la file',
    AmbiancePickerMode() => '↑↓ sélectionner    ↵/tap lancer',
    PadPickerMode() =>
      '↑↓ sélectionner    ↵ ajouter/retirer',
    LibraryMode() =>
      '↑↓ sélectionner    ↵/tap éditer',
    ManageMode() => _unprocessedOnly && _isSplitLayout
        ? '↑↓ sélectionner    ↵/tap éditer    ⌘/Ctrl+↵ valider et suivant    '
            '▶ aperçu depuis le point d\'entrée'
        : '↑↓ sélectionner    ↵/tap éditer    ▶ aperçu depuis le point d\'entrée',
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
  }

  /// Ouverture : l'instantané de l'index est adopté SYNCHRONEMENT s'il existe,
  /// puis rafraîchi en tâche de fond. Sur une bibliothèque d'un millier de sons,
  /// c'est la différence entre un écran de chargement à chaque Ctrl+F et une
  /// liste déjà là — ce qui compte surtout en spectacle.
  void _load() {
    // Variante d'un multipad : liste déjà connue (sons du pad), pas besoin
    // de charger toute la bibliothèque ni le scope d'un board.
    if (_padVariantMode case final mode?) {
      _all = mode.padItem.pad.sounds;
      // Liste courte et déjà en main : jamais d'attente. Les tags et le
      // catalogue viennent de l'index s'il est chaud, et se complètent après
      // coup sinon — ils n'empêchent pas de déclencher une variante.
      _loading = false;
      final snapshot = widget.notifier.searchSnapshot;
      if (snapshot != null) _adoptSnapshot(snapshot);
      // `ensure` et non `refresh` : rien à revalider ici (les sons viennent du
      // pad), et ce sélecteur s'ouvre en pleine représentation.
      unawaited(_adoptRefreshedSnapshot(refresh: false));
      return;
    }

    final snapshot = widget.notifier.searchSnapshot;
    if (snapshot != null) {
      _adoptSnapshot(snapshot);
      _loading = false;
    }
    if (_isPadPicker) _syncPadSoundIds();
    unawaited(_adoptRefreshedSnapshot());
    unawaited(_loadBoardScope());
  }

  Future<void> _adoptRefreshedSnapshot({bool refresh = true}) async {
    final SoundSearchSnapshot snapshot;
    try {
      snapshot = refresh
          ? await widget.notifier.refreshSearchIndex()
          : await widget.notifier.ensureSearchIndex();
    } catch (_) {
      // L'instantané précédent (s'il existe) reste affiché ; sinon la liste
      // vide et son message prennent le relais plutôt qu'un skeleton figé.
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!mounted) return;
    setState(() {
      _adoptSnapshot(snapshot);
      _loading = false;
      if (_isPadPicker) _syncPadSoundIds();
    });
  }

  /// Recopie l'instantané dans l'état local. Le mode variante garde sa propre
  /// liste (les slots du pad), seuls les tags et le catalogue l'intéressent.
  void _adoptSnapshot(SoundSearchSnapshot snapshot) {
    if (!_isPadVariant) _all = snapshot.sounds;
    _tagCatalog = snapshot.tagCatalog;
    _soundTags = snapshot.tagsBySound;
    if (_isQuickSearch) _localIds = snapshot.locallyAvailableSoundIds;
  }

  /// Scope d'un board Drive : sons visibles par sa bibliothèque (vue partagée).
  Future<void> _loadBoardScope() async {
    final scopeLibraryId = _boardLibraryId;
    if (scopeLibraryId == null || _isManage) return;
    final scopeIds =
        await widget.notifier.getSoundIdsVisibleToLibrary(scopeLibraryId);
    if (!mounted) return;
    setState(() => _scopeIds = scopeIds);
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
    _focusNode.dispose();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
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
      // maybePop (et non pop) : respecte le PopScope du mode gestion, qui
      // demande confirmation s'il reste des modifications non enregistrées.
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          unawaited(Navigator.of(context).maybePop()),
      if (_isQuickSearch) ...<ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            unawaited(_prepareSelectedAndClose()),
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
            unawaited(_prepareSelectedAndClose()),
      },
      // Valider le son ouvert depuis la recherche, sans quitter le clavier.
      if (_isSplitLayout) ...<ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            unawaited(_editController.save()),
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
            unawaited(_editController.save()),
      },
    };

    final results = _buildResultsFocusable(scheme, shown, selectedIndex);

    // TextFieldTapRegion : couvre tout l'overlay pour qu'aucun tap interne
    // (filtres, items, boutons) ne compte comme un tap "en dehors" du champ
    // de recherche — ce qui le déconcentrerait automatiquement (comportement
    // par défaut d'EditableText.onTapOutside). Le champ garde ainsi le focus
    // en continu, quoi que l'utilisateur clique dans l'overlay.
    if (widget._isFullPage) {
      final listPane = TextFieldTapRegion(
        child: Column(
          children: [
            if (!_isPadVariant) ...[
              _buildSearchField(scheme),
              _buildTypeFilters(scheme),
              if (_isManage) _buildQueueBar(scheme),
              _buildFilterDivider(scheme),
            ],
            Expanded(child: results),
            _buildHints(scheme, shown.isNotEmpty),
          ],
        ),
      );
      final split = _isSplitLayout;
      return ScaffoldMessenger(
        key: _messengerKey,
        child: PopScope(
          canPop: !(split && _editDirty),
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_confirmDiscardAndClose());
          },
          child: CallbackShortcuts(
            bindings: shortcuts,
            child: Scaffold(
              body: SafeArea(
                child: split ? _buildSplit(scheme, listPane, shown) : listPane,
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
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.radiusLg,
                          side: AppElevation.border(scheme),
                        ),
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
}
