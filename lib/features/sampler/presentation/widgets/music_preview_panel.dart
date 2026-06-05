import 'package:flutter/material.dart';
import '../providers/sampler_provider.dart';

/// Panneau régie musique — bandeau compact + console étendue.
class MusicPreviewPanel extends StatelessWidget {
  final SamplerState state;
  final bool isLandscapeExpanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onChooseMusic;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback? onRestart;
  final VoidCallback? onSkipNext;
  final VoidCallback? onStopCurrent;
  final VoidCallback? onClearQueue;
  final VoidCallback? onPlayNextInQueue;
  final ValueChanged<int>? onRemoveFromQueue;
  final ValueChanged<PadItem>? onSelectMusicPad;
  final VoidCallback? onFadeOutShort;
  final VoidCallback? onFadeOutLong;
  final VoidCallback? onCrossfadeShort;
  final VoidCallback? onCrossfadeLong;

  const MusicPreviewPanel({
    super.key,
    required this.state,
    required this.isLandscapeExpanded,
    required this.onToggleExpanded,
    required this.onChooseMusic,
    this.onTogglePlayPause,
    this.onRestart,
    this.onSkipNext,
    this.onStopCurrent,
    this.onClearQueue,
    this.onPlayNextInQueue,
    this.onRemoveFromQueue,
    this.onSelectMusicPad,
    this.onFadeOutShort,
    this.onFadeOutLong,
    this.onCrossfadeShort,
    this.onCrossfadeLong,
  });

  PadItem? _resolve(int padId) {
    for (final padItem in state.pads) {
      if (padItem.pad.id == padId) return padItem;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (state.isMusicPanelExpanded) {
      return _RegieMusicConsole(
        state: state,
        resolvePad: _resolve,
        isLandscapeExpanded: isLandscapeExpanded,
        onCollapse: onToggleExpanded,
        onChooseMusic: onChooseMusic,
        onTogglePlayPause: onTogglePlayPause,
        onRestart: onRestart,
        onSkipNext: onSkipNext,
        onStopCurrent: onStopCurrent,
        onClearQueue: onClearQueue,
        onPlayNextInQueue: onPlayNextInQueue,
        onRemoveFromQueue: onRemoveFromQueue,
        onSelectMusicPad: onSelectMusicPad,
        onFadeOutShort: onFadeOutShort,
        onFadeOutLong: onFadeOutLong,
        onCrossfadeShort: onCrossfadeShort,
        onCrossfadeLong: onCrossfadeLong,
      );
    }

    return _RegieMusicStrip(
      state: state,
      resolvePad: _resolve,
      onExpand: onToggleExpanded,
      onChooseMusic: onChooseMusic,
      onTogglePlayPause: onTogglePlayPause,
      onStopCurrent: onStopCurrent,
      onSkipNext: onSkipNext,
      onFadeOutShort: onFadeOutShort,
      onFadeOutLong: onFadeOutLong,
      onCrossfadeShort: onCrossfadeShort,
      onCrossfadeLong: onCrossfadeLong,
    );
  }
}

class _RegieMusicStrip extends StatelessWidget {
  final SamplerState state;
  final PadItem? Function(int padId) resolvePad;
  final VoidCallback onExpand;
  final VoidCallback onChooseMusic;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback? onStopCurrent;
  final VoidCallback? onSkipNext;
  final VoidCallback? onFadeOutShort;
  final VoidCallback? onFadeOutLong;
  final VoidCallback? onCrossfadeShort;
  final VoidCallback? onCrossfadeLong;

