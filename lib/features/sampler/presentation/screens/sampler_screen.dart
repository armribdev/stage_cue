import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import '../providers/sampler_provider.dart';
import '../providers/sync_controller.dart';
import '../widgets/pad_button.dart' show padSoundAvailabilityIcon;
import '../models/pad_sound_slot.dart';
import '../widgets/pad_item.dart' show PadCard;
import '../widgets/music_preview_panel.dart';
import '../widgets/music_picker_sheet.dart';
import '../widgets/quick_search_overlay.dart';
import '../widgets/app_form_dialog.dart';
import '../../domain/entities/sound_board.dart';
import '../../../../core/app/app_services.dart';
import '../../../../core/utils/copyable_snackbar.dart';
import '../../../../core/database/database.dart' as db;
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/layout_utils.dart';
import 'settings_screen.dart';
import 'library_sync_screen.dart';
import 'pad_details_screen.dart';
import 'sound_library_screen.dart';
import 'sound_library_manage_screen.dart';

/// Marqueur pour le bouton d'ajout dans la grille
const _addButtonMarker = _AddButtonMarker();

class _AddButtonMarker {
  const _AddButtonMarker();
}

class _UndoPadIntent extends Intent {
  const _UndoPadIntent();
}

class _AddSoundIntent extends Intent {
  const _AddSoundIntent();
}

class _QuickSearchIntent extends Intent {
  const _QuickSearchIntent();
}

/// Écran principal du sampler
class SamplerScreen extends StatefulWidget {
  final AppServices services;

  const SamplerScreen({super.key, required this.services});

  @override
  State<SamplerScreen> createState() => _SamplerScreenState();
}

class _SamplerScreenState extends State<SamplerScreen> {
  late final SamplerNotifier _notifier;
  late final db.AppDatabase _database;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _normalGridScrollController = ScrollController();
  final ScrollController _editGridScrollController = ScrollController();

  ScrollController get _activeGridScrollController =>
      _isEditMode ? _editGridScrollController : _normalGridScrollController;
  int _gridCrossAxisCount = 2;
  double _gridViewportWidth = 0;
  bool _isEditMode = false;
  bool _isPerformanceMode = false;
  int? _recentlyRestoredSoundId;
  int? _highlightedPadId;
  bool _didAutoOpenCreateForCurrentEmptyState = false;
  bool _isMusicRegieAdvanced = false;
  bool _isMusicRegieLocked = false;

  static const _musicRegieTapGroup = 'music-regie-dismiss';

