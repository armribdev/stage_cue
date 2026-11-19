import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../models/keyboard_layout.dart';
import '../providers/sampler_provider.dart';
import 'threshold_draggable.dart';

/// Vue « clavier » d'un board : chaque pad est posé sur la touche qui le
/// déclenche (`AppPreferences.hotkeyForPad`), les touches sans pad restent
/// dessinées en creux. Un pad sans touche dessinée (aucune, collision,
/// flèches…) n'apparaît pas ici : il se place par le menu d'une touche vide.
///
/// Un clic sur un pad le déclenche ([onTap], le même chemin que la grille et
/// que le raccourci clavier). Quand [onAssign] est fourni, on y assigne aussi
/// les touches : glisser un pad sur une touche (vide : il s'y place ; occupée :
/// les deux s'échangent), le lâcher **ailleurs que sur une touche** (il perd sa
/// touche), ou cliquer une touche vide pour choisir un pad.
class KeyboardPadsView extends StatefulWidget {
  /// Pads à montrer, dans l'ordre du board (brouillons exclus par l'appelant).
  final List<PadItem> pads;
  final int? Function(int padId) hotkeyForPad;
  final void Function(PadItem padItem) onTap;

  /// Applique des changements de touches (`padId → keyId`, `null` = retirer).
  /// `null` verrouille l'assignation (Mode Spectacle).
  final Future<void> Function(Map<int, int?> changes)? onAssign;

  /// Ouvre les réglages du pad (appui long ou clic droit) ; `null` en Mode
  /// Spectacle, où l'édition est verrouillée.
  final void Function(PadItem padItem)? onEdit;
  final int? highlightedPadId;
  final EdgeInsets padding;

  /// Carte d'un pad dans le panneau du bas, la même que celle de la grille.
  /// Le panneau (tous les pads, ceux déjà sur une touche estompés) n'existe que
  /// quand l'assignation est permise et que ce builder est fourni : il sert de
  /// réserve d'où glisser les pads vers les touches.
  final Widget Function(BuildContext context, PadItem padItem)? trayCardBuilder;

  /// Largeur cible d'une carte et espacement du panneau : ceux de la grille,
  /// pour que les cartes aient exactement la même taille et la même coupe.
  final double trayItemWidth;
  final double trayGap;

  const KeyboardPadsView({
    super.key,
    required this.pads,
    required this.hotkeyForPad,
    required this.onTap,
    this.onAssign,
    this.onEdit,
    this.highlightedPadId,
    this.padding = const EdgeInsets.all(16),
    this.trayCardBuilder,
    this.trayItemWidth = 180,
    this.trayGap = 14,
  });

  @override
  State<KeyboardPadsView> createState() => _KeyboardPadsViewState();
}

class _KeyboardPadsViewState extends State<KeyboardPadsView> {
  /// Côté maximal d'une touche : au-delà, le clavier ne ressemblerait plus à un
  /// clavier. En dessous, la touche rétrécit avec la fenêtre.
  static const double _maxUnit = 72;

  /// Part de la hauteur que le panneau de pads peut prendre avant de défiler :
  /// le clavier garde de la place.
  static const double _trayMaxHeightFraction = 0.45;

  /// Un pad est en cours de glisser. Notifier plutôt que `setState` : seule la
  /// rappel de dépôt en dépend, et reconstruire la vue au démarrage du
  /// geste démonterait le `Draggable` en cours d'accrochage.
  final ValueNotifier<bool> _isDragging = ValueNotifier<bool>(false);

  late KeyboardPadAssignment _assignment;

  @override
  void dispose() {
    _isDragging.dispose();
    super.dispose();
  }

  bool get _canAssign => widget.onAssign != null;

  void _apply(Map<int, int?> changes) {
    final onAssign = widget.onAssign;
    if (onAssign == null || changes.isEmpty) return;
    onAssign(changes);
  }

  void _dropPad(int padId, int? targetKeyId) {
    PadItem? dragged;
    for (final item in widget.pads) {
      if (item.pad.id == padId) dragged = item;
    }
    if (dragged == null) return;
    _apply(
      planPadDrop(
        dragged: dragged,
        targetKeyId: targetKeyId,
        assignment: _assignment,
        hotkeyForPad: widget.hotkeyForPad,
      ),
    );
  }

