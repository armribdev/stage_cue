import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/sampler_provider.dart';
import '../../data/repositories/library_repository.dart'
    show LibraryRepositoryDriveSession;
import '../widgets/pad_item.dart' show PadCard;
import '../widgets/dashed_slot_frame.dart';
import '../widgets/threshold_draggable.dart';
import '../widgets/music_preview_panel.dart';
import '../widgets/music_picker_sheet.dart';
import '../widgets/quick_search_overlay.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/pad_download_sheet.dart';
import '../widgets/sampler_screen_chrome.dart';
import '../widgets/section_context_anchor.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/sound_board.dart';
import '../../../../core/app/app_services.dart';
import '../../../../core/sync/google_oauth_config.dart';
import '../../../../core/sync/google_oauth_setup_dialog.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/database/database.dart' as db;
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/layout_utils.dart';
import 'settings_screen.dart';
import 'pad_details_screen.dart';
import 'sound_library_manage_screen.dart';

part 'sampler_screen/sampler_screen_intents.dart';
part 'sampler_screen/sampler_screen_boards.dart';
part 'sampler_screen/sampler_screen_navigation.dart';
part 'sampler_screen/sampler_screen_pad_layout.dart';
part 'sampler_screen/sampler_screen_grid.dart';
part 'sampler_screen/sampler_screen_pad_actions.dart';
part 'sampler_screen/sampler_screen_content.dart';

/// Écran principal du sampler
class SamplerScreen extends StatefulWidget {
  final AppServices services;

  /// État plein écran Windows courant — `null` si la fonctionnalité n'est
  /// pas disponible sur cette plateforme (masque les entrées de menu).
  final bool? isWindowsFullScreen;
  final VoidCallback? onToggleWindowsFullScreen;

  /// Ferme complètement l'application — proposé dans le menu uniquement en
  /// plein écran, la fenêtre n'ayant alors plus de bouton de fermeture natif.
  final VoidCallback? onQuitApp;

  const SamplerScreen({
    super.key,
    required this.services,
    this.isWindowsFullScreen,
    this.onToggleWindowsFullScreen,
    this.onQuitApp,
  });

  @override
  State<SamplerScreen> createState() => _SamplerScreenState();
}

// Dimensions partagées entre le `State` et ses extensions (`part`) : une
// extension ne peut pas référencer un membre statique du `State` sans le qualifier.
const _padsGridPadding = 16.0;
const double _itemWidth = 180;
const Duration _padEmphasisDuration = Duration(milliseconds: 2200);
const double _editRowGap = 14;
const double _padScrollAlignment = 0.28;
const Duration _addSlotTransitionDuration = Duration(milliseconds: 240);

class _SamplerScreenState extends State<SamplerScreen> {
  late final SamplerNotifier _notifier;
  late final db.AppDatabase _database;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _normalGridScrollController = ScrollController();

  bool _isPerformanceMode = false;

  /// Mode classique éditable : croix de suppression, crayon et slots « + ».
  /// Verrouillé en Mode Spectacle pour éviter toute modif accidentelle — le
  /// déplacement des pads reste toutefois permis dans les deux modes.
  bool get _isEditable => !_isPerformanceMode;

  int? _draggingPadId;
  ({int rowIndex, int position})? _dropTarget;
  Offset? _lastDragGlobalOffset;

  /// Reconnexion Drive inline en cours — évite qu'un double-tap sur l'action
  /// « Reconnecter » d'un snackbar lance deux flux OAuth concurrents.
  bool _driveReconnectInFlight = false;

  /// true après la 1re frame de drag — évite de reconstruire l'arbre pendant
  /// l'accrochage du geste (sinon le Draggable est démonté et le pad reste bloqué).
  bool _editDragUiReady = false;

  /// Contexte de la grille éditable (hit-test drop). Pas de [GlobalKey] :
  /// [AnimatedSwitcher] garde l'ancien enfant au changement de board, ce qui
  /// dupliquerait une GlobalKey partagée.
  BuildContext? _editGridContext;
  double _lastGridWidth = 0;
  int? _recentlyRestoredSoundId;
  int? _highlightedPadId;
  bool _didAutoOpenCreateForCurrentEmptyState = false;
  bool _isMusicRegieAdvanced = false;
  double _musicRegieOccupiedHeight = 0;

