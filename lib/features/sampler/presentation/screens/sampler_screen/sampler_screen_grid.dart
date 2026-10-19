// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../sampler_screen.dart';

/// Construction de la grille de pads (rangées, emplacement d'ajout, drop targets).
/// Méthodes de [_SamplerScreenState] extraites via extension dans le même `part`.
extension _SamplerScreenGrid on _SamplerScreenState {

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
    return DashedSlotFrame(
      onTap: () => _openAddPadFlow(board, rowIndex: rowIndex),
      child: Center(
        child: Icon(
          Icons.add_rounded,
          size: 24,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }

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
          child: SectionContextAnchor(
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
}