  /// Clic sur une touche vide : menu des pads sans touche sur le clavier.
  Future<void> _openAssignMenu(
    BuildContext context,
    Offset position,
    KeyboardKeySpec key,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final loose = _assignment.loose;
    final chosen = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      popUpAnimationStyle: AnimationStyle.noAnimation,
      items: [
        PopupMenuItem<int>(
          enabled: false,
          height: AppMenu.itemHeight,
          padding: AppMenu.itemPadding,
          child: Text(
            'ASSIGNER À ${key.label}',
            style: AppTextStyles.sectionLabel(context),
          ),
        ),
        if (loose.isEmpty)
          const PopupMenuItem<int>(
            enabled: false,
            height: AppMenu.itemHeight,
            padding: AppMenu.itemPadding,
            child: Text('Tous les pads ont une touche'),
          ),
        for (final item in loose)
          PopupMenuItem<int>(
            value: item.pad.id,
            height: AppMenu.itemHeight,
            padding: AppMenu.itemPadding,
            child: Text(
              item.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
    if (chosen != null) _dropPad(chosen, key.keyId);
  }

  @override
  Widget build(BuildContext context) {
    _assignment = assignPadsToKeys(widget.pads, widget.hotkeyForPad);
    final padding = widget.padding;
    final cardBuilder = widget.trayCardBuilder;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - padding.horizontal;
        final unit = math.max(
          0.0,
          math.min(_maxUnit, available / kAzertyWidthUnits),
        );
        // Dans un défilement la hauteur n'est pas bornée : sans hauteur
        // minimale, `Center` ne centrerait que horizontalement. La hauteur
        // utile est celle de la zone du clavier, panneau de pads exclu.
        Widget buildKeyboard() => LayoutBuilder(
          builder: (context, area) => SingleChildScrollView(
            padding: padding,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(0, area.maxHeight - padding.vertical),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final row in kAzertyRows) _buildRow(row, unit),
                  ],
                ),
              ),
            ),
          ),
        );
        if (!_canAssign) return buildKeyboard();
        final assignedIds = {
          for (final item in _assignment.onKeys.values) item.pad.id,
        };
        // Toute la zone, panneau compris, est une cible : lâcher un pad
        // ailleurs que sur une touche (les cibles des touches, plus profondes,
        // passent avant) lui retire sa touche.
        return DragTarget<int>(
          onAcceptWithDetails: (details) => _dropPad(details.data, null),
          builder: (context, candidates, _) => Column(
            // Pleine largeur : sans cela le panneau se rétrécit à son contenu
            // et se retrouve centré au lieu de partir du bord, comme la grille.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    buildKeyboard(),
                    _UnassignHint(
                      isDragging: _isDragging,
                      isOver: candidates.isNotEmpty,
                    ),
                  ],
                ),
              ),
              if (cardBuilder != null && widget.pads.isNotEmpty)
                _PadTray(
                  pads: widget.pads,
                  assignedIds: assignedIds,
                  cardBuilder: cardBuilder,
                  isDragging: _isDragging,
                  itemWidth: widget.trayItemWidth,
                  gap: widget.trayGap,
                  padding: padding,
                  maxHeight: constraints.maxHeight * _trayMaxHeightFraction,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRow(KeyboardRow row, double unit) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: row.indent * unit),
        for (final key in row.keys)
          SizedBox(
            width: key.width * unit,
            height: unit,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: _buildKey(key),
            ),
          ),
      ],
    );
  }

  Widget _buildKey(KeyboardKeySpec key) {
    final padItem = _assignment.onKeys[key.keyId];
    final Widget content = padItem == null
        ? _EmptyKey(
            label: key.label,
            onTapUp: _canAssign
                ? (context, position) => _openAssignMenu(context, position, key)
                : null,
          )
        : _DraggablePad(
            padItem: padItem,
            enabled: _canAssign,
            isDragging: _isDragging,
            child: _PadTileFrame(
              padItem: padItem,
              onTap: widget.onTap,
              onEdit: widget.onEdit,
              isHighlighted: widget.highlightedPadId == padItem.pad.id,
              child: _PadKeyBody(label: key.label, padItem: padItem),
            ),
          );
    if (!_canAssign) return content;
    return _DropZone(
      onDrop: (padId) => _dropPad(padId, key.keyId),
      child: content,
    );
  }
}

