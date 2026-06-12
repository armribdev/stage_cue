import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/sampler_provider.dart';
import '../providers/sync_controller.dart';
import '../widgets/pad_button.dart' show padSoundAvailabilityIcon;
import '../models/pad_sound_slot.dart';
import '../widgets/pad_item.dart' show PadCard;
import '../widgets/dashed_slot_frame.dart';
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
import 'sound_library_manage_screen.dart';

class _UndoPadIntent extends Intent {
  const _UndoPadIntent();
}

class _AddPadIntent extends Intent {
  const _AddPadIntent();
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
  bool _isEditMode = false;
  bool _isPerformanceMode = false;
  int? _draggingPadId;
  ({int rowIndex, int position})? _dropTarget;
  Offset? _lastDragGlobalOffset;
  /// true après la 1re frame de drag — évite de reconstruire l'arbre pendant
  /// l'accrochage du geste (sinon le Draggable est démonté et le pad reste bloqué).
  bool _editDragUiReady = false;
  final _editGridKey = GlobalKey();
  double _lastGridWidth = 0;
  int? _recentlyRestoredSoundId;
  int? _highlightedPadId;
  bool _didAutoOpenCreateForCurrentEmptyState = false;
  bool _isMusicRegieAdvanced = false;
  bool _isMusicRegieLocked = false;
  double _musicRegieOccupiedHeight = 0;

  static const _musicRegieTapGroup = 'music-regie-dismiss';
  static const _padsGridPadding = 16.0;

