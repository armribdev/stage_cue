part of 'music_preview_panel.dart';

enum _AmbianceSlotLayout {
  /// Icône seule (écran étroit) : changer / arrêter passent par un menu.
  icon,

  /// Pastille bordée dans le bandeau réduit : nom et arrêt. Pas de volume
  /// en mode réduit — il se règle dans le tiroir ouvert.
  pill,

  /// Ligne pleine largeur dans le tiroir ouvert, avec le volume de voie.
  row,
}

/// Voie ambiance de la régie. L'ambiance n'a besoin que de son nom, de son
/// volume et d'un arrêt (pas de file, pas de pause) : elle tient dans une
/// pastille glissée dans une rangée existante, sans ajouter de hauteur.
class _AmbianceSlot extends StatelessWidget {
  final PadItem? current;
  final double volume;
  final _AmbianceSlotLayout layout;
  final VoidCallback? onChoose;
  final VoidCallback? onStop;
  final ValueChanged<double>? onVolumeChanged;

  static const _pillNameMaxWidth = 200.0;

  const _AmbianceSlot({
    required this.current,
    required this.volume,
    required this.layout,
    this.onChoose,
    this.onStop,
    this.onVolumeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = this.current;
    final onAir = current != null && current.isPlaying;

    if (layout == _AmbianceSlotLayout.row) {
      return _buildRow(scheme, onAir ? current : null);
    }
    if (!onAir) {
      return BoxedIconButton(
        icon: SoundType.ambiance.icon,
        tooltip: 'Lancer une ambiance',
        onPressed: onChoose,
      );
    }
    if (layout == _AmbianceSlotLayout.icon) {
      return _buildIconMenu(scheme, current);
    }
    return _buildPill(scheme, current);
  }

  Widget _volumeSlider({required double width}) => SizedBox(
    width: width,
    child: _CompactVolumeSlider(
      value: volume,
      onChanged: onVolumeChanged,
      isPlaying: true,
    ),
  );

  Widget _stopButton(ColorScheme scheme) => IconButton(
    tooltip: 'Arrêter l\'ambiance',
    visualDensity: VisualDensity.compact,
    iconSize: 16,
    color: scheme.onSurfaceVariant,
    onPressed: onStop,
    icon: const Icon(Icons.close),
  );

  Widget _name(ColorScheme scheme, String text, {required bool active}) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
        color: active ? scheme.onSurface : scheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildPill(ColorScheme scheme, PadItem current) {
    return Container(
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border.fromBorderSide(AppElevation.border(scheme)),
        borderRadius: AppRadius.radiusMd,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(SoundType.ambiance.icon, size: 14, color: scheme.primary),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _pillNameMaxWidth),
            child: Tooltip(
              message: 'Changer d\'ambiance',
              child: InkWell(
                borderRadius: AppRadius.radiusSm,
                onTap: onChoose,
                child: _name(scheme, current.displayName, active: true),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _stopButton(scheme),
        ],
      ),
    );
  }

  Widget _buildIconMenu(ColorScheme scheme, PadItem current) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, -8),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: SizedBox(
            width: 220,
            child: Row(
              children: [
                Icon(SoundType.ambiance.icon, size: 14, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: _name(scheme, current.displayName, active: true),
                ),
              ],
            ),
          ),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.swap_horiz_rounded, size: 18),
          onPressed: onChoose,
          child: const Text('Changer d\'ambiance'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.close, size: 18),
          onPressed: onStop,
          child: const Text('Arrêter'),
        ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: current.displayName,
        child: InkWell(
          borderRadius: AppRadius.radiusSm,
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              border: Border.fromBorderSide(AppElevation.border(scheme)),
              borderRadius: AppRadius.radiusSm,
            ),
            child: Icon(
              SoundType.ambiance.icon,
              size: 16,
              color: scheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(ColorScheme scheme, PadItem? onAir) {
    return Row(
      children: [
        Icon(
          SoundType.ambiance.icon,
          size: 16,
          color: onAir != null ? scheme.primary : scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _name(
            scheme,
            onAir?.displayName ?? 'Aucune ambiance',
            active: onAir != null,
          ),
        ),
        if (onAir != null) _volumeSlider(width: 96),
        BoxedIconButton(
          icon: onAir != null
              ? Icons.swap_horiz_rounded
              : SoundType.ambiance.icon,
          tooltip: onAir != null ? 'Changer d\'ambiance' : 'Lancer une ambiance',
          onPressed: onChoose,
        ),
        if (onAir != null) _stopButton(scheme),
      ],
    );
  }
}

/// Chevron très fin (hauteur minimale) : ouvre/ferme la régie explicitement,
/// sans dépendre d'un clic à l'extérieur — la régie reste ouverte quoi qu'il
/// se passe ailleurs sur l'écran (zone pads incluse). Toujours inséré en bout
/// d'une rangée de contrôles déjà plus haute que lui (jamais en overlay au-
/// dessus) : il n'ajoute donc aucune hauteur au tiroir, réduit ou ouvert.
