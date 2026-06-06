import 'package:flutter/material.dart';
import '../../domain/entities/sound.dart';
import '../providers/sampler_provider.dart';
import '../utils/sound_type_ui.dart';

/// Panneau régie musique — deux modes : réduit et avancé.
class MusicPreviewPanel extends StatefulWidget {
  final SamplerState state;
  final double musicVolume;

  /// Résout un pad musique par id — sur la scène ou hors-scène (régie seule).
  final PadItem? Function(int padId) resolveMusicPad;
  final VoidCallback onChooseMusic;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback? onRestart;
  final VoidCallback? onSkipNext;
  final VoidCallback? onStopCurrent;
  final VoidCallback? onClearQueue;
  final VoidCallback? onPlayNextInQueue;
  final ValueChanged<int>? onRemoveFromQueue;
  final ValueChanged<double>? onMusicVolumeChanged;
  final ValueChanged<Duration>? onFadeOut;
  final ValueChanged<Duration>? onTransitionToNext;
  final bool isAdvanced;
  final ValueChanged<bool> onAdvancedChanged;

  const MusicPreviewPanel({
    super.key,
    required this.state,
    required this.musicVolume,
    required this.resolveMusicPad,
    required this.isAdvanced,
    required this.onAdvancedChanged,
    required this.onChooseMusic,
    this.onTogglePlayPause,
    this.onRestart,
    this.onSkipNext,
    this.onStopCurrent,
    this.onClearQueue,
    this.onPlayNextInQueue,
    this.onRemoveFromQueue,
    this.onMusicVolumeChanged,
    this.onFadeOut,
    this.onTransitionToNext,
  });

  @override
  State<MusicPreviewPanel> createState() => _MusicPreviewPanelState();
}

class _MusicPreviewPanelState extends State<MusicPreviewPanel> {
  /// Durée de fondu/enchaînement choisie pour la régie — partagée entre
  /// le fondu (passage en pause) et l'enchaînement (passage à la suivante).
  Duration _transitionDuration = const Duration(seconds: 3);

  void _setTransitionDuration(Duration duration) {
    setState(() => _transitionDuration = duration);
  }

  void _toggleMode() {
    widget.onAdvancedChanged(!widget.isAdvanced);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: _MusicRegieDrawer(
          state: widget.state,
          musicVolume: widget.musicVolume,
          resolveMusicPad: widget.resolveMusicPad,
          isAdvanced: widget.isAdvanced,
          onModeToggle: _toggleMode,
          onChooseMusic: widget.onChooseMusic,
          onTogglePlayPause: widget.onTogglePlayPause,
          onRestart: widget.onRestart,
          onSkipNext: widget.onSkipNext,
          onStopCurrent: widget.onStopCurrent,
          onClearQueue: widget.onClearQueue,
          onPlayNextInQueue: widget.onPlayNextInQueue,
          onRemoveFromQueue: widget.onRemoveFromQueue,
          onMusicVolumeChanged: widget.onMusicVolumeChanged,
          transitionDuration: _transitionDuration,
          onTransitionDurationChanged: _setTransitionDuration,
          onFadeOut: widget.onFadeOut,
          onTransitionToNext: widget.onTransitionToNext,
        ),
      ),
    );
  }
}

class _MusicRegieDrawer extends StatelessWidget {
  final SamplerState state;
  final double musicVolume;
  final PadItem? Function(int padId) resolveMusicPad;
  final bool isAdvanced;
  final VoidCallback onModeToggle;
  final VoidCallback onChooseMusic;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback? onRestart;
  final VoidCallback? onSkipNext;
  final VoidCallback? onStopCurrent;
  final VoidCallback? onClearQueue;
  final VoidCallback? onPlayNextInQueue;
  final ValueChanged<int>? onRemoveFromQueue;
  final ValueChanged<double>? onMusicVolumeChanged;
  final Duration transitionDuration;
  final ValueChanged<Duration> onTransitionDurationChanged;
  final ValueChanged<Duration>? onFadeOut;
  final ValueChanged<Duration>? onTransitionToNext;

