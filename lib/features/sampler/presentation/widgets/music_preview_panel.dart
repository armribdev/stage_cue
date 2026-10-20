import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart'
    show
        HardwareKeyboard,
        KeyDownEvent,
        KeyEvent,
        KeyUpEvent,
        LogicalKeyboardKey;
import '../../../../core/audio/waveform_extractor.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/sound_color_utils.dart';
import '../../domain/entities/sound.dart';
import '../providers/sampler_provider.dart';
import '../utils/sound_type_ui.dart';
import 'boxed_icon_button.dart';
import 'waveform_envelope.dart';

part 'music_regie_drawer.dart';
part 'music_regie_ambiance_slot.dart';
part 'music_regie_playback_controls.dart';
part 'music_regie_volume_transitions.dart';
part 'music_regie_progress.dart';
part 'music_regie_queue_section.dart';

enum _MusicTransitionKind { fadeOut, crossfade }

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

  /// « Ajouter à la file » : ouvre le sélecteur en mode mise en file.
  final VoidCallback onChooseMusic;

  /// Bouton lecture quand rien n'est chargé : ouvre le sélecteur en mode
  /// lecture immédiate. À défaut, retombe sur [onChooseMusic].
  final VoidCallback? onChooseMusicToPlay;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback? onSkipNext;

  /// Éjecte la musique en cours (coupe et oublie la position de reprise) —
  /// désactivé pendant la lecture : il faut d'abord mettre en pause ou
  /// attendre le fondu pour éviter une coupure sèche accidentelle.
  final VoidCallback? onEjectMusic;
  final ValueChanged<int>? onRemoveFromQueue;
  final void Function(int oldIndex, int newIndex)? onReorderMusicQueue;
  final ValueChanged<double>? onMusicVolumeChanged;
  final ValueChanged<Duration>? onFadeOut;
  final ValueChanged<Duration>? onTransitionToNext;

  /// Repositionne la lecture quand la régie est en pause (scrub sur la waveform).
  final ValueChanged<Duration>? onSeekMusic;
  final bool isAdvanced;
  final ValueChanged<bool> onAdvancedChanged;
  final bool isDesktop;

  /// Hauteur occupée en bas de l'écran — pour réserver l'espace sous la grille.
  final ValueChanged<double>? onOccupiedHeightChanged;

  /// Voie ambiance : volume de voie, choix (sélecteur), arrêt avec un fondu
  /// (`null` = fondu par défaut du contrôleur) et réglage du volume.
  final double ambianceVolume;
  final VoidCallback? onChooseAmbiance;
  final ValueChanged<Duration?>? onStopAmbiance;
  final ValueChanged<double>? onAmbianceVolumeChanged;

  const MusicPreviewPanel({
    super.key,
    required this.state,
    required this.musicVolume,
    this.ambianceVolume = 1.0,
    this.onChooseAmbiance,
    this.onStopAmbiance,
    this.onAmbianceVolumeChanged,
    required this.resolveMusicPad,
    required this.isAdvanced,
    required this.onAdvancedChanged,
    required this.onChooseMusic,
    this.onChooseMusicToPlay,
    this.onTogglePlayPause,
    this.onSkipNext,
    this.onEjectMusic,
    this.onRemoveFromQueue,
    this.onReorderMusicQueue,
    this.onMusicVolumeChanged,
    this.onFadeOut,
    this.onTransitionToNext,
    this.onSeekMusic,
    this.isDesktop = false,
    this.onOccupiedHeightChanged,
  });

  @override
  State<MusicPreviewPanel> createState() => _MusicPreviewPanelState();
}