/// Rappel affiché pendant un glisser : lâcher hors d'une touche retire la
/// touche du pad. Passe à l'accent quand le pointeur est bien hors des touches.
class _UnassignHint extends StatelessWidget {
  final ValueNotifier<bool> isDragging;
  final bool isOver;

  const _UnassignHint({required this.isDragging, required this.isOver});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: 0,
      right: 0,
      bottom: AppSpacing.lg,
      child: IgnorePointer(
        child: ValueListenableBuilder<bool>(
          valueListenable: isDragging,
          builder: (context, dragging, _) => AnimatedOpacity(
            opacity: dragging ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: AppRadius.radiusMd,
                  border: Border.all(
                    color: isOver
                        ? scheme.primary
                        : AppElevation.border(scheme).color,
                  ),
                ),
                child: Text(
                  "Lâchez hors d'une touche pour retirer sa touche",
                  style: TextStyle(
                    fontSize: 12,
                    color: isOver ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Panneau du bas : tous les pads du board, rangés comme dans la grille (mêmes
/// rangées, même ordre, mêmes cartes, même taille de cellule). Un pad déjà posé
/// sur une touche y est estompé mais reste glissable (il se déplace ou
/// s'échange). Le panneau fait partie de la cible « lâcher hors d'une touche » :
/// y reposer un pad lui retire sa touche.
class _PadTray extends StatelessWidget {
  final List<PadItem> pads;
  final Set<int> assignedIds;
  final Widget Function(BuildContext context, PadItem padItem) cardBuilder;
  final ValueNotifier<bool> isDragging;
  final double itemWidth;
  final double gap;
  final EdgeInsets padding;
  final double maxHeight;

  const _PadTray({
    required this.pads,
    required this.assignedIds,
    required this.cardBuilder,
    required this.isDragging,
    required this.itemWidth,
    required this.gap,
    required this.padding,
    required this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <int, List<PadItem>>{};
    for (final item in pads) {
      rows.putIfAbsent(item.pad.rowIndex, () => []).add(item);
    }
    for (final row in rows.values) {
      row.sort((a, b) => a.pad.sortOrder.compareTo(b.pad.sortOrder));
    }
    final rowIndices = rows.keys.toList()..sort();

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: AppElevation.border(scheme)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Même calcul que la grille de pads.
            final columns = math.max(
              2,
              (constraints.maxWidth / itemWidth).floor(),
            );
            final cellWidth =
                (constraints.maxWidth -
                    padding.horizontal -
                    (columns - 1) * gap) /
                columns;
            final cellHeight = cellWidth / 1.4;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                padding.left,
                AppSpacing.md,
                padding.right,
                padding.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PADS · GLISSEZ-LES SUR UNE TOUCHE',
                    style: AppTextStyles.sectionLabel(context),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (var i = 0; i < rowIndices.length; i++) ...[
                    if (i > 0) SizedBox(height: gap),
                    Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final item in rows[rowIndices[i]]!)
                          SizedBox(
                            key: ValueKey<int>(item.pad.id),
                            width: cellWidth,
                            height: cellHeight,
                            child: Opacity(
                              opacity: assignedIds.contains(item.pad.id)
                                  ? 0.35
                                  : 1,
                              child: _DraggablePad(
                                padItem: item,
                                enabled: true,
                                isDragging: isDragging,
                                child: cardBuilder(context, item),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Rend [child] glissable (donnée : l'id du pad) quand [enabled]. Le geste ne
/// s'accroche qu'après un déplacement (`ThresholdDraggable`), pour qu'un simple
/// clic continue de déclencher le pad.
class _DraggablePad extends StatelessWidget {
  final PadItem padItem;
  final bool enabled;
  final ValueNotifier<bool> isDragging;
  final Widget child;

  const _DraggablePad({
    required this.padItem,
    required this.enabled,
    required this.isDragging,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final scheme = Theme.of(context).colorScheme;
    return ThresholdDraggable<int>(
      data: padItem.pad.id,
      onDragStarted: () => isDragging.value = true,
      onDragEnd: (_) => isDragging.value = false,
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      feedback: Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: AppRadius.radiusMd,
            border: Border.all(color: scheme.primary),
          ),
          child: Text(
            padItem.displayName,
            style: TextStyle(fontSize: 12, color: scheme.onSurface),
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Cible de dépôt d'un pad : un contour d'accent signale la cible survolée.
class _DropZone extends StatelessWidget {
  final void Function(int padId) onDrop;
  final Widget child;

  const _DropZone({required this.onDrop, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<int>(
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidates, _) => Stack(
        children: [
          child,
          if (candidates.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: AppRadius.radiusMd,
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Touche sans pad : un contour discret et son libellé. Cliquable quand
/// [onTapUp] est fourni (assigner un pad).
class _EmptyKey extends StatelessWidget {
  final String label;
  final void Function(BuildContext context, Offset position)? onTapUp;

  const _EmptyKey({required this.label, this.onTapUp});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onTapUp = this.onTapUp;
    final key = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.radiusMd,
        border: Border.fromBorderSide(AppElevation.border(scheme)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            label,
            style: AppFonts.monoStyle(
              TextStyle(
                fontSize: 10,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ),
    );
    if (onTapUp == null) return key;
    return Tooltip(
      message: 'Assigner un pad à cette touche',
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        borderRadius: AppRadius.radiusMd,
        onTapUp: (details) => onTapUp(context, details.globalPosition),
        child: key,
      ),
    );
  }
}

/// Contenu d'une touche occupée : libellé de la touche en haut à gauche, nom du
/// pad dessous.
class _PadKeyBody extends StatelessWidget {
  final String label;
  final PadItem padItem;

  const _PadKeyBody({required this.label, required this.padItem});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppFonts.monoStyle(
              TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                padItem.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.15,
                  fontWeight: padItem.isPlaying
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cadre commun d'un pad dans cette vue (touche ou pastille) : fond et
/// bordure selon l'état — couleur du pad, lecture, disponibilité —, même
/// langage que `PadButton`, en plus compact.
class _PadTileFrame extends StatelessWidget {
  final PadItem padItem;
  final void Function(PadItem padItem) onTap;
  final void Function(PadItem padItem)? onEdit;
  final bool isHighlighted;
  final Widget child;

  const _PadTileFrame({
    required this.padItem,
    required this.onTap,
    required this.onEdit,
    required this.isHighlighted,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Rebuild ciblé sur la révision du pad (téléchargement, disponibilité),
    // comme `PadCard` : l'état d'un pad change sans que la vue soit reconstruite.
    return ListenableBuilder(
      listenable: padItem.revision,
      builder: (context, _) {
        final colorValue = padItem.pad.colorValue;
        final custom = colorValue != null ? Color(colorValue) : null;
        final isReady = padItem.isPlayable || padItem.appearsReady;
        final fill = padItem.isPlaying
            ? (custom?.withValues(alpha: 0.75) ?? scheme.primaryContainer)
            : (custom ??
                  scheme.surfaceContainerHighest.withValues(alpha: 0.75));
        final border = isHighlighted
            ? scheme.primary
            : padItem.isPlaying
            ? scheme.primary.withValues(alpha: 0.85)
            : scheme.outlineVariant.withValues(alpha: 0.45);
        final edit = onEdit;
        return Tooltip(
          message: padItem.displayName,
          waitDuration: const Duration(milliseconds: 600),
          child: Material(
            color: fill,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.radiusMd,
              side: BorderSide(color: border, width: isHighlighted ? 2 : 1),
            ),
            child: InkWell(
              onTap: () => onTap(padItem),
              onLongPress: edit == null ? null : () => edit(padItem),
              onSecondaryTap: edit == null ? null : () => edit(padItem),
              // Pas encore jouable (à télécharger, hors ligne…) : estompé, mais
              // cliquable — un clic lance la préparation, comme sur la grille.
              child: Opacity(opacity: isReady ? 1 : 0.55, child: child),
            ),
          ),
        );
      },
    );
  }
}