  const _RegieMusicStrip({
    required this.state,
    required this.resolvePad,
    required this.onExpand,
    required this.onChooseMusic,
    this.onTogglePlayPause,
    this.onStopCurrent,
    this.onSkipNext,
    this.onFadeOutShort,
    this.onFadeOutLong,
    this.onCrossfadeShort,
    this.onCrossfadeLong,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = state.currentMusicPad;
    final isPlaying = current?.isPlaying ?? false;
    final queue = state.musicQueue(resolvePad);
    final next = queue.isNotEmpty ? queue.first : null;

    return Material(
      color: scheme.surfaceContainerLow,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isPlaying && current != null)
                _RegieProgressBar(
                  padItem: current,
                  isPlaying: true,
                  height: 3,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.piano_rounded, size: 18, color: scheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'RÉGIE MUSIQUE',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
                        IconButton(
                          tooltip: 'Console musique',
                          onPressed: onExpand,
                          icon: Icon(Icons.open_in_full_rounded, color: scheme.onSurfaceVariant),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
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
                            suffix: queue.length > 1 ? '+${queue.length - 1}' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _RegieControlBar(
                      compact: true,
                      isPlaying: isPlaying,
                      hasCurrent: current != null,
                      hasQueue: queue.isNotEmpty,
                      onChooseMusic: onChooseMusic,
                      onStop: onStopCurrent,
                      onTogglePlayPause: onTogglePlayPause,
                      onSkipNext: onSkipNext,
                    ),
                    if (isPlaying || queue.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _MusicTransitionBar(
                        compact: true,
                        canFadeOut: isPlaying,
                        canCrossfade: isPlaying && queue.isNotEmpty,
                        onFadeOutShort: onFadeOutShort,
                        onFadeOutLong: onFadeOutLong,
                        onCrossfadeShort: onCrossfadeShort,
                        onCrossfadeLong: onCrossfadeLong,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegieMusicConsole extends StatelessWidget {
  final SamplerState state;
  final PadItem? Function(int padId) resolvePad;
  final bool isLandscapeExpanded;
  final VoidCallback onCollapse;
  final VoidCallback onChooseMusic;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback? onRestart;
  final VoidCallback? onSkipNext;
  final VoidCallback? onStopCurrent;
  final VoidCallback? onClearQueue;
  final VoidCallback? onPlayNextInQueue;
  final ValueChanged<int>? onRemoveFromQueue;
  final ValueChanged<PadItem>? onSelectMusicPad;
  final VoidCallback? onFadeOutShort;
  final VoidCallback? onFadeOutLong;
  final VoidCallback? onCrossfadeShort;
  final VoidCallback? onCrossfadeLong;

  const _RegieMusicConsole({
    required this.state,
    required this.resolvePad,
    required this.isLandscapeExpanded,
    required this.onCollapse,
    required this.onChooseMusic,
    this.onTogglePlayPause,
    this.onRestart,
    this.onSkipNext,
    this.onStopCurrent,
    this.onClearQueue,
    this.onPlayNextInQueue,
    this.onRemoveFromQueue,
    this.onSelectMusicPad,
    this.onFadeOutShort,
    this.onFadeOutLong,
    this.onCrossfadeShort,
    this.onCrossfadeLong,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = state.currentMusicPad;
    final queue = state.musicQueue(resolvePad);
    final upcoming = state.upcomingMusicPads(resolvePad);
    final isPlaying = current?.isPlaying ?? false;

    return Material(
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        left: !isLandscapeExpanded,
        right: true,
        bottom: !isLandscapeExpanded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Réduire',
                    onPressed: onCollapse,
                    icon: Icon(
                      isLandscapeExpanded
                          ? Icons.close_rounded
                          : Icons.expand_more_rounded,
                    ),
                  ),
                  Icon(Icons.piano_rounded, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Console musique',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (isPlaying) const _LiveBadge(),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  isLandscapeExpanded ? 12 : 16,
                  8,
                  isLandscapeExpanded ? 12 : 16,
                  16,
                ),
                children: [
                  _OnAirCard(
                    padItem: current,
                    isPlaying: isPlaying,
                    onStop: onStopCurrent,
                    onRestart: onRestart,
                  ),
                  const SizedBox(height: 12),
                  _RegieControlBar(
                    isPlaying: isPlaying,
                    hasCurrent: current != null,
                    hasQueue: queue.isNotEmpty,
                    onChooseMusic: onChooseMusic,
                    onStop: onStopCurrent,
                    onTogglePlayPause: onTogglePlayPause,
                    onSkipNext: onSkipNext,
                  ),
                  if (isPlaying || queue.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _MusicTransitionBar(
                      canFadeOut: isPlaying,
                      canCrossfade: isPlaying && queue.isNotEmpty,
                      onFadeOutShort: onFadeOutShort,
                      onFadeOutLong: onFadeOutLong,
                      onCrossfadeShort: onCrossfadeShort,
                      onCrossfadeLong: onCrossfadeLong,
                    ),
                  ],
                  const SizedBox(height: 16),
                  _PassageQueueSection(
                    queue: queue,
                    onPlayNext: queue.isNotEmpty ? onPlayNextInQueue : null,
                    onClear: queue.isNotEmpty ? onClearQueue : null,
                    onRemove: onRemoveFromQueue,
                  ),
                  if (upcoming.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Pads musique sur la scène',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...upcoming.map(
                      (padItem) => _ScenePadTile(
                        padItem: padItem,
                        onTap: onSelectMusicPad == null
                            ? null
                            : () => onSelectMusicPad!(padItem),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

  const _CueSlot({
    required this.label,
    required this.padItem,
    required this.isActive,
    required this.emptyLabel,
    this.accentColor,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accentColor ?? scheme.primary;
    final title = padItem?.pad.displayName ?? emptyLabel;

    return Column(
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

class _RegieControlBar extends StatelessWidget {
  final bool compact;
  final bool isPlaying;
  final bool hasCurrent;
  final bool hasQueue;
  final VoidCallback onChooseMusic;
  final VoidCallback? onStop;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback? onSkipNext;

  const _RegieControlBar({
    this.compact = false,
    required this.isPlaying,
    required this.hasCurrent,
    required this.hasQueue,
    required this.onChooseMusic,
    this.onStop,
    this.onTogglePlayPause,
    this.onSkipNext,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onChooseMusic,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Ajouter'),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: 'Couper',
            onPressed: hasCurrent && isPlaying ? onStop : null,
            icon: const Icon(Icons.stop_rounded),
          ),
          const SizedBox(width: 4),
          IconButton.filled(
            tooltip: hasCurrent
                ? (isPlaying ? 'Pause' : 'Reprendre')
                : 'Lancer',
            onPressed: hasCurrent || hasQueue ? onTogglePlayPause : onChooseMusic,
            icon: Icon(
              hasCurrent
                  ? (isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded)
                  : Icons.play_arrow_rounded,
            ),
          ),
          const SizedBox(width: 4),
          IconButton.filledTonal(
            tooltip: 'Suivant',
            onPressed: (hasCurrent || hasQueue) ? onSkipNext : null,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        FilledButton.tonalIcon(
          onPressed: onChooseMusic,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Ajouter'),
        ),
        if (hasCurrent && isPlaying)
          OutlinedButton.icon(
            onPressed: onStop,
            icon: const Icon(Icons.stop_rounded),
            label: const Text('Couper'),
          ),
        FilledButton.icon(
          onPressed: hasCurrent || hasQueue ? onTogglePlayPause : onChooseMusic,
          icon: Icon(
            hasCurrent
                ? (isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded)
                : Icons.play_arrow_rounded,
          ),
          label: Text(
            hasCurrent
                ? (isPlaying ? 'Pause' : 'Reprendre')
                : 'Lancer',
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: (hasCurrent || hasQueue) ? onSkipNext : null,
          icon: const Icon(Icons.skip_next_rounded),
          label: const Text('Suivant'),
        ),
      ],
    );
  }
}

class _MusicTransitionBar extends StatelessWidget {
  final bool compact;
  final bool canFadeOut;
  final bool canCrossfade;
  final VoidCallback? onFadeOutShort;
  final VoidCallback? onFadeOutLong;
  final VoidCallback? onCrossfadeShort;
  final VoidCallback? onCrossfadeLong;

  const _MusicTransitionBar({
    this.compact = false,
    required this.canFadeOut,
    required this.canCrossfade,
    this.onFadeOutShort,
    this.onFadeOutLong,
    this.onCrossfadeShort,
    this.onCrossfadeLong,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (compact) {
      return Row(
        children: [
          _TransitionIconButton(
            tooltip: 'Fade out court (2 s)',
            icon: Icons.volume_down_rounded,
            enabled: canFadeOut,
            onPressed: onFadeOutShort,
          ),
          _TransitionIconButton(
            tooltip: 'Fade out long (8 s)',
            icon: Icons.volume_mute_rounded,
            enabled: canFadeOut,
            onPressed: onFadeOutLong,
          ),
          const SizedBox(width: 4),
          _TransitionIconButton(
            tooltip: 'Enchaînement court (3 s)',
            icon: Icons.swap_horiz_rounded,
            enabled: canCrossfade,
            onPressed: onCrossfadeShort,
          ),
          _TransitionIconButton(
            tooltip: 'Enchaînement long (10 s)',
            icon: Icons.sync_alt_rounded,
            enabled: canCrossfade,
            onPressed: onCrossfadeLong,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Transitions',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _TransitionButton(
              label: 'Fade court',
              subtitle: '2 s',
              icon: Icons.volume_down_rounded,
              enabled: canFadeOut,
              onPressed: onFadeOutShort,
            ),
            _TransitionButton(
              label: 'Fade long',
              subtitle: '8 s',
              icon: Icons.volume_mute_rounded,
              enabled: canFadeOut,
              onPressed: onFadeOutLong,
            ),
            _TransitionButton(
              label: 'Enchaînement court',
              subtitle: '3 s',
              icon: Icons.swap_horiz_rounded,
              enabled: canCrossfade,
              onPressed: onCrossfadeShort,
            ),
            _TransitionButton(
              label: 'Enchaînement long',
              subtitle: '10 s',
              icon: Icons.sync_alt_rounded,
              enabled: canCrossfade,
              onPressed: onCrossfadeLong,
            ),
          ],
        ),
      ],
    );
  }
}

class _TransitionButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onPressed;

  const _TransitionButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.enabled,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransitionIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onPressed;

  const _TransitionIconButton({
    required this.tooltip,
    required this.icon,
    required this.enabled,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 20),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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

  const _PassageQueueSection({
    required this.queue,
    this.onPlayNext,
    this.onClear,
    this.onRemove,
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
              Text(
                'Préparez la musique suivante sans interrompre celle en cours.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
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

class _ScenePadTile extends StatelessWidget {
  final PadItem padItem;
  final VoidCallback? onTap;

  const _ScenePadTile({
    required this.padItem,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _PadColorChip(padItem: padItem, size: 36),
                const SizedBox(width: 12),
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
                Icon(Icons.touch_app_rounded, size: 18, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
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
              Icons.music_note_rounded,
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