  const _MusicRegieDrawer({
    required this.state,
    required this.musicVolume,
    required this.resolveMusicPad,
    required this.isAdvanced,
    required this.onModeToggle,
    required this.onChooseMusic,
    this.onTogglePlayPause,
    this.onRestart,
    this.onSkipNext,
    this.onStopCurrent,
    this.onClearQueue,
    this.onPlayNextInQueue,
    this.onRemoveFromQueue,
    this.onMusicVolumeChanged,
    required this.transitionDuration,
    required this.onTransitionDurationChanged,
    this.onFadeOut,
    this.onTransitionToNext,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = state.currentMusicPad;
    final isPlaying = current?.isPlaying ?? false;
    final queue = state.musicQueue(resolveMusicPad);
    final next = queue.isNotEmpty ? queue.first : null;

    void handlePauseToggle() {
      if (isPlaying && current != null) {
        onFadeOut?.call(transitionDuration);
      } else {
        onTogglePlayPause?.call();
      }
    }

    void handleSkipNext() {
      if (isPlaying && queue.isNotEmpty) {
        onTransitionToNext?.call(transitionDuration);
      } else {
        onSkipNext?.call();
      }
    }

    return Material(
      color: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.none,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isAdvanced && isPlaying && current != null)
              _RegieProgressBar(
                padItem: current,
                isPlaying: true,
                height: 3,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        SoundType.music.icon,
                        size: 18,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'RÉGIE MUSIQUE',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                      ),
                      if (isPlaying) ...[
                        const SizedBox(width: 8),
                        const _LiveBadge(compact: true),
                      ],
                      const Spacer(),
                      _DrawerExpandButton(
                        scheme: scheme,
                        isExpanded: isAdvanced,
                        onTap: onModeToggle,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (!isAdvanced)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _CueSlot(
                            label: 'À l\'antenne',
                            padItem: current,
                            isActive: isPlaying,
                            emptyLabel: '—',
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          color: scheme.outlineVariant.withValues(alpha: 0.45),
                        ),
                        Expanded(
                          child: _CueSlot(
                            label: 'Prévu ensuite',
                            padItem: next,
                            isActive: next != null,
                            emptyLabel: '—',
                            accentColor: scheme.secondary,
                            suffix: queue.length > 1
                                ? '+${queue.length - 1}'
                                : null,
                            onTap: onChooseMusic,
                          ),
                        ),
                      ],
                    )
                  else ...[
                    _OnAirCard(
                      padItem: current,
                      isPlaying: isPlaying,
                      onStop: onStopCurrent,
                      onRestart: onRestart,
                    ),
                    const SizedBox(height: 12),
                    _PassageQueueSection(
                      queue: queue,
                      onPlayNext:
                          queue.isNotEmpty ? onPlayNextInQueue : null,
                      onClear: queue.isNotEmpty ? onClearQueue : null,
                      onRemove: onRemoveFromQueue,
                      onChooseMusic: onChooseMusic,
                    ),
                  ],
                  const SizedBox(height: 8),
                  _RegieToolbarRow(
                    volume: musicVolume,
                    onVolumeChanged: onMusicVolumeChanged,
                    isPlaying: isPlaying,
                    hasCurrent: current != null,
                    hasQueue: queue.isNotEmpty,
                    showTransition: isPlaying || queue.isNotEmpty,
                    transitionDuration: transitionDuration,
                    onTransitionDurationChanged: onTransitionDurationChanged,
                    onChooseMusic: onChooseMusic,
                    onTogglePlayPause: handlePauseToggle,
                    onSkipNext: handleSkipNext,
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }
}

class _DrawerExpandButton extends StatelessWidget {
  final ColorScheme scheme;
  final bool isExpanded;
  final VoidCallback? onTap;

  const _DrawerExpandButton({
    required this.scheme,
    required this.isExpanded,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: isExpanded ? 'Mode réduit' : 'Mode avancé',
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      icon: Icon(
        isExpanded
            ? Icons.keyboard_arrow_down_rounded
            : Icons.keyboard_arrow_up_rounded,
        size: 22,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
      ),
    );
  }
}

/// Barre compacte : volume, contrôles et durée de transition sur une seule ligne.
class _RegieToolbarRow extends StatelessWidget {
  final double volume;
  final ValueChanged<double>? onVolumeChanged;
  final bool isPlaying;
  final bool hasCurrent;
  final bool hasQueue;
  final bool showTransition;
  final Duration transitionDuration;
  final ValueChanged<Duration> onTransitionDurationChanged;
  final VoidCallback onChooseMusic;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback? onSkipNext;

  const _RegieToolbarRow({
    required this.volume,
    this.onVolumeChanged,
    required this.isPlaying,
    required this.hasCurrent,
    required this.hasQueue,
    required this.showTransition,
    required this.transitionDuration,
    required this.onTransitionDurationChanged,
    required this.onChooseMusic,
    this.onTogglePlayPause,
    this.onSkipNext,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canControl = hasCurrent || hasQueue;

    return Row(
      children: [
        Icon(
          Icons.volume_up_rounded,
          size: 16,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _CompactVolumeSlider(
            value: volume,
            onChanged: onVolumeChanged,
          ),
        ),
        const SizedBox(width: 8),
        _RegieControlButtons(
          isPlaying: isPlaying,
          canControl: canControl,
          onChooseMusic: onChooseMusic,
          onTogglePlayPause: onTogglePlayPause,
          onSkipNext: onSkipNext,
        ),
        if (showTransition) ...[
          const SizedBox(width: 8),
          _CompactTransitionPicker(
            selected: transitionDuration,
            onChanged: onTransitionDurationChanged,
          ),
        ],
      ],
    );
  }
}

/// Slider volume avec bulle au-dessus du curseur (compatible tactile).
class _CompactVolumeSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double>? onChanged;

