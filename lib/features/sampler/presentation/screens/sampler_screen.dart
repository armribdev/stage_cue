import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/sampler_provider.dart';
import '../widgets/pad_button.dart' show padSoundAvailabilityIcon;
import '../models/pad_sound_slot.dart';
import '../widgets/pad_item.dart' show PadCard;
import '../widgets/dashed_slot_frame.dart';
import '../widgets/threshold_draggable.dart';
import '../widgets/music_preview_panel.dart';
import '../widgets/music_picker_sheet.dart';
import '../widgets/quick_search_overlay.dart';
import '../widgets/audio_vu_meter.dart';
import '../widgets/app_form_dialog.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/sound_board.dart';
import '../../../../core/app/app_services.dart';
import '../../../../core/sync/google_oauth_config.dart';
import '../../../../core/sync/google_oauth_setup_dialog.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/database/database.dart' as db;
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/skeleton.dart';
import '../../../../core/utils/layout_utils.dart';
import 'settings_screen.dart';
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

class _StopAllIntent extends Intent {
  const _StopAllIntent();
}

/// Recherche-éclair pré-filtrée par type de son (Ctrl+G/H/J).
class _QuickSearchFilteredIntent extends Intent {
  final SoundType type;
  const _QuickSearchFilteredIntent(this.type);
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
  bool _isMusicRegieLocked = false;
  double _musicRegieOccupiedHeight = 0;

  static const _musicRegieTapGroup = 'music-regie-dismiss';
  static const _padsGridPadding = 16.0;

