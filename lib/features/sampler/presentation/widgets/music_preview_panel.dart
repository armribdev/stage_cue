import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../../../core/utils/sound_color_utils.dart';
import '../../domain/entities/sound.dart';
import '../providers/sampler_provider.dart';
import '../utils/sound_type_ui.dart';

enum _MusicTransitionKind { fadeOut, crossfade }

const _queueDragBorderRadius = 8.0;
const _drawerSnapDuration = Duration(milliseconds: 280);
const _drawerSnapCurve = Curves.easeOut;
const _drawerSnapVelocityThreshold = 500.0;

/// Signale la taille mesurée d'un sous-arbre après layout.
class _ReportSize extends StatefulWidget {
  final Widget child;
  final ValueChanged<Size> onChange;

  const _ReportSize({required this.child, required this.onChange});

  @override
  State<_ReportSize> createState() => _ReportSizeState();
}

class _ReportSizeState extends State<_ReportSize> {
  Size? _lastSize;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = context.size;
      if (size == null || size == _lastSize) return;
      _lastSize = size;
      widget.onChange(size);
    });
    return widget.child;
  }
}

/// Panneau régie musique — deux modes : réduit et avancé.
class MusicPreviewPanel extends StatefulWidget {
  final SamplerState state;
  final double musicVolume;

  /// Résout un pad musique par id — sur la scène ou hors-scène (régie seule).
  final PadItem? Function(int padId) resolveMusicPad;
  final VoidCallback onChooseMusic;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback? onSkipNext;
  final ValueChanged<int>? onRemoveFromQueue;
  final void Function(int oldIndex, int newIndex)? onReorderMusicQueue;
  final ValueChanged<double>? onMusicVolumeChanged;
  final ValueChanged<Duration>? onFadeOut;
  final ValueChanged<Duration>? onTransitionToNext;
  final bool isAdvanced;
  final ValueChanged<bool> onAdvancedChanged;
  final bool isDesktop;
  final bool isLocked;
  final ValueChanged<bool>? onLockedChanged;

  const MusicPreviewPanel({
    super.key,
    required this.state,
    required this.musicVolume,
    required this.resolveMusicPad,
    required this.isAdvanced,
    required this.onAdvancedChanged,
    required this.onChooseMusic,
    this.onTogglePlayPause,
    this.onSkipNext,
    this.onRemoveFromQueue,
    this.onReorderMusicQueue,
    this.onMusicVolumeChanged,
    this.onFadeOut,
    this.onTransitionToNext,
    this.isDesktop = false,
    this.isLocked = false,
    this.onLockedChanged,
  });

  @override
  State<MusicPreviewPanel> createState() => _MusicPreviewPanelState();
}