  const _CompactVolumeSlider({
    required this.value,
    this.onChanged,
  });

  @override
  State<_CompactVolumeSlider> createState() => _CompactVolumeSliderState();
}

class _CompactVolumeSliderState extends State<_CompactVolumeSlider> {
  bool _isActive = false;
  double? _localValue;

  double get _displayValue => _localValue ?? widget.value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = _displayValue.clamp(0.0, 1.0);

    return SizedBox(
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (_isActive)
            Positioned(
              left: 0,
              right: 0,
              bottom: 30,
              child: Align(
                alignment: Alignment((fraction * 2) - 1, 0),
                child: _VolumeDragBubble(
                  label: '${(fraction * 100).round()}%',
                  scheme: scheme,
                ),
              ),
            ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 8,
                disabledThumbRadius: 8,
              ),
              overlayShape: SliderComponentShape.noOverlay,
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: widget.value,
              min: 0.0,
              max: 1.0,
              onChangeStart: widget.onChanged == null
                  ? null
                  : (_) => setState(() => _isActive = true),
              onChanged: widget.onChanged == null
                  ? null
                  : (value) {
                      setState(() => _localValue = value);
                      widget.onChanged!(value);
                    },
              onChangeEnd: widget.onChanged == null
                  ? null
                  : (_) => setState(() {
                      _isActive = false;
                      _localValue = null;
                    }),
            ),
          ),
        ],
      ),
    );
  }
}

class _VolumeDragBubble extends StatelessWidget {
  final String label;
  final ColorScheme scheme;