  EdgeInsets get _padsGridScrollPadding => EdgeInsets.fromLTRB(
        _padsGridPadding,
        _padsGridPadding,
        _padsGridPadding,
        _padsGridPadding + _musicRegieOccupiedHeight,
      );

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
    widget.services.syncController.onLibraryMerged = _onLibraryMerged;
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
    _notifier.loadBoards();
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
      appPreferences: widget.services.appPreferences,
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
      appPreferences: widget.services.appPreferences,
    );
    if (!mounted) return;
    await _notifier.loadBoards();
  }

  /// Ouvre la recherche-éclair (overlay) ; met en évidence le pad dédié préparé.
  Future<void> _openQuickSearch() async {
    if (_isEditMode) return;
    final result = await QuickSearchOverlay.show(context, notifier: _notifier);
    if (!mounted) return;
    await _notifier.stopPreview();
    if (!mounted) return;
    final padId = result?.highlightPadId;
    if (padId == null) return;
    _emphasizePad(padId);
  }

  Future<void> _handleAddPadShortcut() async {
    if (!_isDesktopPlatform || !mounted || _isEditMode) return;
    final board = _notifier.state.selectedBoard;
    if (board == null) return;
    final pads = _notifier.state.pads;
    final lastRowIndex = pads.isEmpty
        ? 0
        : pads.map((p) => p.pad.rowIndex).reduce(max);
    await _openAddPadFlow(board, rowIndex: lastRowIndex);
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

  Future<void> _openAddPadFlow(SoundBoard board, {int rowIndex = 0}) async {
    final draftPadId = _notifier.beginDraftPad(rowIndex: rowIndex);
    if (draftPadId == null) return;

    final selectedSoundIds = await PadDetailsScreen.pickSoundsForNewPad(
      context,
      notifier: _notifier,
      draftPadId: draftPadId,
    );
    if (!mounted) {
      _notifier.cancelDraftPad(draftPadId);
      return;
    }
    if (selectedSoundIds.isEmpty) {
      _notifier.cancelDraftPad(draftPadId);
      return;
    }

    final padItem = await _notifier.commitDraftPad(
      draftPadId: draftPadId,
      soundIds: selectedSoundIds,
    );
    if (!mounted || padItem == null) return;

    await PadDetailsScreen.open(
      context,
      padItem: padItem,
      notifier: _notifier,
    );
  }

  static const double _editRowGap = 14;

  void _updateDropTarget(int rowIndex, int position) {
    if (_dropTarget?.rowIndex == rowIndex &&
        _dropTarget?.position == position) {
      return;
    }
    _dropTarget = (rowIndex: rowIndex, position: position);
    if (_editDragUiReady) {
      setState(() {});
    }
  }

  double _editWrapHeight(int padCount, double cellHeight, int slotsPerRow) {
    if (padCount == 0) return cellHeight;
    final lines = (padCount / slotsPerRow).ceil();
    return lines * cellHeight + (lines - 1) * _editRowGap;
  }

  int _editIndexFromLocalRow(
    Offset local,
    int visibleCount,
    double cellWidth,
    double cellHeight,
    int slotsPerRow,
  ) {
    if (visibleCount == 0) return 0;
    final strideX = cellWidth + _editRowGap;
    final strideY = cellHeight + _editRowGap;
    final line = (local.dy / strideY).floor().clamp(0, 999);
    final col = (local.dx / strideX).floor().clamp(0, slotsPerRow - 1);
    var index = line * slotsPerRow + col;
    if (index >= visibleCount) return visibleCount;
    final cellLeft = col * strideX;
    if (local.dx > cellLeft + cellWidth / 2) index++;
    return index.clamp(0, visibleCount);
  }

  ({int rowIndex, int position})? _resolveEditDropTarget({
    required Offset global,
    required Map<int, List<PadItem>> rowMap,
    required List<int> rowIndices,
    required int newRowIndex,
    required double cellWidth,
    required double cellHeight,
    required int slotsPerRow,
    int? excludePadId,
  }) {
    final box =
        _editGridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;

    final draggedId = excludePadId ?? _draggingPadId;
    final local = box.globalToLocal(global);
    var y = 0.0;

    for (final rowIdx in rowIndices) {
      final pads = rowMap[rowIdx] ?? [];
      final height = _editWrapHeight(pads.length, cellHeight, slotsPerRow);
      if (local.dy < y + height + _editRowGap / 2) {
        final visibleCount =
            pads.where((p) => p.pad.id != draggedId).length;
        final pos = _editIndexFromLocalRow(
          Offset(local.dx, local.dy - y),
          visibleCount,
          cellWidth,
          cellHeight,
          slotsPerRow,
        );
        return (rowIndex: rowIdx, position: pos);
      }
      y += height + _editRowGap;
    }

    if (local.dy >= y) {
      return (rowIndex: newRowIndex, position: 0);
    }
    return null;
  }

  /// Simule le layout après drop sans toucher à l'état.
  Map<int, List<PadItem>> _previewRowMap({
    required Map<int, List<PadItem>> rowMap,
    required int padId,
    required int targetRowIndex,
    required int insertionPosition,
  }) {
    final byRow = <int, List<PadItem>>{};
    for (final entry in rowMap.entries) {
      byRow[entry.key] = List<PadItem>.from(entry.value);
    }

    PadItem? moved;
    for (final entry in byRow.entries) {
      final idx = entry.value.indexWhere((p) => p.pad.id == padId);
      if (idx != -1) {
        moved = entry.value.removeAt(idx);
        if (entry.value.isEmpty) byRow.remove(entry.key);
        break;
      }
    }
    if (moved == null) return rowMap;

    final targetList = byRow[targetRowIndex] ?? <PadItem>[];
    final pos = insertionPosition.clamp(0, targetList.length);
    targetList.insert(pos, moved);
    byRow[targetRowIndex] = targetList;
    return byRow;
  }

  double _editGridTotalHeight({
    required List<int> rowIndices,
    required Map<int, List<PadItem>> rowMap,
    required double cellHeight,
    required int slotsPerRow,
    required bool includeNewRowSpacer,
  }) {
    var y = 0.0;
    for (var i = 0; i < rowIndices.length; i++) {
      if (i > 0) y += _editRowGap;
      final count = rowMap[rowIndices[i]]?.length ?? 0;
      y += _editWrapHeight(count, cellHeight, slotsPerRow);
    }
    if (includeNewRowSpacer) {
      y += _editRowGap + cellHeight;
    }
    return y;
  }

  void _finishPadDrag(
    int padId,
    Offset globalOffset, {
    required Map<int, List<PadItem>> rowMap,
    required List<int> rowIndices,
    required int newRowIndex,
    required double cellWidth,
    required double cellHeight,
    required int slotsPerRow,
  }) {
    if (_draggingPadId != padId) return;

    final target = _resolveEditDropTarget(
      global: globalOffset,
      rowMap: rowMap,
      rowIndices: rowIndices,
      newRowIndex: newRowIndex,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
      slotsPerRow: slotsPerRow,
      excludePadId: padId,
    );

    setState(() {
      _draggingPadId = null;
      _dropTarget = null;
      _lastDragGlobalOffset = null;
      _editDragUiReady = false;
    });

    if (target == null) return;

    unawaited(_notifier.movePadToPosition(
      padId,
      target.rowIndex,
      target.position,
    ));
  }

  static const double _padScrollAlignment = 0.28;

  double? _computePadTopOffset(int padId, double gridWidth) {
    if (gridWidth <= 0) return null;

    final state = _notifier.state;
    PadItem? target;
    for (final pad in state.pads) {
      if (pad.pad.id == padId && !pad.isDraft && _shouldShowPadOnGrid(pad)) {
        target = pad;
        break;
      }
    }
    if (target == null) return null;

    const rowGap = 14.0;
    final crossAxisCount = max(2, (gridWidth / _itemWidth).floor());
    final availWidth = gridWidth - 32.0;
    final cellHeight =
        ((availWidth - (crossAxisCount - 1) * rowGap) / crossAxisCount) / 1.4;

    final rowMap = <int, List<PadItem>>{};
    for (final pad in state.pads) {
      if (!_shouldShowPadOnGrid(pad)) continue;
      rowMap.putIfAbsent(pad.pad.rowIndex, () => []).add(pad);
    }
    final rowIndices = rowMap.keys.toList()..sort();
    final displayRowIndices = rowMap.isNotEmpty ? rowIndices : [0];
    final visualRowIndex = displayRowIndices.indexOf(target.pad.rowIndex);
    if (visualRowIndex < 0) return null;

    return _padsGridPadding + visualRowIndex * (cellHeight + rowGap);
  }

  void _scrollPadIntoView(int padId) {
    void tryScroll() {
      if (!mounted) return;
      final controller = _activeGridScrollController;
      if (!controller.hasClients || controller.positions.length != 1) return;

      final padTop = _computePadTopOffset(padId, _lastGridWidth);
      if (padTop == null) return;

      final viewportHeight = controller.position.viewportDimension;
      final targetOffset = (padTop - viewportHeight * _padScrollAlignment)
          .clamp(0.0, controller.position.maxScrollExtent);

      controller.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      tryScroll();
      WidgetsBinding.instance.addPostFrameCallback((_) => tryScroll());
    });
  }

  bool _shouldShowPadOnGrid(PadItem pad) {
    if (pad.isDraft || _isEditMode) return true;
    if (!_notifier.offlineMode) return true;
    return _notifier.isPadVisibleInOfflineMode(pad);
  }

  void _toggleOfflineMode() {
    unawaited(_notifier.setOfflineMode(!_notifier.offlineMode));
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
    final onStage = _notifier.state.pads.any(
      (item) => !item.isDraft && item.pad.id == padId,
    );
    if (!onStage) return;

    setState(() => _highlightedPadId = padId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _highlightedPadId != padId) return;
      _scrollPadIntoView(padId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _highlightedPadId != padId) return;
        _scrollPadIntoView(padId);
      });
    });

    unawaited(
      Future<void>.delayed(_padEmphasisDuration, () {
        if (!mounted || _highlightedPadId != padId) return;
        setState(() => _highlightedPadId = null);
      }),
    );
  }

  Widget _buildAddToRowButton(
    BuildContext context,
    SoundBoard board, {
    required int rowIndex,
  }) {
    final scheme = Theme.of(context).colorScheme;
    Widget card = DashedSlotFrame(
      onTap: () => _openAddPadFlow(board, rowIndex: rowIndex),
      child: Center(
        child: Icon(
          Icons.add_rounded,
          size: 24,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
    if (_isDesktopPlatform) {
      card = Tooltip(message: 'Ajouter un pad (Ctrl+N)', child: card);
    }
    return _wrapMusicRegieTapTarget(card);
  }

  static const Duration _addSlotTransitionDuration = Duration(milliseconds: 240);

  /// Le « + » de fin de ligne se transforme en pad ; un nouveau « + » apparaît à côté.
  Widget _buildMorphingAddSlot(
    BuildContext context, {
    required SamplerState state,
    required SoundBoard board,
    required int rowIndex,
    required PadItem? draft,
  }) {
    return AnimatedSwitcher(
      duration: _addSlotTransitionDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
      child: draft != null
          ? KeyedSubtree(
              key: ValueKey<int>(draft.pad.id),
              child: _buildPadWidget(context, state, draft),
            )
          : KeyedSubtree(
              key: ValueKey<String>('add_pad_slot_$rowIndex'),
              child: _buildAddToRowButton(
                context,
                board,
                rowIndex: rowIndex,
              ),
            ),
    );
  }

  Widget _buildAddSlotEntrance({required Widget child}) {
    return TweenAnimationBuilder<double>(
      key: const ValueKey<String>('add_slot_entrance'),
      tween: Tween(begin: 0, end: 1),
      duration: _addSlotTransitionDuration,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(
            scale: 0.94 + 0.06 * value,
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  List<Widget> _buildNormalRowCells({
    required BuildContext context,
    required SamplerState state,
    required SoundBoard board,
    required int rowIndex,
    required List<PadItem> rowPads,
    required double cellWidth,
    required double cellHeight,
  }) {
    final committed = rowPads.where((pad) => !pad.isDraft).toList();
    PadItem? draft;
    for (final pad in rowPads) {
      if (pad.isDraft) {
        draft = pad;
        break;
      }
    }

    final cells = <Widget>[
      for (final pad in committed)
        SizedBox(
          key: ValueKey<int>(pad.pad.id),
          width: cellWidth,
          height: cellHeight,
          child: _buildPadWidget(context, state, pad),
        ),
      SizedBox(
        key: ValueKey<String>('row_${rowIndex}_tail_slot'),
        width: cellWidth,
        height: cellHeight,
        child: _buildMorphingAddSlot(
          context,
          state: state,
          board: board,
          rowIndex: rowIndex,
          draft: draft,
        ),
      ),
    ];

    if (draft != null) {
      cells.add(
        SizedBox(
          key: ValueKey<String>('add_row_${rowIndex}_trailing'),
          width: cellWidth,
          height: cellHeight,
          child: _buildAddSlotEntrance(
            child: _buildAddToRowButton(
              context,
              board,
              rowIndex: rowIndex,
            ),
          ),
        ),
      );
    }

    return cells;
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
        _lastGridWidth = screenWidth;
        final crossAxisCount = max(2, (screenWidth / _itemWidth).floor());

        // Dimensions communes aux deux modes.
        final availWidth = screenWidth - 32.0;
        final cellWidth =
            (availWidth - (crossAxisCount - 1) * 14.0) / crossAxisCount;
        final cellHeight = cellWidth / 1.4;

        // Grouper les pads par rowIndex (ordre stable dans chaque ligne).
        final rowMap = <int, List<PadItem>>{};
        for (final pad in state.pads) {
          if (!_shouldShowPadOnGrid(pad)) continue;
          rowMap.putIfAbsent(pad.pad.rowIndex, () => []).add(pad);
        }
        for (final pads in rowMap.values) {
          pads.sort((a, b) => a.pad.sortOrder.compareTo(b.pad.sortOrder));
        }
        final rowIndices = rowMap.keys.toList()..sort();
        final hasPads = rowMap.isNotEmpty;

        if (_isEditMode) {
          if (!hasPads) return const SizedBox.shrink();

          final newRowIndex = rowIndices.last + 1;

          final dropTarget = _dropTarget;
          final showDragPreview =
              _editDragUiReady && _draggingPadId != null;
          final visualRowMap = showDragPreview && dropTarget != null
              ? _previewRowMap(
                  rowMap: rowMap,
                  padId: _draggingPadId!,
                  targetRowIndex: dropTarget.rowIndex,
                  insertionPosition: dropTarget.position,
                )
              : rowMap;
          final visualRowIndices = visualRowMap.keys.toList()..sort();

          final hitTestHeight = _editGridTotalHeight(
            rowIndices: rowIndices,
            rowMap: rowMap,
            cellHeight: cellHeight,
            slotsPerRow: crossAxisCount,
            includeNewRowSpacer: true,
          );

          Widget buildEditPadCell(PadItem padItem) {
            final rowIdx = padItem.pad.rowIndex;
            final rowPads = rowMap[rowIdx] ?? [];
            final indexInRow =
                rowPads.indexWhere((p) => p.pad.id == padItem.pad.id);

            return SizedBox(
              key: ValueKey('pad_${padItem.pad.id}'),
              width: cellWidth,
              height: cellHeight,
              child: Draggable<int>(
                key: ValueKey('draggable_${padItem.pad.id}'),
                data: padItem.pad.id,
                dragAnchorStrategy: (draggable, context, position) =>
                    Offset(cellWidth / 2, cellHeight / 2),
                onDragStarted: () {
                  HapticFeedback.selectionClick();
                  _draggingPadId = padItem.pad.id;
                  _lastDragGlobalOffset = null;
                  _editDragUiReady = false;
                  _dropTarget = (
                    rowIndex: rowIdx,
                    position: indexInRow < 0 ? 0 : indexInRow,
                  );
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || _draggingPadId != padItem.pad.id) {
                      return;
                    }
                    setState(() => _editDragUiReady = true);
                  });
                },
                onDragUpdate: (details) {
                  _lastDragGlobalOffset = details.globalPosition;
                  final target = _resolveEditDropTarget(
                    global: details.globalPosition,
                    rowMap: rowMap,
                    rowIndices: rowIndices,
                    newRowIndex: newRowIndex,
                    cellWidth: cellWidth,
                    cellHeight: cellHeight,
                    slotsPerRow: crossAxisCount,
                    excludePadId: padItem.pad.id,
                  );
                  if (target != null) {
                    _updateDropTarget(target.rowIndex, target.position);
                  }
                },
                onDragEnd: (details) {
                  _finishPadDrag(
                    padItem.pad.id,
                    _lastDragGlobalOffset ?? details.offset,
                    rowMap: rowMap,
                    rowIndices: rowIndices,
                    newRowIndex: newRowIndex,
                    cellWidth: cellWidth,
                    cellHeight: cellHeight,
                    slotsPerRow: crossAxisCount,
                  );
                },
                feedback: Material(
                  type: MaterialType.transparency,
                  child: Opacity(
                    opacity: 0.88,
                    child: SizedBox(
                      width: cellWidth,
                      height: cellHeight,
                      child: PadCard(
                        padItem: padItem,
                        isEditMode: false,
                        isTapBlocked: (_) => false,
                      ),
                    ),
                  ),
                ),
                childWhenDragging: const SizedBox.shrink(),
                child: _buildPadWidget(context, state, padItem),
              ),
            );
          }

          Widget buildPreviewColumn() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < visualRowIndices.length; i++) ...[
                  if (i > 0) const SizedBox(height: _editRowGap),
                  Wrap(
                    spacing: _editRowGap,
                    runSpacing: _editRowGap,
                    children: [
                      for (final pad
                          in visualRowMap[visualRowIndices[i]] ?? [])
                        SizedBox(
                          key: ValueKey('pad_prev_${pad.pad.id}'),
                          width: cellWidth,
                          height: cellHeight,
                          child: PadCard(
                            padItem: pad,
                            isEditMode: true,
                            isTapBlocked: (_) => false,
                          ),
                        ),
                    ],
                  ),
                ],
                if (dropTarget?.rowIndex == newRowIndex) ...[
                  const SizedBox(height: _editRowGap),
                  SizedBox(height: cellHeight),
                ],
              ],
            );
          }

          return SingleChildScrollView(
            key: const ValueKey('pads_edit_rows'),
            controller: _editGridScrollController,
            padding: _padsGridScrollPadding,
            child: Stack(
              key: _editGridKey,
              clipBehavior: Clip.none,
              children: [
                // Grille interactive (invisible pendant la prévisualisation).
                Opacity(
                  opacity: showDragPreview ? 0 : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < rowIndices.length; i++) ...[
                        if (i > 0) const SizedBox(height: _editRowGap),
                        Wrap(
                          spacing: _editRowGap,
                          runSpacing: _editRowGap,
                          children: [
                            for (final pad in rowMap[rowIndices[i]] ?? [])
                              buildEditPadCell(pad),
                          ],
                        ),
                      ],
                      const SizedBox(height: _editRowGap),
                      SizedBox(height: cellHeight),
                    ],
                  ),
                ),
                // Zone de hit-test stable (layout courant, pas la prévisualisation).
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: hitTestHeight,
                  child: const IgnorePointer(
                    child: SizedBox.expand(),
                  ),
                ),
                // Prévisualisation par-dessus (les événements passent au Draggable).
                if (showDragPreview)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: buildPreviewColumn(),
                    ),
                  ),
              ],
            ),
          );
        }

        // Mode normal : layout par lignes (rows).
        final displayRowIndices = hasPads ? rowIndices : [0];
        final nextRowIndex = hasPads ? rowIndices.last + 1 : null;

        return SingleChildScrollView(
          key: const ValueKey('pads_normal_rows'),
          controller: _normalGridScrollController,
          padding: _padsGridScrollPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < displayRowIndices.length; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: _buildNormalRowCells(
                    context: context,
                    state: state,
                    board: selectedBoard,
                    rowIndex: displayRowIndices[i],
                    rowPads: rowMap[displayRowIndices[i]] ?? [],
                    cellWidth: cellWidth,
                    cellHeight: cellHeight,
                  ),
                ),
              ],
              if (nextRowIndex != null) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: _buildNormalRowCells(
                    context: context,
                    state: state,
                    board: selectedBoard,
                    rowIndex: nextRowIndex,
                    rowPads: const [],
                    cellWidth: cellWidth,
                    cellHeight: cellHeight,
                  ),
                ),
              ],
            ],
          ),
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

  Future<void> _handlePadTap(BuildContext context, PadItem padItem) async {
    final resolved = _notifier.findPadItemById(padItem.pad.id) ?? padItem;

    debugPrint(
      '[TAP] pad="${resolved.pad.displayName}" id=${resolved.pad.id} '
      'isPlayable=${resolved.isPlayable} appearsReady=${resolved.appearsReady} '
      'isPlaying=${resolved.isPlaying} isDownloading=${resolved.isDownloading} '
      'unavailabilityReason=${resolved.unavailabilityReason} '
      'slots=${resolved.slots.length} readySlots=${resolved.slots.where((s) => s.isReady).length}',
    );

    if (_notifier.offlineMode && !resolved.hasLocallyAvailableSound) {
      return;
    }

    // PRÊT (bouton GO) : lecture immédiate garantie.
    if (resolved.isPlayable) {
      unawaited(HapticFeedback.selectionClick());
      await _notifier.toggleSound(resolved);
      return;
    }

    // Fichier local validé, lecteur SoLoud pas encore chargé.
    if (resolved.appearsReady) {
      debugPrint('[TAP] pad="${resolved.pad.displayName}" → appearsReady, refreshing players');
      unawaited(HapticFeedback.selectionClick());
      await _notifier.refreshPadPlayback(resolved.pad.id);
      if (!mounted) return;
      final after = _notifier.findPadItemById(resolved.pad.id) ?? resolved;
      debugPrint('[TAP] pad="${resolved.pad.displayName}" → after refresh: isPlayable=${after.isPlayable}');
      if (after.isPlayable) {
        await _notifier.toggleSound(after);
      }
      return;
    }

    final reason = resolved.unavailabilityReason;

    if (reason == PadUnavailabilityReason.offline ||
        reason == PadUnavailabilityReason.unsupportedFormat) {
      debugPrint('[TAP] pad="${resolved.pad.displayName}" → BLOQUÉ reason=$reason');
      unawaited(HapticFeedback.heavyImpact());
      _showBlockedPadFeedback(resolved, reason);
      return;
    }

    if (reason == PadUnavailabilityReason.missingFile ||
        _notifier.isPadTapBlocked(resolved)) {
      debugPrint('[TAP] pad="${resolved.pad.displayName}" → BLOQUÉ reason=$reason');
      return;
    }

    if (_notifier.offlineMode) return;

    debugPrint('[TAP] pad="${resolved.pad.displayName}" → EN ROUTE / preparing');
    // EN ROUTE (bouton DL) : on télécharge SANS jouer. Le moment de lecture
    // doit rester maîtrisé par l'opérateur → le pad devient un bouton GO une
    // fois prêt, et un second tap le déclenche immédiatement.
    if (resolved.isDownloading) return; // déjà en cours
    unawaited(HapticFeedback.selectionClick());
    await _preparePad(resolved);
  }

  /// Prépare un pad EN ROUTE : recharge depuis le cache puis télécharge si
  /// nécessaire — **sans lecture automatique**. Le pad passe en PRÊT (GO) ;
  /// l'opérateur déclenche au tap suivant. Feedback non-bloquant si bloqué.
  Future<void> _preparePad(PadItem padItem) async {
    // État non résolu : un simple rechargement depuis le cache peut suffire.
    if (padItem.unavailabilityReason == null) {
      await _notifier.refreshPadPlayback(padItem.pad.id);
      if (!mounted) return;
    }

    final resolved = _notifier.findPadItemById(padItem.pad.id) ?? padItem;
    if (resolved.isPlayable) return; // déjà prêt : c'est désormais un bouton GO.

    await _notifier.downloadAndLoadPad(resolved);
    if (!mounted) return;

    final after = _notifier.findPadItemById(resolved.pad.id) ?? resolved;
    if (!after.isPlayable) {
      _showBlockedPadFeedback(after, after.unavailabilityReason);
    }
    // Sinon : le pad est maintenant PRÊT (GO), sans déclenchement automatique.
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
        '« ${padItem.displayName} » indisponible hors-ligne',
      PadUnavailabilityReason.missingFile =>
        'Fichier introuvable pour « ${padItem.displayName} »',
      PadUnavailabilityReason.unsupportedFormat =>
        'Format audio non supporté pour « ${padItem.displayName} »',
      _ => '« ${padItem.displayName} » non téléchargé',
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
          _notifier.isPadRetryableFromDrive(padItem)
              ? 'Le fichier audio n\'a pas pu être chargé. Touchez le pad pour '
                  'retenter le téléchargement depuis Drive, ou resynchronisez la '
                  'bibliothèque dans les paramètres.'
              : 'Le fichier audio n\'a pas pu être chargé. Resynchronisez la '
                  'bibliothèque dans les paramètres.',
        ),
      PadUnavailabilityReason.unsupportedFormat => (
          'Format non supporté',
          'Ce format audio n\'est pas pris en charge sur cette plateforme. '
              'Convertissez le fichier en MP3 ou WAV pour l\'utiliser.',
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
        isTapBlocked: _notifier.isPadTapBlocked,
        animateOnRestore: _recentlyRestoredSoundId == padItem.pad.id,
        isHighlighted: _highlightedPadId == padItem.pad.id,
        onTap: () => unawaited(_handlePadTap(context, padItem)),
        onLongPress: _isEditMode || _isPerformanceMode
            ? null
            : () => PadDetailsScreen.open(
                  context,
                  padItem: padItem,
                  notifier: _notifier,
                ),
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
              : state.isLoading && state.pads.isEmpty
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
          if (state.isLoading && state.pads.isEmpty) {
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
          final downloadableCount =
              state.pads.where(_notifier.isPadPreparable).length;
          final showPrepareBanner = !state.offlineMode &&
              (downloadableCount > 0 || state.isBoardPreparing);
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
        onOccupiedHeightChanged: (height) {
          if ((height - _musicRegieOccupiedHeight).abs() < 0.5) return;
          setState(() => _musicRegieOccupiedHeight = height);
        },
      ),
    );
  }

  @override
  void dispose() {
    widget.services.syncController.onLibraryMerged = null;
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
                  _AddPadIntent(),
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
                    isOfflineMode: state.offlineMode,
                    onToggleOfflineMode: _toggleOfflineMode,
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
                    isOfflineMode: state.offlineMode,
                    canToggleEditMode: state.pads.isNotEmpty,
                    onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
                    onToggleEditMode: _toggleEditMode,
                    onTogglePerformanceMode: _togglePerformanceMode,
                    onToggleOfflineMode: _toggleOfflineMode,
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
  final bool isOfflineMode;
  final bool canToggleEditMode;
  final VoidCallback onOpenMenu;
  final VoidCallback onToggleEditMode;
  final VoidCallback onTogglePerformanceMode;
  final VoidCallback onToggleOfflineMode;
  final VoidCallback onQuickSearch;
  final Widget syncStatus;

  const _SamplerAppBar({
    required this.selectedBoard,
    required this.isEditMode,
    required this.isPerformanceMode,
    required this.isOfflineMode,
    required this.canToggleEditMode,
    required this.onOpenMenu,
    required this.onToggleEditMode,
    required this.onTogglePerformanceMode,
    required this.onToggleOfflineMode,
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
        _OfflineModeButton(
          isOfflineMode: isOfflineMode,
          onToggle: onToggleOfflineMode,
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

// ---------- Bouton mode hors-ligne ----------

/// Masque les pads sans fichier local et limite la lecture au cache.
class _OfflineModeButton extends StatelessWidget {
  final bool isOfflineMode;
  final VoidCallback onToggle;

  const _OfflineModeButton({
    required this.isOfflineMode,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(
        isOfflineMode
            ? Icons.offline_bolt_rounded
            : Icons.offline_bolt_outlined,
      ),
      color: isOfflineMode ? scheme.primary : null,
      tooltip: isOfflineMode
          ? 'Mode hors-ligne actif — sons locaux uniquement'
          : 'Mode hors-ligne (sons locaux uniquement)',
      onPressed: onToggle,
    );
  }
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
  final bool isOfflineMode;
  final VoidCallback onToggleOfflineMode;
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
    required this.isOfflineMode,
    required this.onToggleOfflineMode,
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
        _OfflineModeButton(
          isOfflineMode: isOfflineMode,
          onToggle: onToggleOfflineMode,
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
                      PadUnavailabilityReason.unsupportedFormat
                  ? 'Format audio non supporté sur cette plateforme. Convertissez le fichier en MP3 ou WAV.'
                  : padItem.unavailabilityReason ==
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

