part of 'music_preview_panel.dart';

const _queueDragBorderRadius = 8.0;

class _PassageQueueSection extends StatelessWidget {
  final List<PadItem> queue;
  final bool isDesktop;
  final ValueChanged<int>? onRemove;
  final void Function(int oldIndex, int newIndex)? onReorder;
  final VoidCallback? onChooseMusic;

  /// En deux colonnes, la carte reçoit une hauteur fixe (voir _buildModeBody)
  /// pour égaler la colonne « à l'antenne ». `true` fait remplir cette
  /// hauteur par la liste elle-même (qui défile en interne si elle a plus
  /// d'éléments que de place), au lieu de la laisser pousser la carte plus
  /// haut — c'est ce qui garde « Ajouter à la file » ancré tout en bas sans
  /// jamais faire déborder la carte, quel que soit le nombre d'éléments.
  final bool stretchToFill;

  /// Nombre de lignes que la file doit toujours laisser voir en deux
  /// colonnes, même quand la colonne « à l'antenne » est plus courte.
  static const int minVisibleRows = 4;

  /// Hauteur d'une ligne de file : padding 4+4 autour de l'IconButton
  /// compact (40) de suppression — la plus haute des deux variantes.
  static const double _rowHeight = 48;

  /// Tout ce qui n'est pas la liste : padding de carte (14×2), titre (~20)
  /// + écart (8), écart (10) + bouton « Ajouter à la file » (42), bordures.
  static const double _chromeHeight = 28 + 20 + 8 + 10 + 42 + 2;

  /// Hauteur minimale de la carte étirée pour afficher [minVisibleRows]
  /// éléments sans défiler.
  static const double minStretchHeight =
      _chromeHeight + minVisibleRows * _rowHeight;

  const _PassageQueueSection({
    required this.queue,
    this.isDesktop = false,
    this.onRemove,
    this.onReorder,
    this.onChooseMusic,
    this.stretchToFill = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget content = queue.isEmpty
        ? Text(
            'Préparez la musique suivante sans interrompre celle en cours.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          )
        // Sans stretchToFill, pas de plafond de hauteur : la file utilise
        // toute la place libérée par la suppression du cadre « à l'antenne »
        // (shrinkWrap). Avec stretchToFill, la carte a une hauteur fixe
        // (voir _buildModeBody) : la liste la remplit et défile en interne
        // plutôt que de pousser la carte plus haut que sa colonne voisine.
        : ReorderableListView.builder(
            shrinkWrap: !stretchToFill,
            buildDefaultDragHandles: false,
            padding: EdgeInsets.zero,
            proxyDecorator: _queueDragProxyDecorator,
            itemCount: queue.length,
            onReorderItem: onReorder == null
                ? null
                : (oldIndex, newIndex) => onReorder!(oldIndex, newIndex),
            itemBuilder: (context, index) {
              final padItem = queue[index];
              return _QueueRow(
                key: ValueKey(padItem.pad.id),
                listIndex: index,
                padItem: padItem,
                enableReorder: onReorder != null,
                useDelayedDrag: !isDesktop,
                enableSwipeToRemove: !isDesktop,
                onRemove: onRemove == null
                    ? null
                    : () => onRemove!(padItem.pad.id),
              );
            },
          );
    if (stretchToFill) content = Expanded(child: content);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.radiusLg,
        side: AppElevation.border(scheme),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'File de passage',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            content,
            if (onChooseMusic != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onChooseMusic,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ajouter à la file'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final int listIndex;
  final PadItem padItem;
  final bool enableReorder;
  final bool useDelayedDrag;
  final bool enableSwipeToRemove;
  final VoidCallback? onRemove;

  const _QueueRow({
    super.key,
    required this.listIndex,
    required this.padItem,
    this.enableReorder = false,
    this.useDelayedDrag = true,
    this.enableSwipeToRemove = false,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget content = Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _PadColorChip(padItem: padItem, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  padItem.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _RegieDownloadRing(padItem: padItem, size: 26),
              if (onRemove != null && !enableSwipeToRemove)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (padItem.showsRegieDownloadProgress) ...[
            const SizedBox(height: 6),
            _RegieDownloadBar(padItem: padItem),
          ],
        ],
      ),
    );

    if (enableReorder) {
      content = useDelayedDrag
          ? ReorderableDelayedDragStartListener(
              index: listIndex,
              child: content,
            )
          : ReorderableDragStartListener(
              index: listIndex,
              child: content,
            );
    }

    if (!enableSwipeToRemove || onRemove == null) {
      return content;
    }

    return Dismissible(
      key: ValueKey('dismiss-${padItem.pad.id}'),
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: 0.35},
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(_queueDragBorderRadius),
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          color: scheme.onErrorContainer,
        ),
      ),
      onDismissed: (_) => onRemove!(),
      child: content,
    );
  }
}

/// Pastille couleur alignée sur les pads de la scène.
class _PadColorChip extends StatelessWidget {
  final PadItem padItem;
  final double size;

  const _PadColorChip({
    required this.padItem,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = padItem.pad.colorValue != null
        ? Color(padItem.pad.colorValue!)
        : padItem.pad.sounds.isNotEmpty
            ? soundEffectiveColor(padItem.pad.sounds.first, scheme)
            : scheme.surfaceContainerHighest;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size > 20 ? 8 : 4),
        border: Border.all(
          color: padItem.isPlaying
              ? scheme.primary.withValues(alpha: 0.6)
              : scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: size >= 32
          ? Icon(
              SoundType.music.icon,
              size: size * 0.45,
              color: _chipIconColor(color, scheme),
            )
          : null,
    );
  }

  Color _chipIconColor(Color bg, ColorScheme scheme) {
    return bg.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
  }
}

/// Apparence de l'élément pendant un appui long / glisser pour réordonner.
/// Reprend la couleur de fond surélevée par défaut, sans ombre, avec coins arrondis.
Widget _queueDragProxyDecorator(
  Widget child,
  int index,
  Animation<double> animation,
) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, child) {
      final theme = Theme.of(context);
      final baseColor = theme.canvasColor;
      // Pas d'élévation Material (surfaceTint neutralisé pour la direction
      // "Console Linear") : le retour visuel du drag vient d'un éclaircissement
      // plat de la surface plutôt que d'un glacis de tint.
      final animValue = Curves.easeInOut.transform(animation.value);
      return Material(
        color: Color.lerp(baseColor, AppColors.surface2, animValue),
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(_queueDragBorderRadius),
        child: child,
      );
    },
    child: child,
  );
}