  EdgeInsets _padsGridScrollPadding(BuildContext context) => EdgeInsets.fromLTRB(
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
    final libraries = await _notifier.getConnectedLibraries();
    if (!mounted) return;
    // Une seule bibliothèque : pré-sélectionnée (conserve l'ancien comportement
    // auto). Sinon défaut « Local » et l'opérateur choisit explicitement.
    final initialLibraryId = libraries.length == 1 ? libraries.first.id : null;
    final result = await AppBoardCreationDialog.show(
      context,
      suggestedName: suggestedName,
      libraries: [
        for (final library in libraries) (id: library.id, name: library.name),
      ],
      initialLibraryId: initialLibraryId,
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
      libraryId: result.libraryId,
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
    await SoundLibraryManageScreen.open(
      context,
      notifier: _notifier,
      database: _database,
      onReconnect: () => unawaited(_reconnectDriveInline()),
    );
    if (!mounted) return;
    await _notifier.loadSounds();
  }

  /// Ouvre les paramètres sans fermer de drawer (base method).
  Future<void> _openSettings({bool scrollToDriveSection = false}) async {
    if (!mounted) return;
    await SettingsScreen.open(
      context,
      database: _database,
      libraryRepository: widget.services.libraryRepository,
      syncController: widget.services.syncController,
      appPreferences: widget.services.appPreferences,
      scrollToDriveSection: scrollToDriveSection,
    );
    if (!mounted) return;
    await _notifier.loadSounds();
  }

  /// Action « Reconnecter » pour les snackbars d'échec dus à une session Google
  /// expirée — relance l'OAuth interactif **en place** (sans ouvrir les
  /// réglages). Renvoie `null` si la session est valide (l'échec a une autre
  /// cause).
  SnackBarAction? _reconnectSnackBarAction() {
    if (!_notifier.driveSessionExpired) return null;
    return SnackBarAction(
      label: 'Reconnecter',
      onPressed: () => unawaited(_reconnectDriveInline()),
    );
  }

  /// Reconnexion Drive déclenchée depuis un snackbar, sans quitter l'écran.
  ///
  /// Le refresh silencieux du token a déjà été tenté (et a échoué) avant que
  /// « Session Google expirée » ne s'affiche — inutile de le rejouer ici :
  /// [ensureDriveConnected] enchaîne directement sur l'OAuth interactif quand
  /// [requiresInteractiveReconnect] est levé. Au succès, on efface la bannière
  /// hors-ligne et on recharge les sons pour lever les indisponibilités.
  Future<void> _reconnectDriveInline() async {
    if (_driveReconnectInFlight) return;
    final repo = widget.services.libraryRepository;
    final sync = widget.services.syncController;
    if (!await ensureGoogleOAuthConfigured(context)) return;
    if (!mounted) return;

    setState(() => _driveReconnectInFlight = true);
    try {
      final connected = await repo.ensureDriveConnected();
      if (!mounted) return;
      if (!connected) return; // l'utilisateur a annulé le sélecteur de compte
      sync.clearAuthOfflineState();
      await repo.refreshConnectedAccountProfile();
      await _notifier.loadSounds();
      if (mounted) AppSnackBar.show(context, 'Session Google renouvelée');
    } on GoogleOAuthNotConfiguredException catch (e) {
      if (mounted) {
        AppSnackBar.show(context, e.message,
            duration: const Duration(seconds: 8));
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          'Reconnexion impossible — réessayez depuis les réglages.',
          action: SnackBarAction(
            label: 'Réglages',
            onPressed: () =>
                unawaited(_openSettings(scrollToDriveSection: true)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _driveReconnectInFlight = false);
    }
  }

  /// Ouvre la recherche-éclair (overlay) ; met en évidence le pad dédié préparé.
  /// [typeFilter] pré-filtre sur un type de son (Ctrl+G/H/J).
  Future<void> _openQuickSearch({SoundType? typeFilter}) async {
    final result = await QuickSearchOverlay.show(
      context,
      notifier: _notifier,
      initialTypeFilter: typeFilter,
      onReconnect: () => unawaited(_reconnectDriveInline()),
    );
    if (!mounted) return;
    // Les pré-écoutes (bruitages/ambiances) jouent jusqu'à la fin et se libèrent
    // seules ; les musiques jouent dans la régie. Rien à couper à la fermeture.
    final padId = result?.highlightPadId;
    if (padId == null) return;
    _emphasizePad(padId);
  }

  Future<void> _handleAddPadShortcut() async {
    if (!isNativeDesktopPlatform() || !mounted) return;
    final board = _notifier.state.selectedBoard;
    if (board == null) return;
    final pads = _notifier.state.pads;
    final lastRowIndex = pads.isEmpty
        ? 0
        : pads.map((p) => p.pad.rowIndex).reduce(max);
    await _openAddPadFlow(board, rowIndex: lastRowIndex);
  }

  Future<void> _handleUndoShortcut() async {
    if (!isNativeDesktopPlatform() || !mounted) return;
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

    final padItem = await _notifier.commitDraftPad(
      draftPadId: draftPadId,
      soundIds: [],
    );
    if (!mounted || padItem == null) return;

    await PadDetailsScreen.open(
      context,
      padItem: padItem,
      notifier: _notifier,
      openPickerOnStart: true,
    );

    if (!mounted) return;
    final current = _notifier.findPadItemById(padItem.pad.id);
    if (current != null && current.pad.sounds.isEmpty) {
      await _notifier.removeSound(current);
    }
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
    final box = _editGridContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;

    final draggedId = excludePadId ?? _draggingPadId;
    final local = box.globalToLocal(global);
    var y = 0.0;

    for (final rowIdx in rowIndices) {
      final pads = rowMap[rowIdx] ?? [];
      // +1 : chaque ligne rend un slot « + » de fin en plus des pads.
      final height = _editWrapHeight(pads.length + 1, cellHeight, slotsPerRow);
      if (local.dy < y + height + _editRowGap / 2) {
        final visibleCount = pads.where((p) => p.pad.id != draggedId).length;
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
      // +1 : slot « + » de fin de ligne rendu en plus des pads.
      final count = (rowMap[rowIndices[i]]?.length ?? 0) + 1;
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

    unawaited(
      _notifier.movePadToPosition(padId, target.rowIndex, target.position),
    );
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
      final controller = _normalGridScrollController;
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
    if (pad.isDraft) return true;
    if (!_notifier.isLiveOfflineMode) return true;
    return _notifier.isPadVisibleInOfflineMode(pad);
  }

  /// Entre/sort du Mode Spectacle : verrouille l'édition (croix, ajout) mais
  /// laisse le déplacement des pads possible, et suspend les push Drive auto
  /// pour éviter tout jank pendant le live.
  void _togglePerformanceMode() {
    setState(() {
      _isPerformanceMode = !_isPerformanceMode;
      // Une bascule pendant un drag laisserait un état de glisser orphelin.
      if (_isPerformanceMode) {
        _draggingPadId = null;
        _dropTarget = null;
        _editDragUiReady = false;
      }
    });
    final syncController = widget.services.syncController;
    if (_isPerformanceMode) {
      syncController.pauseAutoSync();
      _notifier.markPerformanceModeEntered();
    } else {
      syncController.resumeAutoSync();
    }
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
    // Mode Spectacle : le slot « + » occupe toujours sa place dans la grille
    // (géométrie de drag inchangée) mais reste invisible et inerte — seul le
    // déplacement des pads existants reste permis.
    if (!_isEditable) return const SizedBox.shrink();

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
    return _wrapMusicRegieTapTarget(card);
  }

  static const Duration _addSlotTransitionDuration = Duration(
    milliseconds: 240,
  );

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
              child: _buildAddToRowButton(context, board, rowIndex: rowIndex),
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
          child: Transform.scale(scale: 0.94 + 0.06 * value, child: child),
        );
      },
      child: child,
    );
  }

  /// Cellules d'une ligne de la grille.
  ///
  /// - Mode classique (`editable`) : pads déplaçables (via [buildCommittedCell])
  ///   + slot « + » de fin de ligne (qui se transforme en pad lors d'un ajout).
  /// - Mode Spectacle (verrouillé) : pads simples, sans « + » ni croix.
  List<Widget> _buildRowCells({
    required BuildContext context,
    required SamplerState state,
    required SoundBoard board,
    required int rowIndex,
    required List<PadItem> rowPads,
    required double cellWidth,
    required double cellHeight,
    required bool editable,
    Widget Function(PadItem pad)? buildCommittedCell,
  }) {
    final committed = rowPads.where((pad) => !pad.isDraft).toList();

    Widget plainCell(PadItem pad) => SizedBox(
      key: ValueKey<int>(pad.pad.id),
      width: cellWidth,
      height: cellHeight,
      child: _buildPadWidget(context, state, pad),
    );

    if (!editable) {
      return [for (final pad in committed) plainCell(pad)];
    }

    PadItem? draft;
    for (final pad in rowPads) {
      if (pad.isDraft) {
        draft = pad;
        break;
      }
    }

    final cells = <Widget>[
      for (final pad in committed)
        buildCommittedCell != null ? buildCommittedCell(pad) : plainCell(pad),
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
            child: _buildAddToRowButton(context, board, rowIndex: rowIndex),
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
        final displayRowIndices = hasPads ? rowIndices : [0];

        // Grille interactive, déplacement (glisser immédiat) toujours permis —
        // y compris en Mode Spectacle. Croix de suppression, crayon et slots
        // « + » restent gérés par `_isEditable` (voir `_buildPadWidget` et
        // `_buildAddToRowButton`) et disparaissent hors du mode classique.
        // Une ligne « nouvelle rangée » finale accueille un pad déposé sous la
        // grille.
        final newRowIndex = hasPads ? rowIndices.last + 1 : null;

        final dropTarget = _dropTarget;
        final showDragPreview = _editDragUiReady && _draggingPadId != null;
        final visualRowMap = showDragPreview && dropTarget != null
            ? _previewRowMap(
                rowMap: rowMap,
                padId: _draggingPadId!,
                targetRowIndex: dropTarget.rowIndex,
                insertionPosition: dropTarget.position,
              )
            : rowMap;

        final hitTestHeight = _editGridTotalHeight(
          rowIndices: displayRowIndices,
          rowMap: rowMap,
          cellHeight: cellHeight,
          slotsPerRow: crossAxisCount,
          includeNewRowSpacer: newRowIndex != null,
        );

        // Enveloppe un pad déplaçable.
        //
        // - Desktop (souris) : glisser immédiat.
        // - Tactile (mobile) : appui long, pour ne pas confisquer le scroll de
        //   la grille ni le tap de déclenchement.
        Widget buildDraggablePadCell(PadItem padItem) {
          final rowIdx = padItem.pad.rowIndex;
          final rowPads = rowMap[rowIdx] ?? [];
          final indexInRow = rowPads.indexWhere(
            (p) => p.pad.id == padItem.pad.id,
          );

          Offset anchorStrategy(
            Draggable<Object> draggable,
            BuildContext context,
            Offset position,
          ) => Offset(cellWidth / 2, cellHeight / 2);

          void onDragStarted() {
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
          }

          void Function(DragUpdateDetails)? onDragUpdate = newRowIndex == null
              ? null
              : (details) {
                  _lastDragGlobalOffset = details.globalPosition;
                  final target = _resolveEditDropTarget(
                    global: details.globalPosition,
                    rowMap: rowMap,
                    rowIndices: displayRowIndices,
                    newRowIndex: newRowIndex,
                    cellWidth: cellWidth,
                    cellHeight: cellHeight,
                    slotsPerRow: crossAxisCount,
                    excludePadId: padItem.pad.id,
                  );
                  if (target != null) {
                    _updateDropTarget(target.rowIndex, target.position);
                  }
                };

          void onDragEnd(DraggableDetails details) {
            _finishPadDrag(
              padItem.pad.id,
              _lastDragGlobalOffset ?? details.offset,
              rowMap: rowMap,
              rowIndices: displayRowIndices,
              newRowIndex: newRowIndex ?? rowIdx,
              cellWidth: cellWidth,
              cellHeight: cellHeight,
              slotsPerRow: crossAxisCount,
            );
          }

          final feedback = Material(
            type: MaterialType.transparency,
            child: Opacity(
              opacity: 0.88,
              child: SizedBox(
                width: cellWidth,
                height: cellHeight,
                child: PadCard(
                  padItem: padItem,
                  isEditable: false,
                  isTapBlocked: (_) => false,
                ),
              ),
            ),
          );

          final dragKey = ValueKey('draggable_${padItem.pad.id}');
          final child = _buildPadWidget(context, state, padItem);

          final Widget draggable = context.prefersDesktopUi
              ? ThresholdDraggable<int>(
                  key: dragKey,
                  data: padItem.pad.id,
                  dragAnchorStrategy: anchorStrategy,
                  onDragStarted: onDragStarted,
                  onDragUpdate: onDragUpdate,
                  onDragEnd: onDragEnd,
                  feedback: feedback,
                  childWhenDragging: const SizedBox.shrink(),
                  child: child,
                )
              : LongPressDraggable<int>(
                  key: dragKey,
                  data: padItem.pad.id,
                  dragAnchorStrategy: anchorStrategy,
                  onDragStarted: onDragStarted,
                  onDragUpdate: onDragUpdate,
                  onDragEnd: onDragEnd,
                  feedback: feedback,
                  childWhenDragging: const SizedBox.shrink(),
                  child: child,
                );

          return SizedBox(
            key: ValueKey('pad_${padItem.pad.id}'),
            width: cellWidth,
            height: cellHeight,
            child: draggable,
          );
        }

        // Mêmes rangées que la grille interactive, mais contenu reflué
        // (visualRowMap) pour matérialiser le trou de dépôt. Les slots « + »
        // « Ajouter un pad » restent visibles pendant le déplacement.
        List<Widget> previewRowCells(int rowIndex) {
          return [
            for (final pad in visualRowMap[rowIndex] ?? [])
              SizedBox(
                key: ValueKey('pad_prev_${pad.pad.id}'),
                width: cellWidth,
                height: cellHeight,
                child: PadCard(
                  padItem: pad,
                  isEditable: true,
                  isTapBlocked: (_) => false,
                ),
              ),
            SizedBox(
              width: cellWidth,
              height: cellHeight,
              child: _buildAddToRowButton(
                context,
                selectedBoard,
                rowIndex: rowIndex,
              ),
            ),
          ];
        }

        Widget buildPreviewColumn() {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < displayRowIndices.length; i++) ...[
                if (i > 0) const SizedBox(height: _editRowGap),
                Wrap(
                  spacing: _editRowGap,
                  runSpacing: _editRowGap,
                  children: previewRowCells(displayRowIndices[i]),
                ),
              ],
              if (newRowIndex != null) ...[
                const SizedBox(height: _editRowGap),
                Wrap(
                  spacing: _editRowGap,
                  runSpacing: _editRowGap,
                  children: previewRowCells(newRowIndex),
                ),
              ],
            ],
          );
        }