  bool get _isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    _database = widget.services.database;
    _initializeNotifier();
    _notifier.loadBoards();
  }

  void _initializeNotifier() {
    _notifier = SamplerNotifier(
      widget.services.soundRepository,
      widget.services.loadSoundsUseCase,
      widget.services.removeSoundFromBoardUseCase,
      widget.services.libraryRepository,
    );

    _notifier.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    if (!mounted) return;

    final musicError = _notifier.consumeLastMusicPlaybackError();
    if (musicError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(musicError)),
        );
      });
    }

    setState(() {
      if (_isEditMode && _notifier.state.pads.isEmpty) {
        _isEditMode = false;
      }
    });
  }

  /// Sélectionne un board et ferme le drawer (mobile).
  Future<void> _selectBoard(SoundBoard board) async {
    Navigator.pop(context);
    await _notifier.selectBoard(board);
  }

  /// Sélectionne un board sans fermer de drawer (sidebar desktop).
  Future<void> _selectBoardDirect(SoundBoard board) async {
    await _notifier.selectBoard(board);
  }

  Future<void> _createBoard() async {
    if (!mounted) return;

    final suggestedName = _buildSuggestedBoardName(_notifier.state.boards);
    final result = await AppBoardCreationDialog.show(
      context,
      suggestedName: suggestedName,
    );

    if (result == null || !mounted) return;
    // Ferme le drawer s'il est ouvert (mobile — no-op si pas de drawer).
    final scaffoldState = _scaffoldKey.currentState;
    if (scaffoldState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }

    final newBoard = await _notifier.createBoard(
      result.name,
      color: result.color,
    );
    if (!mounted) return;
    if (newBoard == null) {
      showCopyableSnackBar(context, 'Erreur lors de la création de la scène');
    }
  }

  String _buildSuggestedBoardName(List<SoundBoard> boards) {
    final existingNames = boards
        .map((b) => b.name.trim().toLowerCase())
        .where((n) => n.isNotEmpty)
        .toSet();
    var index = 1;
    while (existingNames.contains('scène $index')) {
      index++;
    }
    return 'Scène $index';
  }

  String _buildSuggestedDuplicateBoardName(
    String sourceName,
    List<SoundBoard> boards,
  ) {
    final existingNames = boards
        .map((b) => b.name.trim().toLowerCase())
        .where((n) => n.isNotEmpty)
        .toSet();
    final baseName = '$sourceName (copie)';
    if (!existingNames.contains(baseName.toLowerCase())) {
      return baseName;
    }
    var index = 2;
    while (existingNames.contains('$baseName $index'.toLowerCase())) {
      index++;
    }
    return '$baseName $index';
  }

  /// Actions sur une scène via bottom sheet — pattern tactile (mobile/tablette).
  Future<void> _showBoardActions(SoundBoard board) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Renommer'),
                onTap: () {
                  Navigator.pop(context);
                  _renameBoard(board);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Dupliquer'),
                onTap: () {
                  Navigator.pop(context);
                  _duplicateBoard(board);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Supprimer'),
                onTap: () {
                  Navigator.pop(context);
                  _deleteBoard(board);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Actions sur une scène via menu contextuel — clic droit sur le titre (desktop).
  Future<void> _showBoardContextMenu(
    SoundBoard board,
    Offset globalPosition,
  ) async {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    final screenSize = MediaQuery.sizeOf(context);
    final position = RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      screenSize.width - globalPosition.dx,
      screenSize.height - globalPosition.dy,
    );

    final value = await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_rounded, size: 18, color: scheme.onSurface),
              const SizedBox(width: AppSpacing.sm),
              const Text('Renommer'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 18, color: scheme.onSurface),
              const SizedBox(width: AppSpacing.sm),
              const Text('Dupliquer'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: scheme.error),
              const SizedBox(width: AppSpacing.sm),
              Text('Supprimer', style: TextStyle(color: scheme.error)),
            ],
          ),
        ),
      ],
    );

    if (!mounted) return;
    if (value == 'rename') {
      await _renameBoard(board);
    } else if (value == 'duplicate') {
      await _duplicateBoard(board);
    } else if (value == 'delete') {
      await _deleteBoard(board);
    }
  }

  Future<void> _renameBoard(SoundBoard board) async {
    final name = await AppTextInputDialog.show(
      context,
      title: 'Renommer la scène',
      confirmLabel: 'Renommer',
      initialValue: board.name,
      hint: board.name,
      icon: Icons.text_fields_rounded,
    );

    final trimmedName = name?.trim();
    if (trimmedName == null ||
        trimmedName.isEmpty ||
        trimmedName == board.name) {
      return;
    }

    final ok = await _notifier.renameBoard(board, trimmedName);
    if (!mounted) return;
    if (!ok) {
      showCopyableSnackBar(context, 'Erreur lors du renommage de la scène');
    }
  }

  Future<void> _duplicateBoard(SoundBoard board) async {
    final suggestedName = _buildSuggestedDuplicateBoardName(
      board.name,
      _notifier.state.boards,
    );
    final name = await AppTextInputDialog.show(
      context,
      title: 'Dupliquer la scène',
      confirmLabel: 'Dupliquer',
      initialValue: suggestedName,
      hint: suggestedName,
      icon: Icons.copy_rounded,
    );

    final trimmedName = name?.trim();
    if (trimmedName == null || trimmedName.isEmpty) return;

    final duplicated = await _notifier.duplicateBoard(board, trimmedName);
    if (!mounted) return;
    if (duplicated == null) {
      showCopyableSnackBar(
        context,
        'Erreur lors de la duplication de la scène',
      );
    }
  }

  Future<void> _deleteBoard(SoundBoard board) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Supprimer la scène',
      message: 'Supprimer "${board.name}" ? Cette action est irréversible.',
      confirmLabel: 'Supprimer',
      isDestructive: true,
    );

    if (!confirmed) return;

    final ok = await _notifier.deleteBoard(board);
    if (!mounted) return;
    if (!ok) {
      showCopyableSnackBar(
        context,
        'Erreur lors de la suppression de la scène',
      );
    }
  }

  /// Ouvre la bibliothèque sans fermer de drawer (base method).
  Future<void> _openLibrary() async {
    await SoundLibraryManageScreen.open(context, database: _database);
    if (!mounted) return;
    await _notifier.loadSounds();
  }

  /// Ouvre les paramètres sans fermer de drawer (base method).
  Future<void> _openSettings() async {
    if (!mounted) return;
    await SettingsScreen.open(
      context,
      database: _database,
      libraryRepository: widget.services.libraryRepository,
      syncController: widget.services.syncController,
    );
    if (!mounted) return;
    await _notifier.loadSounds();
  }

  /// Ouvre la gestion de synchro Drive depuis la pastille ambiante de l'AppBar,
  /// puis recharge scènes/sons (un pull a pu modifier la bibliothèque).
  Future<void> _openLibrarySync() async {
    await LibrarySyncScreen.open(
      context,
      libraryRepository: widget.services.libraryRepository,
      syncController: widget.services.syncController,
    );
    if (!mounted) return;
    await _notifier.loadBoards();
  }

  /// Ouvre la recherche-éclair (overlay) ; met en évidence le pad créé si un
  /// son a été ajouté à la scène depuis la recherche.
  Future<void> _openQuickSearch() async {
    if (_isEditMode) return;
    final padId = await QuickSearchOverlay.show(context, notifier: _notifier);
    if (!mounted || padId == null) return;
    await _notifier.stopPreview();
    _emphasizePad(padId);
  }

  Future<void> _handleAddSoundShortcut() async {
    if (!_isDesktopPlatform || !mounted || _isEditMode) return;
    final board = _notifier.state.selectedBoard;
    if (board == null) return;
    await _openSoundLibrary(board);
  }

  Future<void> _handleUndoShortcut() async {
    if (!_isDesktopPlatform || !mounted) return;
    final restoredSoundId = await _notifier.undoLastRemoval();
    if (!mounted || restoredSoundId == null) return;
    setState(() {
      _recentlyRestoredSoundId = restoredSoundId;
    });
    _scrollPadIntoView(restoredSoundId);
    unawaited(
      Future<void>.delayed(_padEmphasisDuration, () {
        if (!mounted || _recentlyRestoredSoundId != restoredSoundId) return;
        setState(() {
          _recentlyRestoredSoundId = null;
        });
      }),
    );
  }

  static const double _itemWidth = 180;
  static const Duration _padEmphasisDuration = Duration(milliseconds: 2200);

  Future<void> _openSoundLibrary(SoundBoard board) async {
    final result = await SoundLibraryScreen.open(
      context,
      database: _database,
      boardId: board.id,
      libraryRepository: widget.services.libraryRepository,
    );
    await _notifier.loadSounds();
    if (!mounted || result == null) return;
    _emphasizePad(result.highlightPadId);
  }

  void _scrollPadIntoView(int padId) {
    void tryScroll() {
      if (!mounted) return;
      final controller = _activeGridScrollController;
      if (!controller.hasClients || controller.positions.length != 1) return;
      final index = _notifier.state.pads.indexWhere((p) => p.pad.id == padId);
      if (index < 0 || _gridViewportWidth <= 0) return;

      const padding = 16.0;
      const crossSpacing = 14.0;
      const mainSpacing = 14.0;
      const aspectRatio = 1.4;

      final contentWidth = _gridViewportWidth - (padding * 2);
      final cellWidth =
          (contentWidth - crossSpacing * (_gridCrossAxisCount - 1)) /
          _gridCrossAxisCount;
      final cellHeight = cellWidth / aspectRatio;
      final row = index ~/ _gridCrossAxisCount;
      final targetTop = padding + row * (cellHeight + mainSpacing);
      final viewport = controller.position.viewportDimension;
      final offset = (targetTop - viewport * 0.25).clamp(
        0.0,
        controller.position.maxScrollExtent,
      );

      controller.animateTo(
        offset,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      tryScroll();
      WidgetsBinding.instance.addPostFrameCallback((_) => tryScroll());
    });
  }

  /// Entre/sort du Mode Spectacle : verrouille l'édition (long-press, grille)
  /// et suspend les push Drive auto pour éviter tout jank pendant le live.
  void _togglePerformanceMode() {
    setState(() {
      _isPerformanceMode = !_isPerformanceMode;
      if (_isPerformanceMode) _isEditMode = false;
    });
    final syncController = widget.services.syncController;
    if (_isPerformanceMode) {
      syncController.pauseAutoSync();
    } else {
      syncController.resumeAutoSync();
    }
  }

  void _toggleEditMode() {
    final outgoing = _activeGridScrollController;
    final savedOffset = outgoing.hasClients && outgoing.positions.length == 1
        ? outgoing.offset
        : 0.0;
    setState(() {
      _isEditMode = !_isEditMode;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final incoming = _activeGridScrollController;
      if (!incoming.hasClients || incoming.positions.length != 1) return;
      incoming.jumpTo(
        savedOffset.clamp(0.0, incoming.position.maxScrollExtent),
      );
    });
  }

  void _emphasizePad(int padId) {
    setState(() {
      _highlightedPadId = padId;
    });
    _scrollPadIntoView(padId);
    unawaited(
      Future<void>.delayed(_padEmphasisDuration, () {
        if (!mounted || _highlightedPadId != padId) return;
        setState(() {
          _highlightedPadId = null;
        });
      }),
    );
  }

  Widget _buildAddButtonCard(BuildContext context, SoundBoard selectedBoard) {
    final scheme = Theme.of(context).colorScheme;
    const borderRadius = 14.0;
    final card = Card(
        key: const ValueKey('add_button'),
        elevation: 0,
        margin: EdgeInsets.zero,
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: CustomPaint(
          foregroundPainter: _DashedRoundedRectPainter(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
            radius: borderRadius,
          ),
          child: InkWell(
            onTap: () => _openSoundLibrary(selectedBoard),
            borderRadius: BorderRadius.circular(borderRadius),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_circle_outline_rounded,
                      size: 22,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Ajouter un son',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    );
    if (!_isDesktopPlatform) {
      return _wrapMusicRegieTapTarget(card);
    }
    return _wrapMusicRegieTapTarget(
      Tooltip(
        message: 'Ajouter un son (Ctrl+N)',
        child: card,
      ),
    );
  }

  Widget _buildPadsGrid(
    BuildContext context,
    SamplerState state,
    SoundBoard selectedBoard,
  ) {
    return LayoutBuilder(
      key: ValueKey<bool>(_isEditMode),
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        int crossAxisCount = (screenWidth / _itemWidth).floor();
        crossAxisCount = max(2, crossAxisCount);
        _gridCrossAxisCount = crossAxisCount;
        _gridViewportWidth = screenWidth;
        final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 1.4,
        );

        if (_isEditMode) {
          return ReorderableGridView.builder(
            key: const ValueKey('pads_reorder_grid'),
            controller: _editGridScrollController,
            padding: const EdgeInsets.all(16),
            gridDelegate: gridDelegate,
            itemCount: state.pads.length,
            dragEnabled: true,
            dragStartDelay: Duration.zero,
            dragWidgetBuilder: (index, child) {
              return Material(
                type: MaterialType.transparency,
                child: Opacity(opacity: 0.95, child: child),
              );
            },
            onDragStart: (index) {
              HapticFeedback.selectionClick();
            },
            onReorder: (oldIndex, newIndex) {
              if (oldIndex == newIndex) return;
              final reordered = List<PadItem>.from(state.pads);
              final moved = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, moved);
              _notifier.reorderSoundsFromList(reordered);
            },
            itemBuilder: (context, index) {
              return _buildPadWidget(context, state, state.pads[index]);
            },
          );
        }

        final gridItems = <Object>[...state.pads, _addButtonMarker];
        return GridView.builder(
          key: const ValueKey('pads_normal_grid'),
          controller: _normalGridScrollController,
          padding: const EdgeInsets.all(16),
          gridDelegate: gridDelegate,
          itemCount: gridItems.length,
          itemBuilder: (context, index) {
            final item = gridItems[index];
            if (item == _addButtonMarker) {
              return _buildAddButtonCard(context, selectedBoard);
            }
            return _buildPadWidget(context, state, item as PadItem);
          },
        );
      },
    );
  }

  Widget _wrapMusicRegieTapTarget(Widget child) {
    if (!_isMusicRegieAdvanced) return child;
    return TapRegion(
      groupId: _musicRegieTapGroup,
      child: child,
    );
  }

  /// Fenêtre pendant laquelle un pad « armé » se déclenche automatiquement une
  /// fois chargé. Au-delà, le moment dramatique est passé : on ne joue pas en
  /// retard, le pad reste PRÊT et un second tap le déclenche instantanément.
  static const _autoPlayWindow = Duration(milliseconds: 1500);

  Future<void> _handlePadTap(BuildContext context, PadItem padItem) async {
    final resolved = _notifier.findPadItemById(padItem.pad.id) ?? padItem;

    // PRÊT : déclenchement immédiat.
    if (resolved.isPlayable) {
      unawaited(HapticFeedback.selectionClick());
      await _notifier.toggleSound(resolved);
      return;
    }

    final reason = resolved.unavailabilityReason;

    // BLOQUÉ : feedback non-bloquant (jamais de modale auto, jamais de clic mort).
    if (reason == PadUnavailabilityReason.offline ||
        reason == PadUnavailabilityReason.missingFile) {
      unawaited(HapticFeedback.heavyImpact());
      _showBlockedPadFeedback(resolved, reason);
      return;
    }

    // EN ROUTE (ou état non résolu) : download optimiste + auto-play.
    unawaited(HapticFeedback.selectionClick());
    await _armAndPlay(resolved);
  }

  /// « Arme » un pad EN ROUTE : tente le cache local puis télécharge, et joue
  /// automatiquement si le pad est prêt à temps. Donne un feedback si bloqué.
  Future<void> _armAndPlay(PadItem padItem) async {
    final stopwatch = Stopwatch()..start();

    // État non résolu : un simple rechargement depuis le cache peut suffire.
    if (padItem.unavailabilityReason == null) {
      await _notifier.refreshPadPlayback(padItem.pad.id);
      if (!mounted) return;
    }

    var resolved = _notifier.findPadItemById(padItem.pad.id) ?? padItem;
    if (!resolved.isPlayable) {
      await _notifier.downloadAndLoadPad(resolved);
      if (!mounted) return;
      resolved = _notifier.findPadItemById(resolved.pad.id) ?? resolved;
    }

    if (resolved.isPlayable) {
      // Joue seulement si l'arrivée est restée « à temps » (cf. _autoPlayWindow).
      if (stopwatch.elapsed <= _autoPlayWindow) {
        await _notifier.toggleSound(resolved);
      }
      return;
    }

    _showBlockedPadFeedback(resolved, resolved.unavailabilityReason);
  }

  /// SnackBar non-bloquante expliquant pourquoi un pad ne joue pas, avec une
  /// action « Détails » pour la vue de téléchargement (sans la pousser de force).
  void _showBlockedPadFeedback(
    PadItem padItem,
    PadUnavailabilityReason? reason,
  ) {
    if (!mounted) return;
    final text = switch (reason) {
      PadUnavailabilityReason.offline =>
        '« ${padItem.pad.displayName} » indisponible hors-ligne',
      PadUnavailabilityReason.missingFile =>
        'Fichier introuvable pour « ${padItem.pad.displayName} »',
      _ => '« ${padItem.pad.displayName} » non téléchargé',
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Détails',
            onPressed: () => _showPadUnavailableSheet(context, padItem),
          ),
        ),
      );
  }

  void _showPadUnavailableSheet(BuildContext context, PadItem padItem) {
    final reason = padItem.unavailabilityReason;
    if (reason == null) return;

    if (reason == PadUnavailabilityReason.needsDownload ||
        padItem.totalSoundCount > 1) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => _PadDownloadSheet(
          padItem: padItem,
          notifier: _notifier,
        ),
      );
      return;
    }

    final (title, body) = switch (reason) {
      PadUnavailabilityReason.needsDownload => (
          'Son non téléchargé',
          'Ce pad n\'est pas disponible localement. Synchronisez la bibliothèque pour télécharger les fichiers audio.',
        ),
      PadUnavailabilityReason.offline => (
          'Hors-ligne',
          'Ce pad n\'est pas disponible sans connexion. Reconnectez-vous pour accéder aux fichiers audio.',
        ),
      PadUnavailabilityReason.missingFile => (
          'Fichier introuvable',
          'Le fichier audio de ce pad est introuvable. Re-synchronisez la bibliothèque.',
        ),
    };

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(body, style: Theme.of(ctx).textTheme.bodyMedium),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPadWidget(
    BuildContext context,
    SamplerState state,
    PadItem padItem,
  ) {
    // ValueKey sur la racine : requis par ReorderableGridView (ne pas utiliser GlobalKey ici).
    return _wrapMusicRegieTapTarget(
      PadCard(
        key: ValueKey<int>(padItem.pad.id),
        padItem: padItem,
        isEditMode: _isEditMode,
        animateOnRestore: _recentlyRestoredSoundId == padItem.pad.id,
        isHighlighted: _highlightedPadId == padItem.pad.id,
        onTap: _isEditMode
            ? null
            : () => unawaited(_handlePadTap(context, padItem)),
        onLongPress: _isEditMode || _isPerformanceMode
            ? null
            : () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PadDetailsScreen(
                      padItem: padItem,
                      notifier: _notifier,
                    ),
                  ),
                );
              },
        onRemove: _isEditMode
            ? () async {
                final removed = await _notifier.removeSound(padItem);
                if (!mounted || !removed) return;
              }
            : null,
      ),
    );
  }

  Widget _buildSamplerContent(BuildContext context, SamplerState state) {
    final selectedBoard = state.selectedBoard;
    final isBoardsLoading = state.isBoardsLoading;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Builder(
        key: ValueKey<String>(
          selectedBoard == null
              ? (isBoardsLoading ? 'boards_loading' : 'boards_empty')
              : state.isLoading
              ? 'sounds_loading'
              : state.error != null && state.pads.isEmpty
              ? 'sounds_error'
              : 'sounds_grid',
        ),
        builder: (context) {
          if (selectedBoard == null) {
            return Center(
              child: isBoardsLoading
                  ? const CircularProgressIndicator()
                  : const Text('Aucune scène disponible'),
            );
          }
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.error != null && state.pads.isEmpty) {
            return Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 48,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Erreur: ${state.error}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          final downloadableCount = state.pads.where((p) => !p.isFullyReady).length;
          final showPrepareBanner =
              downloadableCount > 0 || state.isBoardPreparing;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.error != null)
                Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            state.error!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOutCubic,
                child: showPrepareBanner
                    ? _buildPrepareBanner(context, state, downloadableCount)
                    : const SizedBox.shrink(),
              ),
              Expanded(child: _buildPadsGrid(context, state, selectedBoard)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPrepareBanner(
    BuildContext context,
    SamplerState state,
    int count,
  ) {
    final scheme = Theme.of(context).colorScheme;

    if (state.isBoardPreparing) {
      final total = state.boardPrepareTotal;
      final done = state.boardPrepareDone;
      final progress = total > 0 ? done / total : 0.0;
      return ColoredBox(
        color: scheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$done/$total son${total > 1 ? 's' : ''} téléchargé${done != 1 ? 's' : ''}',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              TweenAnimationBuilder<double>(
                tween: Tween(end: progress),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                builder: (ctx, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(4),
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(scheme.primary),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: () => _notifier.prepareBoardForOffline(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.cloud_download_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$count son${count > 1 ? 's' : ''} '
                  'non téléchargé${count > 1 ? 's' : ''}',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ),
              Text(
                'Préparer',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMusicPicker() async {
    await MusicPickerSheet.show(
      context,
      repository: widget.services.soundRepository,
      notifier: _notifier,
    );
  }

  Widget _buildMusicPreviewPanel(BuildContext context, SamplerState state) {
    return TapRegion(
      groupId: _musicRegieTapGroup,
      onTapOutside: _isMusicRegieAdvanced && !_isMusicRegieLocked
          ? (_) => setState(() => _isMusicRegieAdvanced = false)
          : null,
      child: MusicPreviewPanel(
        state: state,
        musicVolume: _notifier.musicVolume,
        resolveMusicPad: _notifier.resolveMusicPad,
        isAdvanced: _isMusicRegieAdvanced,
        isDesktop: _isDesktopPlatform,
        isLocked: _isMusicRegieLocked,
        onLockedChanged: _isDesktopPlatform
            ? (locked) => setState(() => _isMusicRegieLocked = locked)
            : null,
        onAdvancedChanged: (isAdvanced) => setState(() {
          _isMusicRegieAdvanced = isAdvanced;
          if (!isAdvanced) _isMusicRegieLocked = false;
        }),
        onChooseMusic: () => unawaited(_openMusicPicker()),
        onTogglePlayPause: () =>
            unawaited(_notifier.toggleCurrentMusicPlayback()),
        onSkipNext: () => unawaited(_notifier.skipToNextMusic()),
        onRemoveFromQueue: (padId) =>
            unawaited(_notifier.removeFromMusicQueue(padId)),
        onReorderMusicQueue: _notifier.reorderMusicQueue,
        onMusicVolumeChanged: (value) =>
            unawaited(_notifier.setMusicVolume(value, smooth: true)),
        onFadeOut: (duration) =>
            unawaited(_notifier.fadeOutCurrentMusic(duration)),
        onTransitionToNext: (duration) =>
            unawaited(_notifier.crossfadeToNextMusic(duration)),
      ),
    );
  }

  @override
  void dispose() {
    _normalGridScrollController.dispose();
    _editGridScrollController.dispose();
    _notifier.removeListener(_onStateChanged);
    _notifier.dispose();
    super.dispose();
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    final state = _notifier.state;
    final selectedBoard = state.selectedBoard;
    final boards = state.boards;
    final isBoardsLoading = state.isBoardsLoading;
    final isDesktop = context.deviceClass.isDesktop;

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

    return Shortcuts(
      shortcuts: _isDesktopPlatform
          ? const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.keyN, control: true):
                  _AddSoundIntent(),
              SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                  _UndoPadIntent(),
              SingleActivator(LogicalKeyboardKey.keyK, control: true):
                  _QuickSearchIntent(),
              SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                  _QuickSearchIntent(),
            }
          : const <ShortcutActivator, Intent>{},
      child: Actions(
        actions: <Type, Action<Intent>>{
          _AddSoundIntent: CallbackAction<_AddSoundIntent>(
            onInvoke: (intent) {
              unawaited(_handleAddSoundShortcut());
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
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            key: isDesktop ? null : _scaffoldKey,
            appBar: isDesktop
                ? _SamplerDesktopAppBar(
                    selectedBoard: selectedBoard,
                    boards: boards,
                    isBoardsLoading: isBoardsLoading,
                    isEditMode: _isEditMode,
                    canToggleEditMode: state.pads.isNotEmpty,
                    onSelectBoard: _selectBoardDirect,
                    onCreateBoard: _createBoard,
                    onBoardContextMenu: _showBoardContextMenu,
                    onToggleEditMode: _toggleEditMode,
                    isPerformanceMode: _isPerformanceMode,
                    onTogglePerformanceMode: _togglePerformanceMode,
                    onOpenLibrary: _openLibrary,
                    onOpenSettings: _openSettings,
                    onQuickSearch: () => unawaited(_openQuickSearch()),
                    syncStatus: _SyncStatusPill(
                      syncController: widget.services.syncController,
                      onTap: _openLibrarySync,
                    ),
                  )
                : _SamplerAppBar(
                    selectedBoard: selectedBoard,
                    isEditMode: _isEditMode,
                    isPerformanceMode: _isPerformanceMode,
                    canToggleEditMode: state.pads.isNotEmpty,
                    onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
                    onToggleEditMode: _toggleEditMode,
                    onTogglePerformanceMode: _togglePerformanceMode,
                    onQuickSearch: () => unawaited(_openQuickSearch()),
                    syncStatus: _SyncStatusPill(
                      syncController: widget.services.syncController,
                      onTap: _openLibrarySync,
                    ),
                  ),
            drawer: isDesktop
                ? null
                : _BoardsDrawer(
                    boards: boards,
                    selectedBoard: selectedBoard,
                    isBoardsLoading: isBoardsLoading,
                    onSelectBoard: _selectBoard,
                    onCreateBoard: _createBoard,
                    onBoardLongPress: _showBoardActions,
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
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _buildSamplerContent(context, state),
                  ),
                  ListenableBuilder(
                    listenable: _notifier,
                    builder: (context, _) =>
                        _buildMusicPreviewPanel(context, _notifier.state),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

}

// ---------- Pastille de synchronisation (ambiante) ----------

/// Indicateur de synchro Drive permanent et non bloquant dans l'AppBar.
///
/// Caché tant que la synchro est `idle` (aucun bruit pour un usage 100 % local) ;
/// dès qu'une bibliothèque Drive est en jeu, il rend l'état d'un coup d'œil
/// (couleur + libellé court) et ouvre la gestion de synchro au tap. Remplace
/// l'enfouissement de la synchro dans Paramètres (refonte UX P1).
class _SyncStatusPill extends StatelessWidget {
  final SyncController syncController;
  final VoidCallback onTap;

  const _SyncStatusPill({required this.syncController, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: syncController,
      builder: (context, _) {
        final status = syncController.state.status;
        if (status == SyncStatus.idle) return const SizedBox.shrink();

        final scheme = Theme.of(context).colorScheme;
        final (color, label, icon, spinning, tooltip) =
            _visuals(status, scheme, syncController.state);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Tooltip(
            message: tooltip,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (spinning)
                      SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    else
                      Icon(icon, size: 15, color: color),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  (Color, String, IconData, bool, String) _visuals(
    SyncStatus status,
    ColorScheme scheme,
    SyncState state,
  ) {
    return switch (status) {
      SyncStatus.syncing => (
          scheme.primary,
          'Synchro…',
          Icons.sync_rounded,
          true,
          'Synchronisation en cours…',
        ),
      SyncStatus.synced => (
          scheme.primary,
          'À jour',
          Icons.cloud_done_outlined,
          false,
          'Bibliothèque synchronisée',
        ),
      // Hors-ligne : neutre, jamais alarmiste — le travail local est normal.
      SyncStatus.offline => (
          scheme.onSurfaceVariant,
          'Hors-ligne',
          Icons.cloud_off_outlined,
          false,
          'Hors-ligne — modifications gardées en local',
        ),
      SyncStatus.conflict => (
          scheme.error,
          'Conflit',
          Icons.merge_type_rounded,
          false,
          'Conflit de version — appuyez pour résoudre',
        ),
      SyncStatus.error => (
          scheme.error,
          'Erreur sync',
          Icons.error_outline_rounded,
          false,
          state.message ?? 'Erreur de synchronisation',
        ),
      SyncStatus.idle => (
          scheme.onSurfaceVariant,
          '',
          Icons.cloud_outlined,
          false,
          '',
        ),
    };
  }
}

// ---------- AppBar (mobile/tablette) ----------

class _SamplerAppBar extends StatelessWidget implements PreferredSizeWidget {
  final SoundBoard? selectedBoard;
  final bool isEditMode;
  final bool isPerformanceMode;
  final bool canToggleEditMode;
  final VoidCallback onOpenMenu;
  final VoidCallback onToggleEditMode;
  final VoidCallback onTogglePerformanceMode;
  final VoidCallback onQuickSearch;
  final Widget syncStatus;

  const _SamplerAppBar({
    required this.selectedBoard,
    required this.isEditMode,
    required this.isPerformanceMode,
    required this.canToggleEditMode,
    required this.onOpenMenu,
    required this.onToggleEditMode,
    required this.onTogglePerformanceMode,
    required this.onQuickSearch,
    required this.syncStatus,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.menu_rounded),
        tooltip: 'Menu',
        onPressed: onOpenMenu,
      ),
      title: _BoardTitleLabel(board: selectedBoard),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
          height: 1,
        ),
      ),
      actions: [
        _PerformanceLockButton(
          isPerformanceMode: isPerformanceMode,
          onToggle: onTogglePerformanceMode,
        ),
        IconButton(
          icon: const Icon(Icons.search_rounded),
          tooltip: 'Rechercher un son',
          onPressed: onQuickSearch,
        ),
        syncStatus,
        if (!isPerformanceMode)
          IconButton(
            icon: Icon(
              isEditMode ? Icons.done_rounded : Icons.grid_view_rounded,
              color: isEditMode ? scheme.primary : null,
            ),
            tooltip: isEditMode ? 'Terminer l\'édition' : 'Modifier la grille',
            onPressed: canToggleEditMode ? onToggleEditMode : null,
          ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

// ---------- Bouton verrou Mode Spectacle ----------

/// Bascule du Mode Spectacle : verrouille l'édition et suspend la sync auto
/// pour un live sans modif accidentelle ni jank (refonte UX P2).
class _PerformanceLockButton extends StatelessWidget {
  final bool isPerformanceMode;
  final VoidCallback onToggle;

  const _PerformanceLockButton({
    required this.isPerformanceMode,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(
        isPerformanceMode ? Icons.lock_rounded : Icons.lock_open_rounded,
      ),
      color: isPerformanceMode ? scheme.primary : null,
      tooltip: isPerformanceMode
          ? 'Mode Spectacle actif — déverrouiller'
          : 'Mode Spectacle (verrouiller l\'édition)',
      onPressed: onToggle,
    );
  }
}

// ---------- Liste des scènes (drawer mobile/tablette) ----------

class _BoardsList extends StatelessWidget {
  final List<SoundBoard> boards;
  final SoundBoard? selectedBoard;
  final bool isBoardsLoading;
  final Future<void> Function(SoundBoard board) onSelectBoard;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function(SoundBoard board)? onBoardLongPress;
  final Future<void> Function()? onOpenLibrary;
  final Future<void> Function() onOpenSettings;

  const _BoardsList({
    required this.boards,
    required this.selectedBoard,
    required this.isBoardsLoading,
    required this.onSelectBoard,
    required this.onCreateBoard,
    this.onBoardLongPress,
    required this.onOpenLibrary,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(Icons.theater_comedy_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Scènes',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              if (isBoardsLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (boards.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Aucune scène',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                )
              else
                ...boards.map(
                  (board) => ListTile(
                    leading: board.color != null
                        ? _BoardTileIcon(color: board.color!)
                        : null,
                    title: Text(board.name),
                    onTap: () => onSelectBoard(board),
                    onLongPress: onBoardLongPress == null
                        ? null
                        : () => onBoardLongPress!(board),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Nouvelle scène'),
                onTap: () => onCreateBoard(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.library_books_rounded),
          title: const Text('Gérer la bibliothèque'),
          onTap: onOpenLibrary == null ? null : () => onOpenLibrary!(),
        ),
        ListTile(
          leading: const Icon(Icons.settings),
          title: const Text('Paramètres'),
          onTap: () => onOpenSettings(),
        ),
      ],
    );
  }
}

// ---------- Drawer (mobile/tablette) ----------

class _BoardsDrawer extends StatelessWidget {
  final List<SoundBoard> boards;
  final SoundBoard? selectedBoard;
  final bool isBoardsLoading;
  final Future<void> Function(SoundBoard board) onSelectBoard;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function(SoundBoard board) onBoardLongPress;
  final Future<void> Function()? onOpenLibrary;
  final Future<void> Function() onOpenSettings;

  const _BoardsDrawer({
    required this.boards,
    required this.selectedBoard,
    required this.isBoardsLoading,
    required this.onSelectBoard,
    required this.onCreateBoard,
    required this.onBoardLongPress,
    required this.onOpenLibrary,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: _BoardsList(
          boards: boards,
          selectedBoard: selectedBoard,
          isBoardsLoading: isBoardsLoading,
          onSelectBoard: onSelectBoard,
          onCreateBoard: onCreateBoard,
          onBoardLongPress: onBoardLongPress,
          onOpenLibrary: onOpenLibrary,
          onOpenSettings: onOpenSettings,
        ),
      ),
    );
  }
}

// ---------- AppBar desktop ----------

class _SamplerDesktopAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final SoundBoard? selectedBoard;
  final List<SoundBoard> boards;
  final bool isBoardsLoading;
  final bool isEditMode;
  final bool canToggleEditMode;
  final Future<void> Function(SoundBoard board) onSelectBoard;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function(SoundBoard board, Offset position)
      onBoardContextMenu;
  final VoidCallback onToggleEditMode;
  final bool isPerformanceMode;
  final VoidCallback onTogglePerformanceMode;
  final Future<void> Function() onOpenLibrary;
  final Future<void> Function() onOpenSettings;
  final VoidCallback onQuickSearch;
  final Widget syncStatus;

  const _SamplerDesktopAppBar({
    required this.selectedBoard,
    required this.boards,
    required this.isBoardsLoading,
    required this.isEditMode,
    required this.canToggleEditMode,
    required this.onSelectBoard,
    required this.onCreateBoard,
    required this.onBoardContextMenu,
    required this.onToggleEditMode,
    required this.isPerformanceMode,
    required this.onTogglePerformanceMode,
    required this.onOpenLibrary,
    required this.onOpenSettings,
    required this.onQuickSearch,
    required this.syncStatus,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      leading: _BoardsMenuButton(
        boards: boards,
        selectedBoard: selectedBoard,
        isBoardsLoading: isBoardsLoading,
        onSelectBoard: onSelectBoard,
        onCreateBoard: onCreateBoard,
        onOpenLibrary: onOpenLibrary,
        onOpenSettings: onOpenSettings,
      ),
      title: GestureDetector(
        onSecondaryTapDown: selectedBoard != null
            ? (details) =>
                onBoardContextMenu(selectedBoard!, details.globalPosition)
            : null,
        child: Tooltip(
          message: selectedBoard != null
              ? 'Clic droit pour les actions…'
              : '',
          child: _BoardTitleLabel(board: selectedBoard),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
          height: 1,
        ),
      ),
      actions: [
        _PerformanceLockButton(
          isPerformanceMode: isPerformanceMode,
          onToggle: onTogglePerformanceMode,
        ),
        IconButton(
          icon: const Icon(Icons.search_rounded),
          tooltip: 'Rechercher un son (Ctrl/Cmd+K)',
          onPressed: onQuickSearch,
        ),
        syncStatus,
        if (!isPerformanceMode)
          IconButton(
            icon: Icon(
              isEditMode ? Icons.done_rounded : Icons.grid_view_rounded,
              color: isEditMode ? scheme.primary : null,
            ),
            tooltip: isEditMode ? 'Terminer l\'édition' : 'Modifier la grille',
            onPressed: canToggleEditMode ? onToggleEditMode : null,
          ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

// ---------- Menu popup scènes (desktop) ----------

class _BoardsMenuButton extends StatelessWidget {
  final List<SoundBoard> boards;
  final SoundBoard? selectedBoard;
  final bool isBoardsLoading;
  final Future<void> Function(SoundBoard board) onSelectBoard;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function() onOpenLibrary;
  final Future<void> Function() onOpenSettings;

  const _BoardsMenuButton({
    required this.boards,
    required this.selectedBoard,
    required this.isBoardsLoading,
    required this.onSelectBoard,
    required this.onCreateBoard,
    required this.onOpenLibrary,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: 'Scènes',
      icon: const Icon(Icons.menu_rounded),
      itemBuilder: (context) => [
        if (isBoardsLoading)
          const PopupMenuItem<Object>(
            enabled: false,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (boards.isEmpty)
          const PopupMenuItem<Object>(
            enabled: false,
            child: Text('Aucune scène'),
          )
        else
          ...boards.map(
            (board) => PopupMenuItem<Object>(
              value: board,
              child: Row(
                children: [
                  if (board.color != null) ...[
                    _BoardTileIcon(color: board.color!),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Text(board.name),
                ],
              ),
            ),
          ),
        const PopupMenuItem<Object>(
          value: 'create',
          child: Row(
            children: [
              Icon(Icons.add, size: 18),
              SizedBox(width: AppSpacing.sm),
              Text('Nouvelle scène'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(
          value: 'library',
          child: Row(
            children: [
              Icon(Icons.library_books_rounded, size: 18),
              SizedBox(width: AppSpacing.sm),
              Text('Gérer la bibliothèque'),
            ],
          ),
        ),
        const PopupMenuItem<Object>(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings, size: 18),
              SizedBox(width: AppSpacing.sm),
              Text('Paramètres'),
            ],
          ),
        ),
      ],
      onSelected: (value) async {
        if (value is SoundBoard) {
          await onSelectBoard(value);
        } else if (value == 'create') {
          await onCreateBoard();
        } else if (value == 'library') {
          await onOpenLibrary();
        } else if (value == 'settings') {
          await onOpenSettings();
        }
      },
    );
  }
}

// ---------- Titre de scène dans l'AppBar (icône + nom) ----------

class _BoardTitleLabel extends StatelessWidget {
  const _BoardTitleLabel({this.board});

  final SoundBoard? board;

  @override
  Widget build(BuildContext context) {
    final showIcon = board != null && board!.color != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showIcon) ...[
          _BoardTileIcon(color: board!.color!),
          const SizedBox(width: AppSpacing.sm),
        ],
        Flexible(
          child: Text(
            board?.name ?? 'Scène',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// ---------- Feuille de téléchargement d'un pad ----------

class _PadDownloadSheet extends StatefulWidget {
  final PadItem padItem;
  final SamplerNotifier notifier;

  const _PadDownloadSheet({required this.padItem, required this.notifier});

  @override
  State<_PadDownloadSheet> createState() => _PadDownloadSheetState();
}

class _PadDownloadSheetState extends State<_PadDownloadSheet> {
  bool _isDownloading = false;
  bool _failed = false;

  Future<void> _download() async {
    setState(() {
      _isDownloading = true;
      _failed = false;
    });
    final ok = await widget.notifier.downloadAndLoadPad(widget.padItem);
    if (!mounted) return;
    if (widget.padItem.isFullyReady) {
      Navigator.of(context).pop();
      return;
    }
    if (widget.padItem.isPlayable) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isDownloading = false;
      _failed = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final padItem = widget.padItem;
    final isMulti = padItem.totalSoundCount > 1;
    final ready = padItem.readySoundCount;
    final total = padItem.totalSoundCount;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        32 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isMulti ? 'Variantes du pad' : 'Son non téléchargé',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            isMulti
                ? ready > 0
                    ? '$ready sur $total variantes disponibles localement.'
                    : 'Ce pad contient $total variantes non encore téléchargées.'
                : 'Ce pad n\'est pas encore disponible localement.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (isMulti) ...[
            const SizedBox(height: 16),
            ...List.generate(total, (index) {
              final sound = padItem.pad.sounds[index];
              final availability = index < padItem.slots.length
                  ? padItem.slots[index].availability
                  : PadSoundAvailability.needsDownload;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    padSoundAvailabilityIcon(availability, scheme, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        sound.displayName ?? sound.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          if (_failed) ...[
            const SizedBox(height: 8),
            Text(
              padItem.unavailabilityReason ==
                      PadUnavailabilityReason.missingFile
                  ? 'Fichier introuvable sur Drive. Resynchronisez la bibliothèque dans les paramètres.'
                  : padItem.unavailabilityReason ==
                          PadUnavailabilityReason.offline
                      ? 'Hors-ligne. Reconnectez-vous à Drive dans les paramètres.'
                      : 'Téléchargement échoué. Vérifiez la connexion.',
              style: TextStyle(color: scheme.error, fontSize: 13),
            ),
          ],
          if (_isDownloading && padItem.downloadTotal > 0) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: padItem.downloadDone / padItem.downloadTotal,
            ),
            const SizedBox(height: 4),
            Text(
              'Téléchargement ${padItem.downloadDone}/${padItem.downloadTotal}…',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isDownloading || padItem.isFullyReady
                  ? null
                  : _download,
              icon: _isDownloading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.cloud_download_outlined, size: 18),
              label: Text(
                padItem.isFullyReady
                    ? 'Tout est prêt'
                    : _isDownloading
                        ? 'Téléchargement…'
                        : isMulti
                            ? 'Télécharger les variantes manquantes'
                            : 'Télécharger',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Icône de scène (couleur + icône) ----------

class _BoardTileIcon extends StatelessWidget {
  const _BoardTileIcon({required this.color});

  final int color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: Color(color),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
    );
  }
}

/// Contour pointillé pour le faux pad « Ajouter un son ».
class _DashedRoundedRectPainter extends CustomPainter {
  const _DashedRoundedRectPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;
  static const _strokeWidth = 1.0;
  static const _dashLength = 5.0;
  static const _dashGap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;

    final halfStroke = _strokeWidth / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        halfStroke,
        halfStroke,
        size.width - _strokeWidth,
        size.height - _strokeWidth,
      ),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dashLength).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += _dashLength + _dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedRectPainter oldDelegate) {
    return color != oldDelegate.color || radius != oldDelegate.radius;
  }
}
