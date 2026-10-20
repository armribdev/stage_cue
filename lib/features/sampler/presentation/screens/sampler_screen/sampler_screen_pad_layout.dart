// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../sampler_screen.dart';

/// Disposition des pads : glisser-déposer, défilement, mode spectacle, mise en valeur.
/// Méthodes de [_SamplerScreenState] extraites via extension dans le même `part`.
extension _SamplerScreenPadLayout on _SamplerScreenState {
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
      _notifier.startLiveSession();
    } else {
      syncController.resumeAutoSync();
      _notifier.endLiveSession();
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
}