  const _VolumeDragBubble({
    required this.label,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      color: scheme.inverseSurface,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onInverseSurface,
            fontWeight: FontWeight.w700,
            fontSize: 10,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

/// Sélecteur minimal de durée (0 / 1 / 3 / 5 s).
class _CompactTransitionPicker extends StatelessWidget {
  final Duration selected;
  final ValueChanged<Duration> onChanged;

  static const _options = <Duration>[
    Duration.zero,
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 5),
  ];

  const _CompactTransitionPicker({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      height: 1,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _options.length; i++) ...[
              if (i > 0)
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              _TransitionCell(
                label: '${_options[i].inSeconds}',
                isSelected: selected == _options[i],
                onTap: () => onChanged(_options[i]),
                labelStyle: labelStyle,
                scheme: scheme,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TransitionCell extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final TextStyle? labelStyle;
  final ColorScheme scheme;

  const _TransitionCell({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.labelStyle,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? scheme.primaryContainer.withValues(alpha: 0.55)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Text(
            label,
            style: labelStyle?.copyWith(
              color: isSelected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _RegieControlButtons extends StatelessWidget {
  final bool isPlaying;
  final bool canControl;
  final VoidCallback onChooseMusic;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback? onSkipNext;

  const _RegieControlButtons({
    required this.isPlaying,
    required this.canControl,
    required this.onChooseMusic,
    this.onTogglePlayPause,
    this.onSkipNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: _playTooltip(),
          onPressed: canControl ? onTogglePlayPause : onChooseMusic,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Icon(
            canControl
                ? (isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded)
                : Icons.play_arrow_rounded,
            size: 22,
          ),
        ),
        IconButton(
          tooltip: 'Suivant',
          onPressed: canControl ? onSkipNext : null,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: const Icon(Icons.skip_next_rounded, size: 22),
        ),
      ],
    );
  }

  String _playTooltip() {
    if (!canControl) return 'Lancer';
    return isPlaying ? 'Pause' : 'Reprendre';
  }
}

class _LiveBadge extends StatelessWidget {
  final bool compact;

  const _LiveBadge({this.compact = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: scheme.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: compact ? 7 : 8, color: scheme.error),
          SizedBox(width: compact ? 4 : 5),
          Text(
            'ON AIR',
            style: TextStyle(
              color: scheme.error,
              fontSize: compact ? 9 : 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _CueSlot extends StatelessWidget {
  final String label;
  final PadItem? padItem;
  final bool isActive;
  final String emptyLabel;
  final Color? accentColor;
  final String? suffix;
  final VoidCallback? onTap;

  const _CueSlot({
    required this.label,
    required this.padItem,
    required this.isActive,
    required this.emptyLabel,
    this.accentColor,
    this.suffix,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accentColor ?? scheme.primary;
    final title = padItem?.pad.displayName ?? emptyLabel;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (padItem != null)
              _PadColorChip(padItem: padItem!, size: 14)
            else if (onTap != null)
              Icon(Icons.add_rounded, size: 14, color: color)
            else
              Icon(Icons.remove_rounded, size: 14, color: scheme.outline),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (suffix != null)
              Text(
                suffix!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ],
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: content,
        ),
      ),
    );
  }
}

class _OnAirCard extends StatelessWidget {
  final PadItem? padItem;
  final bool isPlaying;
  final VoidCallback? onStop;
  final VoidCallback? onRestart;

  const _OnAirCard({
    required this.padItem,
    required this.isPlaying,
    this.onStop,
    this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isPlaying
              ? scheme.primary.withValues(alpha: 0.45)
              : scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'À l\'antenne',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (isPlaying) const _LiveBadge(),
              ],
            ),
            const SizedBox(height: 12),
            if (padItem == null)
              Text(
                'Aucune musique lancée',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PadColorChip(padItem: padItem!, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          padItem!.pad.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (padItem!.pad.sounds.length > 1)
                          Text(
                            '${padItem!.pad.sounds.length} variantes',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (isPlaying) ...[
                const SizedBox(height: 14),
                _RegieProgressBar(
                  padItem: padItem!,
                  isPlaying: true,
                  showTimes: true,
                ),
              ],
              if (onStop != null || onRestart != null) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    if (isPlaying && onStop != null)
                      OutlinedButton.icon(
                        onPressed: onStop,
                        icon: const Icon(Icons.stop_rounded, size: 18),
                        label: const Text('Couper'),
                      ),
                    if (padItem != null && onRestart != null)
                      TextButton.icon(
                        onPressed: onRestart,
                        icon: const Icon(Icons.replay_rounded, size: 18),
                        label: const Text('Rejouer'),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _RegieProgressBar extends StatelessWidget {
  final PadItem? padItem;
  final bool isPlaying;
  final bool showTimes;
  final double height;

  const _RegieProgressBar({
    required this.padItem,
    this.isPlaying = false,
    this.showTimes = false,
    this.height = 4,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = padItem?.currentPlayer?.duration ?? Duration.zero;
    final playing = isPlaying && (padItem?.isPlaying ?? false);

    return Column(
      children: [
        TweenAnimationBuilder<double>(
          key: ValueKey(
            'regie_progress_${padItem?.pad.id}_${padItem?.currentSoundIndex}',
          ),
          tween: Tween(begin: 0.0, end: playing ? 1.0 : 0.0),
          duration: playing
              ? (duration.inMilliseconds > 0
                    ? duration
                    : const Duration(seconds: 1))
              : const Duration(milliseconds: 200),
          curve: Curves.linear,
          builder: (context, value, _) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(height),
              child: LinearProgressIndicator(
                value: playing ? value : 0,
                minHeight: height,
                backgroundColor: scheme.outlineVariant.withValues(alpha: 0.35),
                valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
              ),
            );
          },
        ),
        if (showTimes) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '0:00',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                _formatDuration(duration),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _PassageQueueSection extends StatelessWidget {
  final List<PadItem> queue;
  final VoidCallback? onPlayNext;
  final VoidCallback? onClear;
  final ValueChanged<int>? onRemove;
  final VoidCallback? onChooseMusic;

  const _PassageQueueSection({
    required this.queue,
    this.onPlayNext,
    this.onClear,
    this.onRemove,
    this.onChooseMusic,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'File de passage',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (onPlayNext != null)
                  TextButton.icon(
                    onPressed: onPlayNext,
                    icon: const Icon(Icons.skip_next_rounded, size: 18),
                    label: const Text('Enchaîner'),
                  ),
                if (onClear != null)
                  TextButton(
                    onPressed: onClear,
                    child: const Text('Vider'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (queue.isEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Préparez la musique suivante sans interrompre celle en cours.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (onChooseMusic != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: onChooseMusic,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Choisir une musique'),
                    ),
                  ],
                ],
              )
            else
              ...queue.asMap().entries.map(
                (entry) => _QueueRow(
                  index: entry.key + 1,
                  padItem: entry.value,
                  onRemove: onRemove == null
                      ? null
                      : () => onRemove!(entry.value.pad.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final int index;
  final PadItem padItem;
  final VoidCallback? onRemove;

  const _QueueRow({
    required this.index,
    required this.padItem,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$index.',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.secondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _PadColorChip(padItem: padItem, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              padItem.pad.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Retirer',
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 18),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
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
    final custom = padItem.pad.colorValue;
    final color = custom != null
        ? Color(custom)
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

/// Couleur de pastille pour les sons sans pad (sélecteur).
Color musicChipColor(int seed, ColorScheme scheme) {
  if (seed == 0) return scheme.primaryContainer;
  final hue = (seed * 47) % 360;
  return HSLColor.fromAHSL(1, hue.toDouble(), 0.45, 0.38).toColor();
}