        return SingleChildScrollView(
          key: const ValueKey('pads_editable_rows'),
          controller: _normalGridScrollController,
          padding: _padsGridScrollPadding(context),
          child: _EditGridAnchor(
            onAttached: (ctx) => _editGridContext = ctx,
            onDetached: (ctx) {
              if (identical(_editGridContext, ctx)) {
                _editGridContext = null;
              }
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Grille interactive (invisible pendant la prévisualisation).
                // IgnorePointer pendant le drag : sinon le calque masqué continue
                // de capter le survol souris et affiche le tooltip du slot « + ».
                IgnorePointer(
                  ignoring: showDragPreview,
                  child: Opacity(
                    opacity: showDragPreview ? 0 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = 0; i < displayRowIndices.length; i++) ...[
                          if (i > 0) const SizedBox(height: _editRowGap),
                          Wrap(
                            spacing: _editRowGap,
                            runSpacing: _editRowGap,
                            children: _buildRowCells(
                              context: context,
                              state: state,
                              board: selectedBoard,
                              rowIndex: displayRowIndices[i],
                              rowPads: rowMap[displayRowIndices[i]] ?? const [],
                              cellWidth: cellWidth,
                              cellHeight: cellHeight,
                              editable: true,
                              buildCommittedCell: buildDraggablePadCell,
                            ),
                          ),
                        ],
                        if (newRowIndex != null) ...[
                          const SizedBox(height: _editRowGap),
                          Wrap(
                            spacing: _editRowGap,
                            runSpacing: _editRowGap,
                            children: _buildRowCells(
                              context: context,
                              state: state,
                              board: selectedBoard,
                              rowIndex: newRowIndex,
                              rowPads: const [],
                              cellWidth: cellWidth,
                              cellHeight: cellHeight,
                              editable: true,
                              buildCommittedCell: buildDraggablePadCell,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Zone de hit-test stable (layout courant, pas la prévisualisation).
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: hitTestHeight,
                  child: const IgnorePointer(child: SizedBox.expand()),
                ),
                // Prévisualisation par-dessus (les événements passent au Draggable).
                if (showDragPreview)
                  Positioned.fill(
                    child: IgnorePointer(child: buildPreviewColumn()),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _wrapMusicRegieTapTarget(Widget child) {
    if (!_isMusicRegieAdvanced) return child;
    return TapRegion(groupId: _musicRegieTapGroup, child: child);
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

    if (_notifier.isLiveOfflineMode && !resolved.hasLocallyAvailableSound) {
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
      debugPrint(
        '[TAP] pad="${resolved.pad.displayName}" → appearsReady, refreshing players',
      );
      unawaited(HapticFeedback.selectionClick());
      await _notifier.refreshPadPlayback(resolved.pad.id);
      if (!mounted) return;
      final after = _notifier.findPadItemById(resolved.pad.id) ?? resolved;
      debugPrint(
        '[TAP] pad="${resolved.pad.displayName}" → after refresh: isPlayable=${after.isPlayable}',
      );
      if (after.isPlayable) {
        await _notifier.toggleSound(after);
      }
      return;
    }

    final reason = resolved.unavailabilityReason;

    if (reason == PadUnavailabilityReason.offline ||
        reason == PadUnavailabilityReason.unsupportedFormat) {
      debugPrint(
        '[TAP] pad="${resolved.pad.displayName}" → BLOQUÉ reason=$reason',
      );
      unawaited(HapticFeedback.heavyImpact());
      _showBlockedPadFeedback(resolved, reason);
      return;
    }

    if (reason == PadUnavailabilityReason.missingFile ||
        _notifier.isPadTapBlocked(resolved)) {
      debugPrint(
        '[TAP] pad="${resolved.pad.displayName}" → BLOQUÉ reason=$reason',
      );
      return;
    }

    if (!_notifier.allowsSoundDownload) return;

    debugPrint(
      '[TAP] pad="${resolved.pad.displayName}" → EN ROUTE / preparing',
    );
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
    // déjà prêt : c'est désormais un bouton GO.
    if (resolved.isPlayable) return;

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
      PadUnavailabilityReason.offline when _notifier.driveSessionExpired =>
        'Session Google expirée — touchez « Reconnecter »',
      PadUnavailabilityReason.offline =>
        '« ${padItem.displayName} » indisponible hors-ligne',
      PadUnavailabilityReason.missingFile =>
        'Fichier introuvable pour « ${padItem.displayName} »',
      PadUnavailabilityReason.unsupportedFormat =>
        'Format audio non supporté pour « ${padItem.displayName} »',
      _ => '« ${padItem.displayName} » non téléchargé',
    };
    // Session expirée : proposer la reconnexion plutôt que le détail du pad,
    // qui ne dirait rien de la vraie cause.
    final action = _reconnectSnackBarAction() ??
        SnackBarAction(
          label: 'Détails',
          onPressed: () => _showPadUnavailableSheet(context, padItem),
        );
    AppSnackBar.show(context, text, action: action);
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
        builder: (ctx) =>
            _PadDownloadSheet(padItem: padItem, notifier: _notifier),
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
    final editable = _isEditable;
    // Croix (suppression) et crayon (détails) ne concernent que les pads
    // confirmés en mode classique — jamais un brouillon en cours de création
    // ni le Mode Spectacle (verrouillé).
    final showEditAffordances = editable && !padItem.isDraft;
    return _wrapMusicRegieTapTarget(
      PadCard(
        key: ValueKey<int>(padItem.pad.id),
        padItem: padItem,
        isEditable: editable,
        isTapBlocked: _notifier.isPadTapBlocked,
        animateOnRestore: _recentlyRestoredSoundId == padItem.pad.id,
        isHighlighted: _highlightedPadId == padItem.pad.id,
        onTap: () => unawaited(_handlePadTap(context, padItem)),
        onEdit: showEditAffordances
            ? () {
                final live =
                    _notifier.findPadItemById(padItem.pad.id) ?? padItem;
                PadDetailsScreen.open(
                  context,
                  padItem: live,
                  notifier: _notifier,
                );
              }
            : null,
        onRemove: showEditAffordances
            ? () async {
                final removed = await _notifier.removeSound(padItem);
                if (!mounted || !removed) return;
              }
            : null,
        onShowSounds: padItem.totalSoundCount > 1
            ? () => _showPadSoundPicker(context, padItem)
            : null,
      ),
    );
  }

  /// Overlay listant les sons d'un multipad — permet de déclencher une
  /// variante précise plutôt que de laisser le pad piocher automatiquement.
  void _showPadSoundPicker(BuildContext context, PadItem padItem) {
    unawaited(SoundPickerOverlay.showForPadVariant(
      context,
      notifier: _notifier,
      padItem: padItem,
    ));
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
        // Inclut l'id du board : sinon le switcher ne remonte pas la grille
        // au changement de scène (et une GlobalKey partagée plantait ici).
        key: ValueKey<String>(
          selectedBoard == null
              ? (isBoardsLoading ? 'boards_loading' : 'boards_empty')
              : state.isLoading && state.pads.isEmpty
              ? 'sounds_loading_${selectedBoard.id}'
              : state.error != null && state.pads.isEmpty
              ? 'sounds_error_${selectedBoard.id}'
              : 'sounds_grid_${selectedBoard.id}',
        ),
        builder: (context) {
          if (selectedBoard == null) {
            if (isBoardsLoading) {
              return const SizedBox.shrink();
            }
            return const Center(child: Text('Aucune scène disponible'));
          }
          if (state.isLoading && state.pads.isEmpty) {
            return const SizedBox.shrink();
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
          final downloadableCount = state.pads
              .where(_notifier.isPadPreparable)
              .length;
          final showPrepareBanner =
              _notifier.allowsSoundDownload &&
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
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
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
        isDesktop: context.prefersDesktopUi,
        isLocked: _isMusicRegieLocked,
        onLockedChanged: context.prefersDesktopUi
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
        onSeekMusic: (position) =>
            unawaited(_notifier.seekPausedMusic(position)),
        onOccupiedHeightChanged: context.prefersDesktopUi
            ? null
            : (height) {
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
                unawaited(_notifier.stopAllNonMusicSounds());
              }
              return null;
            },
          ),
          _QuickSearchFilteredIntent: CallbackAction<_QuickSearchFilteredIntent>(
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
                ? _SamplerDesktopAppBar(
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
                    stopAllButton: _StopAllButton(notifier: _notifier),
                  )
                : _SamplerAppBar(
                    selectedBoard: selectedBoard,
                    isPerformanceMode: _isPerformanceMode,
                    onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
                    onTogglePerformanceMode: _togglePerformanceMode,
                    onQuickSearch: () => unawaited(_openQuickSearch()),
                    stopAllButton: _StopAllButton(notifier: _notifier),
                  ),
            drawer: prefersDesktopUi
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

// ---------- AppBar (mobile/tablette) ----------

class _SamplerAppBar extends StatelessWidget implements PreferredSizeWidget {
  final SoundBoard? selectedBoard;
  final bool isPerformanceMode;
  final VoidCallback onOpenMenu;
  final VoidCallback onTogglePerformanceMode;
  final VoidCallback onQuickSearch;
  final Widget stopAllButton;

  const _SamplerAppBar({
    required this.selectedBoard,
    required this.isPerformanceMode,
    required this.onOpenMenu,
    required this.onTogglePerformanceMode,
    required this.onQuickSearch,
    required this.stopAllButton,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      automaticallyImplyLeading: false,
      leading: isPerformanceMode
          ? null
          : IconButton(
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
        // Vumètre de sortie : uniquement là où la barre a la place (tablette+).
        if (context.deviceClass.isAtLeastTablet)
          const Center(child: AudioVuMeter()),
        stopAllButton,
        IconButton(
          icon: const Icon(Icons.search_rounded),
          tooltip: 'Recherche rapide',
          onPressed: onQuickSearch,
        ),
        _LiveModeButton(
          isPerformanceMode: isPerformanceMode,
          onToggle: onTogglePerformanceMode,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

// ---------- Bouton « Tout arrêter » (bruitages) ----------

/// Bouton panique : coupe d'un coup tous les pads non-musique en cours, sans
/// toucher au tapis musical. Actif uniquement quand au moins un bruitage joue.
class _StopAllButton extends StatelessWidget {
  final SamplerNotifier notifier;

  const _StopAllButton({required this.notifier});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) {
        final active = notifier.hasNonMusicSoundsPlaying;
        return IconButton(
          icon: const Icon(Icons.stop_circle_rounded),
          tooltip: isNativeDesktopPlatform()
              ? 'Tout arrêter (Échap)'
              : 'Tout arrêter',
          color: active ? scheme.error : null,
          onPressed: active
              ? () {
                  unawaited(HapticFeedback.heavyImpact());
                  unawaited(notifier.stopAllNonMusicSounds());
                }
              : null,
        );
      },
    );
  }
}

// ---------- Bouton mode live ----------

/// Bascule du mode live : verrouille l'édition et suspend la sync auto
/// pour un spectacle sans modif accidentelle ni jank (refonte UX P2).
class _LiveModeButton extends StatelessWidget {
  final bool isPerformanceMode;
  final VoidCallback onToggle;

  const _LiveModeButton({
    required this.isPerformanceMode,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: isPerformanceMode
          ? 'Quitter le mode live'
          : 'Mode live',
      onPressed: onToggle,
      icon: isPerformanceMode
          ? const _LiveModeActiveIcon()
          : Icon(Icons.theater_comedy_outlined, color: scheme.onSurfaceVariant),
    );
  }
}

/// Masque théâtre + voyant rouge pulsé — même langage visuel que le badge ON AIR.
class _LiveModeActiveIcon extends StatefulWidget {
  const _LiveModeActiveIcon();

  @override
  State<_LiveModeActiveIcon> createState() => _LiveModeActiveIconState();
}

class _LiveModeActiveIconState extends State<_LiveModeActiveIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _pulse = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 1.0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(Icons.theater_comedy_rounded, color: scheme.error),
          Positioned(
            right: -2,
            top: -2,
            child: FadeTransition(
              opacity: _pulse,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: scheme.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
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
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              if (isBoardsLoading)
                const _BoardsListSkeleton()
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
  final Future<void> Function(SoundBoard board) onSelectBoard;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function(SoundBoard board, Offset position)
  onBoardContextMenu;
  final bool isPerformanceMode;
  final VoidCallback onTogglePerformanceMode;
  final Future<void> Function() onOpenLibrary;
  final Future<void> Function() onOpenSettings;
  final VoidCallback onQuickSearch;
  final Widget stopAllButton;

  const _SamplerDesktopAppBar({
    required this.selectedBoard,
    required this.boards,
    required this.isBoardsLoading,
    required this.onSelectBoard,
    required this.onCreateBoard,
    required this.onBoardContextMenu,
    required this.isPerformanceMode,
    required this.onTogglePerformanceMode,
    required this.onOpenLibrary,
    required this.onOpenSettings,
    required this.onQuickSearch,
    required this.stopAllButton,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      automaticallyImplyLeading: false,
      title: _BoardSceneSelector(
        boards: boards,
        selectedBoard: selectedBoard,
        isBoardsLoading: isBoardsLoading,
        onSelectBoard: onSelectBoard,
        onCreateBoard: onCreateBoard,
        onBoardContextMenu: onBoardContextMenu,
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
          height: 1,
        ),
      ),
      actions: [
        if (!isPerformanceMode) ...[
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Paramètres',
            onPressed: () => unawaited(onOpenSettings()),
          ),
          IconButton(
            icon: const Icon(Icons.library_books_rounded),
            tooltip: 'Gérer la bibliothèque',
            onPressed: () => unawaited(onOpenLibrary()),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: VerticalDivider(width: 24),
          ),
        ],
        stopAllButton,
        IconButton(
          icon: const Icon(Icons.search_rounded),
          tooltip: 'Recherche rapide (Ctrl+F)',
          onPressed: onQuickSearch,
        ),
        _LiveModeButton(
          isPerformanceMode: isPerformanceMode,
          onToggle: onTogglePerformanceMode,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

// ---------- Sélecteur de scène (desktop) ----------

class _BoardSceneSelector extends StatelessWidget {
  final List<SoundBoard> boards;
  final SoundBoard? selectedBoard;
  final bool isBoardsLoading;
  final Future<void> Function(SoundBoard board) onSelectBoard;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function(SoundBoard board, Offset position)
  onBoardContextMenu;

  const _BoardSceneSelector({
    required this.boards,
    required this.selectedBoard,
    required this.isBoardsLoading,
    required this.onSelectBoard,
    required this.onCreateBoard,
    required this.onBoardContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<Object>(
        tooltip: '',
        offset: const Offset(0, 48),
        onSelected: (value) async {
          if (value is SoundBoard) {
            await onSelectBoard(value);
          } else if (value == 'create') {
            await onCreateBoard();
          }
        },
        itemBuilder: (context) => [
          if (isBoardsLoading)
            const PopupMenuItem<Object>(
              enabled: false,
              child: Skeleton(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(widthFactor: 0.7),
                    SizedBox(height: 14),
                    SkeletonLine(widthFactor: 0.5),
                    SizedBox(height: 14),
                    SkeletonLine(widthFactor: 0.6),
                  ],
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
                    if (board.id == selectedBoard?.id)
                      Icon(Icons.check_rounded, size: 18, color: scheme.primary)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: AppSpacing.sm),
                    if (board.color != null) ...[
                      _BoardTileIcon(color: board.color!),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(child: Text(board.name)),
                  ],
                ),
              ),
            ),
          const PopupMenuDivider(),
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
        ],
        child: GestureDetector(
          onSecondaryTapDown: selectedBoard != null
              ? (details) =>
                    onBoardContextMenu(selectedBoard!, details.globalPosition)
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BoardTitleLabel(board: selectedBoard),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
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

// ---------- Placeholders de chargement ----------

/// Liste de scènes factices pour le tiroir latéral pendant le chargement.
class _BoardsListSkeleton extends StatelessWidget {
  const _BoardsListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Column(
        children: [
          for (int i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              child: Row(
                children: [
                  const SkeletonBox(
                    width: 18,
                    height: 18,
                    borderRadius: AppRadius.radiusXs,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SkeletonLine(widthFactor: i.isEven ? 0.6 : 0.45),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Ancre la grille pour le hit-test de drop sans [GlobalKey] (sécurise
/// [AnimatedSwitcher] qui conserve brièvement l'ancien enfant).
class _EditGridAnchor extends StatefulWidget {
  const _EditGridAnchor({
    required this.onAttached,
    required this.onDetached,
    required this.child,
  });

  final ValueChanged<BuildContext> onAttached;
  final ValueChanged<BuildContext> onDetached;
  final Widget child;

  @override
  State<_EditGridAnchor> createState() => _EditGridAnchorState();
}

class _EditGridAnchorState extends State<_EditGridAnchor> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_register);
  }

  @override
  void didUpdateWidget(covariant _EditGridAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback(_register);
  }

  void _register(Duration _) {
    if (!mounted) return;
    widget.onAttached(context);
  }

  @override
  void dispose() {
    widget.onDetached(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