class _MusicPreviewPanelState extends State<MusicPreviewPanel>
    with TickerProviderStateMixin {
  /// Durée affichée dans le sélecteur — `null` = aucune option active (0,1 s).
  Duration? _selectedTransitionDuration = const Duration(seconds: 3);

  static const _defaultSelectedTransition = Duration(seconds: 3);
  static const _instantTransition = Duration(milliseconds: 100);
  static const _transitionBlinkDuration = Duration(milliseconds: 320);

  _MusicTransitionKind? _activeTransitionKind;
  AnimationController? _transitionProgressController;
  AnimationController? _transitionBlinkController;
  Animation<double>? _transitionBlinkOpacity;
  late AnimationController _expandController;
  double _compactHeight = 0;
  double _expandedHeight = 0;
  bool _isDrawerDragging = false;
  double _drawerDragProgress = 0;
  double _drawerDragStartProgress = 0;
  double _drawerDragAccumulated = 0;

  Duration get _effectiveTransitionDuration =>
      _selectedTransitionDuration ?? _instantTransition;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      value: widget.isAdvanced ? 1.0 : 0.0,
      duration: _drawerSnapDuration,
    );
  }

  @override
  void didUpdateWidget(MusicPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDesktop ||
        widget.isAdvanced == oldWidget.isAdvanced ||
        _isDrawerDragging) {
      return;
    }
    final target = widget.isAdvanced ? 1.0 : 0.0;
    if ((_expandController.value - target).abs() > 0.01) {
      _expandController.animateTo(target, curve: _drawerSnapCurve);
    }
  }

  @override
  void dispose() {
    _expandController.dispose();
    _transitionProgressController?.dispose();
    _transitionBlinkController?.dispose();
    super.dispose();
  }

  void _clearTransitionFeedback() {
    _transitionBlinkController?.dispose();
    _transitionBlinkController = null;
    _transitionBlinkOpacity = null;
    _transitionProgressController?.dispose();
    _transitionProgressController = null;
    _activeTransitionKind = null;
  }

  void _startTransitionFeedback(
    _MusicTransitionKind kind,
    Duration duration,
  ) {
    if (_selectedTransitionDuration == null) return;

    _clearTransitionFeedback();

    _transitionProgressController = AnimationController(
      vsync: this,
      duration: duration,
    );
    _transitionBlinkController = AnimationController(
      vsync: this,
      duration: _transitionBlinkDuration,
    );
    _transitionBlinkOpacity = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(
        parent: _transitionBlinkController!,
        curve: Curves.easeInOut,
      ),
    );

    setState(() => _activeTransitionKind = kind);
    _transitionBlinkController!.repeat(reverse: true);
    _transitionProgressController!.forward().whenComplete(() {
      if (!mounted) return;
      setState(_clearTransitionFeedback);
    });
  }

  void _toggleTransitionOption(Duration option) {
    setState(() {
      _selectedTransitionDuration =
          _selectedTransitionDuration == option ? null : option;
    });
  }

  void _resetTransitionDurationAfter(Duration used) {
    Future<void>.delayed(used, () {
      if (!mounted) return;
      setState(() => _selectedTransitionDuration = _defaultSelectedTransition);
    });
  }

  void _toggleMode() {
    widget.onAdvancedChanged(!widget.isAdvanced);
  }

  double get _drawerExpandProgress =>
      _isDrawerDragging ? _drawerDragProgress : _expandController.value;

  bool get _hasDrawerHeights =>
      _compactHeight > 0 && _expandedHeight > _compactHeight;

  double _snapDrawerTarget(double progress, double velocity) {
    if (velocity < -_drawerSnapVelocityThreshold) return 1.0;
    if (velocity > _drawerSnapVelocityThreshold) return 0.0;
    return progress >= 0.5 ? 1.0 : 0.0;
  }

  void _handleDrawerDragStart() {
    _drawerDragStartProgress = _expandController.value;
    _drawerDragAccumulated = 0;
    setState(() => _isDrawerDragging = true);
  }

  void _handleDrawerDragUpdate(DragUpdateDetails details) {
    if (!_hasDrawerHeights) return;
    final range = _expandedHeight - _compactHeight;
    setState(() {
      _drawerDragAccumulated += -details.delta.dy;
      _drawerDragProgress =
          (_drawerDragStartProgress + _drawerDragAccumulated / range).clamp(
            0.0,
            1.0,
          );
    });
  }

  void _handleDrawerDragEnd(DragEndDetails details) {
    if (!_hasDrawerHeights) {
      setState(() => _isDrawerDragging = false);
      return;
    }

    final velocity = details.primaryVelocity ?? 0;
    final target = _snapDrawerTarget(_drawerDragProgress, velocity);
    _expandController.value = _drawerDragProgress;
    setState(() => _isDrawerDragging = false);

    _expandController
        .animateTo(target, curve: _drawerSnapCurve)
        .then((_) {
          if (!mounted) return;
          final isAdvanced = target >= 0.5;
          if (isAdvanced != widget.isAdvanced) {
            widget.onAdvancedChanged(isAdvanced);
          }
        });
  }

  void _handleDrawerDragCancel() {
    if (!_isDrawerDragging) return;
    setState(() => _isDrawerDragging = false);
  }

  void _reportCompactHeight(double height) {
    if ((height - _compactHeight).abs() < 0.5) return;
    setState(() => _compactHeight = height);
  }

  void _reportExpandedHeight(double height) {
    if ((height - _expandedHeight).abs() < 0.5) return;
    setState(() => _expandedHeight = height);
  }

  _MusicRegieDrawer _buildRegieDrawer({
    required bool isAdvanced,
    double? expandProgress,
    VoidCallback? onVerticalDragStart,
    ValueChanged<DragUpdateDetails>? onVerticalDragUpdate,
    ValueChanged<DragEndDetails>? onVerticalDragEnd,
    VoidCallback? onVerticalDragCancel,
  }) {
    return _MusicRegieDrawer(
      state: widget.state,
      musicVolume: widget.musicVolume,
      resolveMusicPad: widget.resolveMusicPad,
      isAdvanced: isAdvanced,
      isDesktop: widget.isDesktop,
      isLocked: widget.isLocked,
      onLockedChanged: widget.onLockedChanged,
      onModeToggle: _toggleMode,
      onChooseMusic: widget.onChooseMusic,
      onPauseToggle: _handlePauseToggle,
      onSkipNext: _handleSkipNext,
      onRemoveFromQueue: widget.onRemoveFromQueue,
      onReorderMusicQueue: widget.onReorderMusicQueue,
      onMusicVolumeChanged: widget.onMusicVolumeChanged,
      selectedTransitionDuration: _selectedTransitionDuration,
      onTransitionOptionTapped: _toggleTransitionOption,
      activeTransitionKind: _activeTransitionKind,
      transitionProgress: _transitionProgressController,
      transitionBlinkOpacity: _transitionBlinkOpacity,
      expandProgress: expandProgress,
      onVerticalDragStart: onVerticalDragStart,
      onVerticalDragUpdate: onVerticalDragUpdate,
      onVerticalDragEnd: onVerticalDragEnd,
      onVerticalDragCancel: onVerticalDragCancel,
    );
  }

  Widget _buildDesktopPanel(double panelWidth) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: panelWidth,
        child: AnimatedSize(
          duration: _drawerSnapDuration,
          curve: _drawerSnapCurve,
          alignment: Alignment.topCenter,
          child: _buildRegieDrawer(isAdvanced: widget.isAdvanced),
        ),
      ),
    );
  }

  Widget _buildTouchPanel(double panelWidth) {
    final measurer = Offstage(
      child: OverflowBox(
        maxWidth: panelWidth,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ReportSize(
              onChange: (size) => _reportCompactHeight(size.height),
              child: SizedBox(
                width: panelWidth,
                child: _buildRegieDrawer(isAdvanced: false),
              ),
            ),
            _ReportSize(
              onChange: (size) => _reportExpandedHeight(size.height),
              child: SizedBox(
                width: panelWidth,
                child: _buildRegieDrawer(isAdvanced: true),
              ),
            ),
          ],
        ),
      ),
    );

    return Align(
      alignment: Alignment.bottomCenter,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          measurer,
          AnimatedBuilder(
            animation: _expandController,
            builder: (context, _) {
              final progress = _drawerExpandProgress;
              final drawer = _buildRegieDrawer(
                isAdvanced: widget.isAdvanced,
                expandProgress: progress,
                onVerticalDragStart: _handleDrawerDragStart,
                onVerticalDragUpdate: _handleDrawerDragUpdate,
                onVerticalDragEnd: _handleDrawerDragEnd,
                onVerticalDragCancel: _handleDrawerDragCancel,
              );

              if (!_hasDrawerHeights) {
                return SizedBox(width: panelWidth, child: drawer);
              }

              final height = lerpDouble(
                _compactHeight,
                _expandedHeight,
                progress,
              )!;

              return SizedBox(
                width: panelWidth,
                height: height,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: _expandedHeight,
                    maxHeight: _expandedHeight,
                    child: drawer,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _handlePauseToggle({
    required bool isPlaying,
    required bool hasCurrent,
  }) {
    if (isPlaying && hasCurrent) {
      final duration = _effectiveTransitionDuration;
      widget.onFadeOut?.call(duration);
      _startTransitionFeedback(_MusicTransitionKind.fadeOut, duration);
      _resetTransitionDurationAfter(duration);
    } else {
      widget.onTogglePlayPause?.call();
    }
  }

  void _handleSkipNext({
    required bool isPlaying,
    required bool hasQueue,
  }) {
    if (!hasQueue) {
      widget.onSkipNext?.call();
      return;
    }

    if (_selectedTransitionDuration != null) {
      final duration = _effectiveTransitionDuration;
      widget.onTransitionToNext?.call(duration);
      _startTransitionFeedback(_MusicTransitionKind.crossfade, duration);
      _resetTransitionDurationAfter(duration);
      return;
    }

    widget.onSkipNext?.call();
  }

  @override
  Widget build(BuildContext context) {
    final panelWidth = MediaQuery.sizeOf(context).width;
    if (widget.isDesktop) {
      return _buildDesktopPanel(panelWidth);
    }
    return _buildTouchPanel(panelWidth);
  }
}

class _MusicRegieDrawer extends StatefulWidget {
  /// Largeur minimale pour afficher « À l'antenne » et file de passage côte à côte.
  static const _twoColumnMinWidth = 560.0;

  /// Espacements du mode réduit — compact mais aéré.
  static const _compactDrawerPadding = EdgeInsets.fromLTRB(16, 14, 16, 16);
  static const _compactSectionGap = 10.0;

  final SamplerState state;
  final double musicVolume;
  final PadItem? Function(int padId) resolveMusicPad;
  final bool isAdvanced;
  final bool isDesktop;
  final bool isLocked;
  final ValueChanged<bool>? onLockedChanged;
  final VoidCallback onModeToggle;
  final VoidCallback onChooseMusic;
  final void Function({required bool isPlaying, required bool hasCurrent})
      onPauseToggle;
  final void Function({required bool isPlaying, required bool hasQueue})
      onSkipNext;
  final ValueChanged<int>? onRemoveFromQueue;
  final void Function(int oldIndex, int newIndex)? onReorderMusicQueue;
  final ValueChanged<double>? onMusicVolumeChanged;
  final Duration? selectedTransitionDuration;
  final ValueChanged<Duration> onTransitionOptionTapped;
  final _MusicTransitionKind? activeTransitionKind;
  final Animation<double>? transitionProgress;
  final Animation<double>? transitionBlinkOpacity;
  final double? expandProgress;
  final VoidCallback? onVerticalDragStart;
  final ValueChanged<DragUpdateDetails>? onVerticalDragUpdate;
  final ValueChanged<DragEndDetails>? onVerticalDragEnd;
  final VoidCallback? onVerticalDragCancel;

  const _MusicRegieDrawer({
    required this.state,
    required this.musicVolume,
    required this.resolveMusicPad,
    required this.isAdvanced,
    this.isDesktop = false,
    this.isLocked = false,
    this.onLockedChanged,
    required this.onModeToggle,
    required this.onChooseMusic,
    required this.onPauseToggle,
    required this.onSkipNext,
    this.onRemoveFromQueue,
    this.onReorderMusicQueue,
    this.onMusicVolumeChanged,
    required this.selectedTransitionDuration,
    required this.onTransitionOptionTapped,
    this.activeTransitionKind,
    this.transitionProgress,
    this.transitionBlinkOpacity,
    this.expandProgress,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
    this.onVerticalDragCancel,
  });

  @override
  State<_MusicRegieDrawer> createState() => _MusicRegieDrawerState();
}

class _MusicRegieDrawerState extends State<_MusicRegieDrawer> {
  bool get _isInteractive => widget.expandProgress != null && !widget.isDesktop;

  _OnAirControls _buildOnAirControls({
    required bool isPlaying,
    required bool hasCurrent,
    required bool hasQueue,
  }) {
    return _OnAirControls(
      volume: widget.musicVolume,
      onVolumeChanged: widget.onMusicVolumeChanged,
      isPlaying: isPlaying,
      hasCurrent: hasCurrent,
      hasQueue: hasQueue,
      selectedTransitionDuration: widget.selectedTransitionDuration,
      onTransitionOptionTapped: widget.onTransitionOptionTapped,
      activeTransitionKind: widget.activeTransitionKind,
      transitionProgress: widget.transitionProgress,
      transitionBlinkOpacity: widget.transitionBlinkOpacity,
      onChooseMusic: widget.onChooseMusic,
      onTogglePlayPause: () => widget.onPauseToggle(
        isPlaying: isPlaying,
        hasCurrent: hasCurrent,
      ),
      onSkipNext: () => widget.onSkipNext(
        isPlaying: isPlaying,
        hasQueue: hasQueue,
      ),
    );
  }

  Widget _buildModeBody({
    required BuildContext context,
    required ColorScheme scheme,
    required bool advanced,
    required PadItem? current,
    required bool isPlaying,
    required PadItem? next,
    required List<PadItem> queue,
    required _OnAirControls onAirControls,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns =
            constraints.maxWidth >= _MusicRegieDrawer._twoColumnMinWidth;

        if (!advanced) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CueSlot(
                label: 'À l\'antenne',
                padItem: current,
                isActive: isPlaying,
                emptyLabel: 'Aucune piste',
              ),
              const SizedBox(height: 10),
              if (current != null) ...[
                _RegieProgressBar(
                  padItem: current,
                  isPlaying: isPlaying,
                  height: 4,
                ),
              ],
              const SizedBox(height: 12),
              onAirControls,
              if (next != null) ...[
                const SizedBox(height: _MusicRegieDrawer._compactSectionGap),
                _CueSlot(
                  label: 'Prévu ensuite',
                  padItem: next,
                  isActive: true,
                  emptyLabel: '—',
                  showDownloadBar: true,
                ),
              ],
            ],
          );
        }

        final onAirCard = _OnAirCard(
          padItem: current,
          isPlaying: isPlaying,
          controls: onAirControls,
        );
        final queueSection = _PassageQueueSection(
          queue: queue,
          isDesktop: widget.isDesktop,
          onRemove: widget.onRemoveFromQueue,
          onReorder: widget.onReorderMusicQueue,
          onChooseMusic: widget.onChooseMusic,
        );

        if (useTwoColumns) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: onAirCard),
              const SizedBox(width: 12),
              Expanded(child: queueSection),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            onAirCard,
            const SizedBox(height: 12),
            queueSection,
          ],
        );
      },
    );
  }

  Widget _buildDrawerInner({
    required BuildContext context,
    required ColorScheme scheme,
    required bool advanced,
    required double? progress,
  }) {
    final current = widget.state.currentMusicPad;
    final isPlaying = current?.isPlaying ?? false;
    final queue = widget.state.musicQueue(widget.resolveMusicPad);
    final next = queue.isNotEmpty ? queue.first : null;
    final hasCurrent = current != null;
    final hasQueue = queue.isNotEmpty;
    final onAirControls = _buildOnAirControls(
      isPlaying: isPlaying,
      hasCurrent: hasCurrent,
      hasQueue: hasQueue,
    );
    final showCompactHeaderBadge =
        progress == null ? !advanced : (progress < 0.5);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: _MusicRegieDrawer._compactDrawerPadding,
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
                  const SizedBox(width: 8),
                  Text(
                    'RÉGIE MUSIQUE',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  if (isPlaying && showCompactHeaderBadge) ...[
                    const SizedBox(width: 8),
                    const _LiveBadge(compact: true),
                  ],
                  const Spacer(),
                  if (widget.isDesktop &&
                      widget.isAdvanced &&
                      widget.onLockedChanged != null)
                    _DrawerLockButton(
                      scheme: scheme,
                      isLocked: widget.isLocked,
                      onTap: () => widget.onLockedChanged!(!widget.isLocked),
                    ),
                  if (widget.isDesktop)
                    _DrawerExpandButton(
                      scheme: scheme,
                      isExpanded: widget.isAdvanced,
                      onTap: widget.onModeToggle,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (progress == null)
                _buildModeBody(
                  context: context,
                  scheme: scheme,
                  advanced: advanced,
                  current: current,
                  isPlaying: isPlaying,
                  next: next,
                  queue: queue,
                  onAirControls: onAirControls,
                )
              else
                Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    IgnorePointer(
                      ignoring: progress > 0.5,
                      child: Opacity(
                        opacity: (1 - progress).clamp(0.0, 1.0),
                        child: _buildModeBody(
                          context: context,
                          scheme: scheme,
                          advanced: false,
                          current: current,
                          isPlaying: isPlaying,
                          next: next,
                          queue: queue,
                          onAirControls: _buildOnAirControls(
                            isPlaying: isPlaying,
                            hasCurrent: hasCurrent,
                            hasQueue: hasQueue,
                          ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      ignoring: progress <= 0.5,
                      child: Opacity(
                        opacity: progress.clamp(0.0, 1.0),
                        child: _buildModeBody(
                          context: context,
                          scheme: scheme,
                          advanced: true,
                          current: current,
                          isPlaying: isPlaying,
                          next: next,
                          queue: queue,
                          onAirControls: _buildOnAirControls(
                            isPlaying: isPlaying,
                            hasCurrent: hasCurrent,
                            hasQueue: hasQueue,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = widget.expandProgress;
    final drawerBody = _buildDrawerInner(
      context: context,
      scheme: scheme,
      advanced: widget.isAdvanced,
      progress: progress,
    );

    final drawerContent = _isInteractive
        ? Semantics(
            label: (progress ?? 0) >= 0.5
                ? 'Réduire la régie'
                : 'Développer la régie',
            hint:
                'Glisser vers le haut pour développer, '
                'vers le bas pour réduire',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (_) => widget.onVerticalDragStart?.call(),
              onVerticalDragUpdate: widget.onVerticalDragUpdate,
              onVerticalDragEnd: widget.onVerticalDragEnd,
              onVerticalDragCancel: widget.onVerticalDragCancel,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  drawerBody,
                  Positioned(
                    top: 4,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 24,
                          height: 4,
                          decoration: BoxDecoration(
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: 0.35,
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        : drawerBody;

    return Material(
      color: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.none,
      child: drawerContent,
    );
  }
}

class _DrawerLockButton extends StatelessWidget {
  final ColorScheme scheme;
  final bool isLocked;
  final VoidCallback? onTap;

  const _DrawerLockButton({
    required this.scheme,
    required this.isLocked,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: isLocked ? 'Déverrouiller la régie' : 'Verrouiller la régie',
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      icon: Icon(
        isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
        size: 18,
        color: isLocked
            ? scheme.primary
            : scheme.onSurfaceVariant.withValues(alpha: 0.75),
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

/// Contrôles de lecture intégrés à la zone « À l'antenne ».
class _OnAirControls extends StatelessWidget {
  static const _volumeSliderMinWidth = 100.0;
  static const _volumeSliderMaxWidth = 150.0;
  static const _inlineGap = 8.0;
  static const _wrappedRowGap = 10.0;
  static const _volumeGroupMinWidth = _volumeSliderMinWidth;

  final double volume;
  final ValueChanged<double>? onVolumeChanged;
  final bool isPlaying;
  final bool hasCurrent;
  final bool hasQueue;
  final Duration? selectedTransitionDuration;
  final ValueChanged<Duration> onTransitionOptionTapped;
  final _MusicTransitionKind? activeTransitionKind;
  final Animation<double>? transitionProgress;
  final Animation<double>? transitionBlinkOpacity;
  final VoidCallback onChooseMusic;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback? onSkipNext;

  const _OnAirControls({
    required this.volume,
    this.onVolumeChanged,
    required this.isPlaying,
    required this.hasCurrent,
    required this.hasQueue,
    required this.selectedTransitionDuration,
    required this.onTransitionOptionTapped,
    this.activeTransitionKind,
    this.transitionProgress,
    this.transitionBlinkOpacity,
    required this.onChooseMusic,
    this.onTogglePlayPause,
    this.onSkipNext,
  });

  double _resolveSliderWidth(double available) {
    if (available <= 0) return 0;
    return available.clamp(
      available < _volumeSliderMinWidth ? available : _volumeSliderMinWidth,
      _volumeSliderMaxWidth,
    );
  }

  Widget _volumeSlider({double? width, bool flexible = false}) {
    final slider = SizedBox(
      height: 42,
      width: width,
      child: _CompactVolumeSlider(
        value: volume,
        onChanged: onVolumeChanged,
      ),
    );

    if (flexible) {
      return ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: _volumeSliderMinWidth,
          maxWidth: _volumeSliderMaxWidth,
        ),
        child: slider,
      );
    }

    return slider;
  }

  Widget _volumeRow(double maxWidth) {
    return _volumeSlider(width: _resolveSliderWidth(maxWidth));
  }

  @override
  Widget build(BuildContext context) {
    final canControl = hasCurrent || hasQueue;

    final playbackControls = _GroupedPlaybackControls(
      isPlaying: isPlaying,
      canControl: canControl,
      hasQueue: hasQueue,
      selectedTransitionDuration: selectedTransitionDuration,
      onTransitionOptionTapped: onTransitionOptionTapped,
      activeTransitionKind: activeTransitionKind,
      transitionProgress: transitionProgress,
      transitionBlinkOpacity: transitionBlinkOpacity,
      onChooseMusic: onChooseMusic,
      onTogglePlayPause: onTogglePlayPause,
      onSkipNext: onSkipNext,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final fitsOnOneLine = maxWidth >=
            _GroupedPlaybackControls.minWidth +
                _inlineGap +
                _volumeGroupMinWidth;

        final Widget controls;
        if (fitsOnOneLine) {
          controls = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              playbackControls,
              const SizedBox(width: _inlineGap),
              Flexible(child: _volumeSlider(flexible: true)),
            ],
          );
        } else {
          controls = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              playbackControls,
              const SizedBox(height: _wrappedRowGap),
              _volumeRow(maxWidth),
            ],
          );
        }

        return SizedBox(
          width: maxWidth,
          child: controls,
        );
      },
    );
  }
}

/// Play / suivant et durée de transition regroupés visuellement.
class _GroupedPlaybackControls extends StatelessWidget {
  static const _iconSize = 24.0;
  static const _actionSize = 48.0;
  static const _actionButtonSize = 40.0;
  static const _progressBadgeSize = 11.0;
  static const _transitionPickerWidth = 3 * 18.0 + 2.0;
  static const minWidth = 6.0 +
      2 * _actionButtonSize +
      6.0 +
      1.0 +
      4.0 +
      _transitionPickerWidth +
      8.0;

  final bool isPlaying;
  final bool canControl;
  final bool hasQueue;
  final Duration? selectedTransitionDuration;
  final ValueChanged<Duration> onTransitionOptionTapped;
  final _MusicTransitionKind? activeTransitionKind;
  final Animation<double>? transitionProgress;
  final Animation<double>? transitionBlinkOpacity;
  final VoidCallback onChooseMusic;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback? onSkipNext;

  const _GroupedPlaybackControls({
    required this.isPlaying,
    required this.canControl,
    required this.hasQueue,
    required this.selectedTransitionDuration,
    required this.onTransitionOptionTapped,
    this.activeTransitionKind,
    this.transitionProgress,
    this.transitionBlinkOpacity,
    required this.onChooseMusic,
    this.onTogglePlayPause,
    this.onSkipNext,
  });

  String _playTooltip() {
    if (!canControl) return 'Lancer';
    return isPlaying ? 'Pause' : 'Reprendre';
  }

  Widget _actionButton({
    required BuildContext context,
    required String tooltip,
    required VoidCallback? onPressed,
    required IconData icon,
    required bool showTransitionFeedback,
  }) {
    final scheme = Theme.of(context).colorScheme;

    Widget button = SizedBox(
      width: _actionButtonSize,
      height: _actionButtonSize,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: _iconSize,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          alignment: Alignment.center,
        ),
        constraints: const BoxConstraints(
          minWidth: _actionButtonSize,
          maxWidth: _actionButtonSize,
          minHeight: _actionButtonSize,
          maxHeight: _actionButtonSize,
        ),
        icon: Icon(icon),
      ),
    );

    if (showTransitionFeedback && transitionBlinkOpacity != null) {
      button = FadeTransition(
        opacity: transitionBlinkOpacity!,
        child: button,
      );
    }

    if (!showTransitionFeedback || transitionProgress == null) {
      return button;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          right: 2,
          top: 2,
          child: SizedBox(
            width: _progressBadgeSize,
            height: _progressBadgeSize,
            child: AnimatedBuilder(
              animation: transitionProgress!,
              builder: (context, _) {
                return CircularProgressIndicator(
                  value: transitionProgress!.value,
                  strokeWidth: 1.5,
                  backgroundColor:
                      scheme.outlineVariant.withValues(alpha: 0.25),
                  valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor = scheme.outlineVariant.withValues(alpha: 0.55);
    final playFeedback =
        activeTransitionKind == _MusicTransitionKind.fadeOut;
    final skipFeedback =
        activeTransitionKind == _MusicTransitionKind.crossfade;
    final transitionInProgress = activeTransitionKind != null;

    return Material(
      color: Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: borderColor)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: _actionSize,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _actionButton(
                context: context,
                tooltip: _playTooltip(),
                onPressed: transitionInProgress
                    ? null
                    : (canControl ? onTogglePlayPause : onChooseMusic),
                icon: canControl
                    ? (isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded)
                    : Icons.play_arrow_rounded,
                showTransitionFeedback: playFeedback,
              ),
            ),
            _actionButton(
              context: context,
              tooltip: 'Suivant',
              onPressed: hasQueue && !transitionInProgress ? onSkipNext : null,
              icon: Icons.skip_next_rounded,
              showTransitionFeedback: skipFeedback,
            ),
            const SizedBox(width: 6),
            Container(
              width: 1,
              height: 24,
              color: borderColor,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 8),
              child: _CompactTransitionPicker(
                selected: selectedTransitionDuration,
                onOptionTapped: onTransitionOptionTapped,
              ),
            ),
          ],
        ),
      ),
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
      height: 42,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (_isActive)
            Positioned(
              left: 0,
              right: 0,
              bottom: 26,
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
              trackHeight: 3,
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

/// Sélecteur minimal de durée (1 / 3 / 5 s) — reclic pour désélectionner.
class _CompactTransitionPicker extends StatelessWidget {
  final Duration? selected;
  final ValueChanged<Duration> onOptionTapped;

  static const _options = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 5),
  ];

  const _CompactTransitionPicker({
    required this.selected,
    required this.onOptionTapped,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontSize: 9,
      fontWeight: FontWeight.w600,
      height: 1,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _options.length; i++) ...[
          if (i > 0) const SizedBox(width: 1),
          _TransitionCell(
            label: '${_options[i].inSeconds}',
            isSelected: selected == _options[i],
            onTap: () => onOptionTapped(_options[i]),
            labelStyle: labelStyle,
            scheme: scheme,
          ),
        ],
      ],
    );
  }
}

class _TransitionCell extends StatelessWidget {
  static const _size = 18.0;

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
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: _size,
          height: _size,
          alignment: Alignment.center,
          decoration: isSelected
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primaryContainer.withValues(alpha: 0.65),
                )
              : null,
          child: Text(
            label,
            style: labelStyle?.copyWith(
              color: isSelected
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
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

/// Indicateur circulaire de téléchargement pour la régie musique.
class _RegieDownloadRing extends StatelessWidget {
  final PadItem padItem;
  final double size;

  const _RegieDownloadRing({
    required this.padItem,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    if (!padItem.showsRegieDownloadProgress) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: size >= 24 ? 2.5 : 2,
        value: padItem.regieDownloadProgress,
        color: scheme.tertiary,
        backgroundColor: scheme.tertiary.withValues(alpha: 0.18),
      ),
    );
  }
}

/// Barre de progression linéaire sous une piste en file.
class _RegieDownloadBar extends StatelessWidget {
  final PadItem padItem;

  const _RegieDownloadBar({required this.padItem});

  @override
  Widget build(BuildContext context) {
    if (!padItem.showsRegieDownloadProgress) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        minHeight: 3,
        value: padItem.regieDownloadProgress,
        color: scheme.tertiary,
        backgroundColor: scheme.tertiary.withValues(alpha: 0.15),
      ),
    );
  }
}

class _CueSlot extends StatelessWidget {
  final String label;
  final PadItem? padItem;
  final bool isActive;
  final String emptyLabel;
  final bool showDownloadBar;

  const _CueSlot({
    required this.label,
    required this.padItem,
    required this.isActive,
    required this.emptyLabel,
    this.showDownloadBar = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
        const SizedBox(height: 6),
        Row(
          children: [
            if (padItem != null)
              _PadColorChip(padItem: padItem!, size: 14)
            else
              const _OnAirEmptyChip(size: 14),
            const SizedBox(width: 8),
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
            if (padItem != null)
              _RegieDownloadRing(padItem: padItem!, size: 22),
          ],
        ),
        if (showDownloadBar && padItem != null) ...[
          const SizedBox(height: 6),
          _RegieDownloadBar(padItem: padItem!),
        ],
      ],
    );
  }
}

class _OnAirCard extends StatelessWidget {
  final PadItem? padItem;
  final bool isPlaying;
  final Widget controls;

  const _OnAirCard({
    required this.padItem,
    required this.isPlaying,
    required this.controls,
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (padItem != null)
                  _PadColorChip(padItem: padItem!, size: 40)
                else
                  const _OnAirEmptyChip(size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        padItem?.pad.displayName ?? 'Aucune musique lancée',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: padItem != null
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                            ),
                      ),
                      if (padItem != null && padItem!.pad.sounds.length > 1)
                        Text(
                          '${padItem!.pad.sounds.length} variantes',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      else if (padItem == null)
                        Text(
                          'Choisissez une piste pour démarrer',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant
                                .withValues(alpha: 0.75),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (padItem != null)
              _RegieProgressBar(
                padItem: padItem,
                isPlaying: isPlaying,
                showTimes: true,
              ),
            const SizedBox(height: 12),
            controls,
          ],
        ),
      ),
    );
  }
}

class _RegieProgressBar extends StatefulWidget {
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
  State<_RegieProgressBar> createState() => _RegieProgressBarState();
}

class _RegieProgressBarState extends State<_RegieProgressBar>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  bool get _isLive =>
      widget.isPlaying && (widget.padItem?.isPlaying ?? false);

  bool get _hasTrack => widget.padItem != null;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    });
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _RegieProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    if (_isLive) {
      if (!_ticker.isActive) _ticker.start();
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  ({Duration position, Duration duration, double value}) _playbackState() {
    final padItem = widget.padItem;
    if (padItem == null) {
      return (position: Duration.zero, duration: Duration.zero, value: 0);
    }

    final player = padItem.progressPlayer;
    final duration = player?.duration ?? Duration.zero;

    final Duration position;
    if (_isLive && padItem.currentPlayer != null) {
      position = padItem.currentPlayer!.position;
    } else {
      position = padItem.pausedPlaybackPosition ?? Duration.zero;
    }

    if (duration.inMilliseconds <= 0) {
      return (position: position, duration: duration, value: 0);
    }

    final value = (position.inMilliseconds / duration.inMilliseconds)
        .clamp(0.0, 1.0);
    return (position: position, duration: duration, value: value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playback = _playbackState();

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(widget.height),
          child: LinearProgressIndicator(
            value: _hasTrack ? playback.value : 0,
            minHeight: widget.height,
            backgroundColor: scheme.outlineVariant.withValues(alpha: 0.35),
            valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
          ),
        ),
        if (widget.showTimes) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(playback.position),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                _formatDuration(playback.duration),
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
  final bool isDesktop;
  final ValueChanged<int>? onRemove;
  final void Function(int oldIndex, int newIndex)? onReorder;
  final VoidCallback? onChooseMusic;

  const _PassageQueueSection({
    required this.queue,
    this.isDesktop = false,
    this.onRemove,
    this.onReorder,
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
            Text(
              'File de passage',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
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
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  padding: EdgeInsets.zero,
                  proxyDecorator: _queueDragProxyDecorator,
                  itemCount: queue.length,
                  onReorderItem: onReorder == null
                      ? null
                      : (oldIndex, newIndex) =>
                          onReorder!(oldIndex, newIndex),
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
                ),
              ),
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
                  padItem.pad.displayName,
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
                  tooltip: 'Retirer',
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

/// Pastille vide affichée quand aucune piste n'est à l'antenne.
class _OnAirEmptyChip extends StatelessWidget {
  final double size;

  const _OnAirEmptyChip({required this.size});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(size > 20 ? 8 : 4),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: size >= 32
          ? Icon(
              Icons.music_note_outlined,
              size: size * 0.45,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
            )
          : null,
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
      final scheme = theme.colorScheme;
      final baseColor = theme.canvasColor;
      const dragElevation = 6.0;
      final elevatedColor = ElevationOverlay.applySurfaceTint(
        baseColor,
        scheme.surfaceTint,
        dragElevation,
      );
      final animValue = Curves.easeInOut.transform(animation.value);
      return Material(
        color: Color.lerp(baseColor, elevatedColor, animValue),
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