class _MusicPreviewPanelState extends State<MusicPreviewPanel>
    with TickerProviderStateMixin {
  /// Durée du fondu sélectionnée — `null` = coupe sèche (état de repos par
  /// défaut : aucun fondu, on opte pour une durée à chaque fois qu'on en veut).
  Duration? _selectedTransitionDuration;

  /// Verrou de la durée sélectionnée (appui long) : quand `true`, la durée ne
  /// retombe plus automatiquement sur la coupe sèche après une transition.
  bool _transitionDurationLocked = false;

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
  double _lastReportedOccupiedHeight = -1;

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

  void _startTransitionFeedback(_MusicTransitionKind kind, Duration duration) {
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
      // La cellule ciseaux (sentinelle `Duration.zero`) sélectionne la coupe
      // sèche, matérialisée par l'état `null` (aucun fondu). Elle lève aussi
      // tout verrou éventuel.
      if (option == _CompactTransitionPicker.cutSentinel) {
        _selectedTransitionDuration = null;
        _transitionDurationLocked = false;
        return;
      }
      // Tap simple : sélection temporaire (reviendra au cut après transition).
      // Reclic sur la même durée → désélection, et on lève le verrou.
      _selectedTransitionDuration = _selectedTransitionDuration == option
          ? null
          : option;
      _transitionDurationLocked = false;
    });
  }

  /// Appui long sur une durée : verrouille (ou déverrouille) la sélection pour
  /// qu'elle ne retombe plus sur la coupe sèche après chaque transition.
  void _lockTransitionOption(Duration option) {
    // Le verrou n'a pas de sens sur la coupe sèche.
    if (option == _CompactTransitionPicker.cutSentinel) return;
    setState(() {
      if (_selectedTransitionDuration == option && _transitionDurationLocked) {
        // Re-appui long sur la durée déjà verrouillée → déverrouille (la
        // sélection redevient temporaire).
        _transitionDurationLocked = false;
      } else {
        _selectedTransitionDuration = option;
        _transitionDurationLocked = true;
      }
    });
  }

  /// Après une transition, retour à la coupe sèche (état de repos par défaut) —
  /// sauf si la durée est verrouillée : elle reste alors sélectionnée.
  void _resetTransitionDurationAfter(Duration used) {
    if (_transitionDurationLocked) return;
    Future<void>.delayed(used, () {
      if (!mounted || _transitionDurationLocked) return;
      setState(() => _selectedTransitionDuration = null);
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

    _expandController.animateTo(target, curve: _drawerSnapCurve).then((_) {
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

  void _notifyOccupiedHeight(double height) {
    if ((height - _lastReportedOccupiedHeight).abs() < 0.5) return;
    _lastReportedOccupiedHeight = height;
    widget.onOccupiedHeightChanged?.call(height);
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
      onModeToggle: _toggleMode,
      onChooseMusic: widget.onChooseMusic,
      onChooseMusicToPlay: widget.onChooseMusicToPlay ?? widget.onChooseMusic,
      onPauseToggle: _handlePauseToggle,
      onSkipNext: _handleSkipNext,
      onEjectMusic: widget.onEjectMusic,
      onRemoveFromQueue: widget.onRemoveFromQueue,
      onReorderMusicQueue: widget.onReorderMusicQueue,
      onMusicVolumeChanged: widget.onMusicVolumeChanged,
      onSeekMusic: widget.onSeekMusic,
      ambianceVolume: widget.ambianceVolume,
      onChooseAmbiance: widget.onChooseAmbiance,
      // Le sélecteur de fondu (1/3/5 s, coupe) est pensé pour la musique :
      // l'ambiance garde toujours son propre fondu, plus long et plus doux.
      onStopAmbiance: widget.onStopAmbiance == null
          ? null
          : () => widget.onStopAmbiance!(null),
      onAmbianceVolumeChanged: widget.onAmbianceVolumeChanged,
      selectedTransitionDuration: _selectedTransitionDuration,
      transitionDurationLocked: _transitionDurationLocked,
      onTransitionOptionTapped: _toggleTransitionOption,
      onTransitionOptionLongPressed: _lockTransitionOption,
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
    return SizedBox(
      width: panelWidth,
      child: AnimatedSize(
        duration: _drawerSnapDuration,
        curve: _drawerSnapCurve,
        alignment: Alignment.topCenter,
        child: _buildRegieDrawer(isAdvanced: widget.isAdvanced),
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

              Widget panel;
              if (!_hasDrawerHeights) {
                panel = SizedBox(width: panelWidth, child: drawer);
              } else {
                final height = lerpDouble(
                  _compactHeight,
                  _expandedHeight,
                  progress,
                )!;

                panel = SizedBox(
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
              }

              return _ReportSize(
                onChange: (size) => _notifyOccupiedHeight(size.height),
                child: panel,
              );
            },
          ),
        ],
      ),
    );
  }

  void _handlePauseToggle({required bool isPlaying, required bool hasCurrent}) {
    if (isPlaying && hasCurrent) {
      final duration = _effectiveTransitionDuration;
      widget.onFadeOut?.call(duration);
      _startTransitionFeedback(_MusicTransitionKind.fadeOut, duration);
      _resetTransitionDurationAfter(duration);
    } else {
      widget.onTogglePlayPause?.call();
    }
  }

  void _handleSkipNext({required bool isPlaying, required bool hasQueue}) {
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