  EdgeInsets _padsGridScrollPadding(BuildContext context) =>
      EdgeInsets.fromLTRB(
        _padsGridPadding,
        _padsGridPadding,
        _padsGridPadding,
        _padsGridPadding +
            (context.prefersDesktopUi ? 0 : _musicRegieOccupiedHeight),
      );

  @override
  void initState() {
    super.initState();
    _database = widget.services.database;
    _initializeNotifier();
    // Câbler les relances de chargement AVANT le premier `loadBoards` : si le
    // pull de lancement se règle très tôt, `initialSyncSettled` (persistant)
    // couvre la fenêtre ; sinon ces callbacks relancent le chargement mis en
    // attente par la garde anti « Scène 1 » fantôme.
    widget.services.syncController.onLibraryMerged = _onLibraryMerged;
    widget.services.autoSyncCoordinator.onInitialPullSettled = _onLibraryMerged;
    _notifier.loadBoards();
    if (isNativeDesktopPlatform()) {
      HardwareKeyboard.instance.addHandler(_handlePadHotkeyEvent);
    }
  }

  void _initializeNotifier() {
    _notifier = SamplerNotifier(
      widget.services.soundRepository,
      widget.services.loadSoundsUseCase,
      widget.services.removeSoundFromBoardUseCase,
      widget.services.libraryRepository,
      widget.services.appPreferences,
    );

    _notifier.addListener(_onStateChanged);
  }

  void _onLibraryMerged() {
    if (!mounted) return;
    // Un merge peut ajouter/retirer des centaines de sons : l'index de recherche
    // est jeté avant le rechargement, qui le reconstruira.
    _notifier.invalidateSearchIndex();
    _notifier.loadBoards();
  }

