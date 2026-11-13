import 'package:flutter/material.dart';

import '../../domain/entities/sound.dart';
import '../utils/sound_type_ui.dart';

/// Sélecteur du type de son : l'avatar du type courant, qui se déplie au toucher
/// en trois cercles (bruitage, ambiance, musique) et se replie sur le choix.
///
/// Les cercles gardent leur ordre fixe : celui du type courant reste en place,
/// les autres glissent hors de lui en cascade. [type] null = son non classé
/// (cercle neutre, remplacé par les trois types au dépliage).
class SoundTypeSelector extends StatefulWidget {
  final SoundType? type;
  final int? colorValue;
  final ValueChanged<SoundType> onChanged;

  const SoundTypeSelector({
    super.key,
    required this.type,
    required this.onChanged,
    this.colorValue,
  });

  @override
  State<SoundTypeSelector> createState() => _SoundTypeSelectorState();
}

class _SoundTypeSelectorState extends State<SoundTypeSelector>
    with SingleTickerProviderStateMixin {
  static const _types = <SoundType>[
    SoundType.soundEffect,
    SoundType.ambiance,
    SoundType.music,
  ];
  static const double _radius = 24;
  static const double _gap = 8;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    reverseDuration: const Duration(milliseconds: 220),
  );

  bool get _expanded => _controller.status.isForwardOrCompleted;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_expanded) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  void _select(SoundType type) {
    if (type != widget.type) widget.onChanged(type);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TapRegion(
      onTapOutside: (_) {
        if (_expanded) _controller.reverse();
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final open = _controller.value;
          // Rang parmi les cercles qui apparaissent : décale chaque départ.
          var rank = 0;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.type == null)
                _Slot(
                  presence: 1 - Curves.easeOut.transform(open),
                  child: _circle(
                    scheme: scheme,
                    type: null,
                    tooltip: 'Type de son non défini',
                    onTap: _toggle,
                  ),
                ),
              for (final type in _types)
                _Slot(
                  presence: type == widget.type ? 1 : _staggered(open, rank++),
                  child: _circle(
                    scheme: scheme,
                    type: type,
                    tooltip: type.label,
                    selectedRing: type == widget.type ? open : 0,
                    onTap: type == widget.type ? _toggle : () => _select(type),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Progression du [rank]-ième cercle qui apparaît : chacun démarre un peu
  /// après le précédent.
  static double _staggered(double open, int rank) {
    final start = 0.12 * rank;
    return Interval(
      start,
      start + 0.7,
      curve: Curves.easeOutCubic,
    ).transform(open);
  }

  Widget _circle({
    required ColorScheme scheme,
    required SoundType? type,
    required String tooltip,
    required VoidCallback onTap,
    double selectedRing = 0,
  }) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: _radius * 2,
            height: _radius * 2,
            foregroundDecoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: scheme.primary.withValues(alpha: selectedRing),
                width: 2,
              ),
            ),
            child: SoundTypeAvatar(
              type: type,
              colorValue: widget.colorValue,
              radius: _radius,
              iconSize: _radius,
            ),
          ),
        ),
      ),
    );
  }
}

/// Un cercle et son espacement, qui apparaît (largeur, échelle, opacité) selon
/// [presence] : 0 = absent (largeur nulle), 1 = pleinement déplié.
class _Slot extends StatelessWidget {
  final double presence;
  final Widget child;

  const _Slot({required this.presence, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = presence.clamp(0.0, 1.0);
    if (t == 0) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: t,
      child: Opacity(
        opacity: t,
        child: Transform.scale(
          scale: 0.4 + 0.6 * t,
          child: Padding(
            padding: const EdgeInsets.only(right: _SoundTypeSelectorState._gap),
            child: child,
          ),
        ),
      ),
    );
  }
}