  void _onStateChanged() {
    if (!mounted) return;

    // Peek non-destructif : la décision d'afficher (et la consommation) est
    // différée au post-frame — `ModalRoute.of` dépend d'un InheritedWidget et
    // ne peut être lu pendant `initState` (ce listener tourne dès `loadBoards`).
    if (_notifier.hasPendingMusicPlaybackError) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Un overlay/dialog au-dessus (route non courante) possède le message et
        // l'affiche sur son propre messenger — le nôtre le dessinerait derrière
        // la barrière modale, sans se fermer. On le lui laisse (pas de consume).
        if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
        final musicError = _notifier.consumeLastMusicPlaybackError();
        if (musicError == null) return;
        AppSnackBar.show(
          context,
          musicError,
          action: _reconnectSnackBarAction(),
        );
      });
    }

    setState(() {});
  }

  @override
  void dispose() {
    widget.services.syncController.onLibraryMerged = null;
    widget.services.autoSyncCoordinator.onInitialPullSettled = null;
    if (isNativeDesktopPlatform()) {
      HardwareKeyboard.instance.removeHandler(_handlePadHotkeyEvent);
    }
    _normalGridScrollController.dispose();
    _notifier.removeListener(_onStateChanged);
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _notifier.state;
    final selectedBoard = state.selectedBoard;
    final boards = state.boards;
    final isBoardsLoading = state.isBoardsLoading;
    final prefersDesktopUi = context.prefersDesktopUi;

    if (!isBoardsLoading &&
        boards.isEmpty &&
        !_didAutoOpenCreateForCurrentEmptyState) {
      _didAutoOpenCreateForCurrentEmptyState = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_createBoard());
      });
    } else if (boards.isNotEmpty && _didAutoOpenCreateForCurrentEmptyState) {
      _didAutoOpenCreateForCurrentEmptyState = false;
    }

    final musicPreviewPanel = ListenableBuilder(
      listenable: _notifier,
      builder: (context, _) =>
          _buildMusicPreviewPanel(context, _notifier.state),
    );

    return Shortcuts(
      shortcuts: isNativeDesktopPlatform()
          ? const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.keyN, control: true):
                  _AddPadIntent(),
              SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                  _UndoPadIntent(),
              SingleActivator(LogicalKeyboardKey.keyF, control: true):
                  _QuickSearchIntent(),
              SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                  _QuickSearchIntent(),
              SingleActivator(LogicalKeyboardKey.escape): _StopAllIntent(),
              SingleActivator(LogicalKeyboardKey.keyG, control: true):
                  _QuickSearchFilteredIntent(SoundType.soundEffect),
              SingleActivator(LogicalKeyboardKey.keyH, control: true):
                  _QuickSearchFilteredIntent(SoundType.music),
              SingleActivator(LogicalKeyboardKey.keyJ, control: true):
                  _QuickSearchFilteredIntent(SoundType.ambiance),
            }
          : const <ShortcutActivator, Intent>{},
      child: Actions(
        actions: <Type, Action<Intent>>{
          _AddPadIntent: CallbackAction<_AddPadIntent>(
            onInvoke: (intent) {
              unawaited(_handleAddPadShortcut());
              return null;
            },
          ),
          _UndoPadIntent: CallbackAction<_UndoPadIntent>(
            onInvoke: (intent) {
              unawaited(_handleUndoShortcut());
              return null;
            },
          ),
          _QuickSearchIntent: CallbackAction<_QuickSearchIntent>(
            onInvoke: (intent) {
              unawaited(_openQuickSearch());
              return null;
            },
          ),
          _StopAllIntent: CallbackAction<_StopAllIntent>(
            onInvoke: (intent) {
              if (_notifier.hasNonMusicSoundsPlaying) {
                unawaited(HapticFeedback.heavyImpact());
                unawaited(_notifier.panicStop());
              }
              return null;
            },
          ),
          _QuickSearchFilteredIntent:
              CallbackAction<_QuickSearchFilteredIntent>(
                onInvoke: (intent) {
                  unawaited(_openQuickSearch(typeFilter: intent.type));
                  return null;
                },
              ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            key: prefersDesktopUi ? null : _scaffoldKey,
            appBar: prefersDesktopUi
                ? SamplerDesktopAppBar(
                    unprocessedCount: _notifier.unprocessedSoundCount,
                    selectedBoard: selectedBoard,
                    boards: boards,
                    isBoardsLoading: isBoardsLoading,
                    onSelectBoard: _selectBoardDirect,
                    onCreateBoard: _createBoard,
                    onBoardContextMenu: _showBoardContextMenu,
                    isPerformanceMode: _isPerformanceMode,
                    onTogglePerformanceMode: _togglePerformanceMode,
                    onOpenLibrary: _openLibrary,
                    onOpenSettings: _openSettings,
                    onQuickSearch: () => unawaited(_openQuickSearch()),
                    stopAllButton: StopAllButton(notifier: _notifier),
                    isWindowsFullScreen: widget.isWindowsFullScreen,
                    onToggleWindowsFullScreen: widget.onToggleWindowsFullScreen,
                    onQuitApp: widget.onQuitApp,
                  )
                : SamplerAppBar(
                    selectedBoard: selectedBoard,
                    isPerformanceMode: _isPerformanceMode,
                    onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
                    onTogglePerformanceMode: _togglePerformanceMode,
                    onQuickSearch: () => unawaited(_openQuickSearch()),
                    stopAllButton: StopAllButton(notifier: _notifier),
                  ),
            drawer: prefersDesktopUi
                ? null
                : BoardsDrawer(
                    unprocessedCount: _notifier.unprocessedSoundCount,
                    boards: boards,
                    selectedBoard: selectedBoard,
                    isBoardsLoading: isBoardsLoading,
                    isPerformanceMode: _isPerformanceMode,
                    onSelectBoard: _selectBoard,
                    onCreateBoard: _createBoard,
                    onBoardLongPress: _showBoardActions,
                    onTogglePerformanceMode: () {
                      Navigator.pop(context);
                      _togglePerformanceMode();
                    },
                    onOpenLibrary: () async {
                      Navigator.pop(context);
                      await _openLibrary();
                    },
                    onOpenSettings: () async {
                      Navigator.pop(context);
                      await _openSettings();
                    },
                  ),
            body: SafeArea(
              child: prefersDesktopUi
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _buildSamplerContent(context, state)),
                        musicPreviewPanel,
                      ],
                    )
                  : Stack(
                      children: [
                        Positioned.fill(
                          child: _buildSamplerContent(context, state),
                        ),
                        musicPreviewPanel,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
