import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../core/audio/waveform_extractor.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/transport_icon.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/layout_utils.dart';
import '../providers/sampler_provider.dart';
import 'sound_edit_preload.dart';
import 'waveform_envelope.dart';
import '../../../../core/theme/stroke_icon.dart';

/// Zone cliquable autour de la poignée sur desktop (souris).
const _kHandleHitHalfWidthDesktop = 14.0;
const _kHandleHitHalfWidthMobile = 28.0;

/// Écart (px) sous lequel poignée et tête de lecture comptent comme superposées.
const _kOverlapPx = 8.0;

/// Marge horizontale de part et d'autre de la piste : pastille de la poignée
/// (rayon 5,5 au survol) et repère de la tête (±5) restent entiers, même au
/// tout début ou à la toute fin du son, sans dépasser du cadre de l'éditeur.
const _kTrackInset = 7.0;

/// Hauteur réservée au-dessus de la waveform pour le repère de temps : fixe,
/// pour que le survol ne fasse pas « sauter » la mise en page.
const _kTagStripHeight = 20.0;

/// Pas des flèches du clavier, et avec Maj.
const _kKeyStepMs = 100;
const _kKeyBigStepMs = 1000;

/// Étalement du balayage de la croissance : 1 = tous les points montent en
/// même temps, plus grand = le front de gauche à droite est plus marqué.
const _kRevealSweep = 1.6;

/// Ce qu'un geste sur la waveform déplace.
enum _Grab { handle, playhead }

/// Éditeur du point d'entrée d'un son : waveform scrubbable avec une poignée
/// draggable, aperçu audio depuis le point choisi et réglage fin (±0,1 s).
/// La zone avant le point d'entrée est grisée pour montrer d'un coup d'œil ce
/// qui sera sauté à la lecture.
///
/// La tête de lecture (jaune) est toujours visible et se déplace au glisser :
/// à l'arrêt elle marque d'où repartira ▶, en aperçu l'audio repart de la
/// position relâchée. Poignée et tête superposées : pastille en haut = poignée,
/// repère en bas = tête. En aperçu, un clic ailleurs déplace la tête ; à
/// l'arrêt, il déplace le point d'entrée.
///
/// N'a pas de lecteur propre : il charge et pilote le lecteur d'aperçu unique du
/// [SamplerNotifier] (durée, ▶/⏸, position), le même que le bouton de ligne de la
/// liste — l'un lance ou arrête ce que l'autre voit. Si le fichier n'est pas
/// disponible localement, l'éditeur s'affiche désactivé avec un message.
///
/// Navigation : un repère de temps suit le pointeur (et l'élément glissé), un
/// trait fantôme annonce ce qu'un clic déplacerait, « Placer ici » fixe le
/// point d'entrée à la position de lecture, et la waveform se pilote au clavier
/// (←/→ ±0,1 s, Maj ±1 s, Espace ▶/⏸, Entrée = Placer ici).
class StartOffsetEditor extends StatefulWidget {
  final int soundId;

  /// Porteur du lecteur d'aperçu ; `null` = pas d'aperçu possible (éditeur
  /// désactivé avec son message).
  final SamplerNotifier? notifier;
  final Uint8List? waveform;

  /// L'enveloppe est en cours d'extraction : la piste pulse au lieu de montrer
  /// une ligne plate, puis la waveform croît quand elle arrive.
  final bool waveformPending;

  /// Ce que le formulaire précédent laisse (son enveloppe) et où inscrire la
  /// nôtre, pour passer d'un son à l'autre par une transformation et non une
  /// piste vide. `null` = pas de suite.
  final SoundFormMemory? memory;
  final int initialOffsetMs;

  /// Volume d'écoute (0.0 → 1.0) : celui du son, pour que l'audition du point
  /// d'entrée soit au niveau réel. Relu à chaque lecture.
  final double volume;

  /// Volume tel que montré (suit [volume], en glissant quand il change d'un
  /// coup) : la waveform en est l'échelle, en phase avec le curseur du
  /// formulaire.
  final ValueListenable<double> displayVolume;

  /// Notifié à chaque changement de valeur (drag, nudge, reset).
  final ValueChanged<int> onChanged;

  /// Lance l'aperçu depuis le point d'entrée dès que la source est chargée
  /// (file de traitement : trier se fait à l'oreille, tête de lecture visible).
  /// Lu au chargement seulement ; passer à `false` ensuite coupe l'aperçu en
  /// cours.
  final bool autoPlay;

  const StartOffsetEditor({
    super.key,
    required this.soundId,
    required this.notifier,
    required this.waveform,
    this.waveformPending = false,
    this.memory,
    required this.initialOffsetMs,
    required this.volume,
    required this.displayVolume,
    required this.onChanged,
    this.autoPlay = false,
  });

  @override
  State<StartOffsetEditor> createState() => _StartOffsetEditorState();
}

class _StartOffsetEditorState extends State<StartOffsetEditor>
    with TickerProviderStateMixin {
  static const _nudgeStep = Duration(milliseconds: 100);
  static const _waveHeight = 56.0;

  /// Apparition de la poignée, de la tête et de la couleur une fois le son
  /// chargé ; durée de la transformation de l'enveloppe.
  static const _settleDuration = Duration(milliseconds: 200);

  /// Glissement de la poignée et de la tête d'une position à l'autre.
  static const _glideDuration = Duration(milliseconds: 180);

  /// Transformation de l'enveloppe affichée vers celle du son, de gauche à
  /// droite (0 → 1) : depuis la waveform du son précédent (`_morphFrom`), ou
  /// depuis l'axe médian s'il n'y en a pas. Part dès que l'enveloppe est connue
  /// (et le son chargé, s'il n'en suit pas un autre), même durée que le
  /// glissement du volume.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: kSoundSwitchDuration,
  );

  /// Respiration de la ligne médiane tant que l'enveloppe est attendue.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  /// Enveloppe du son (décodée une fois par changement de `widget.waveform`).
  late List<double> _bars = decodeWaveformBars(widget.waveform);

  /// Enveloppe d'où part la transformation : celle du son précédent (laissée
  /// par le formulaire d'avant), puis celle qui était affichée.
  late List<double> _morphFrom =
      widget.memory?.waveformBars ?? const <double>[];

  /// Enveloppe vers laquelle `_reveal` a été lancé ; `null` = pas encore.
  List<double>? _revealedFor;

  /// La poignée et la tête glissent d'une position à l'autre. Éteint tant que
  /// rien ne les précède : à l'ouverture elles se posent d'emblée, sans glisser
  /// depuis le bord gauche.
  late bool _glideEnabled = _hasPrevious;

  /// Un son était affiché avant celui-ci : sa waveform, sa poignée et sa tête
  /// restent à l'écran, telles quelles, jusqu'à ce que ce son soit chargé.
  late final bool _hasPrevious = widget.memory?.offsetFraction != null;

  /// Un geste a bougé depuis son appui : poignée / tête suivent alors le
  /// pointeur sans retard (l'appui seul, lui, glisse jusqu'au point cliqué).
  bool _dragMoved = false;

  Duration _glideFor({required bool live}) =>
      live || !_glideEnabled || _reduceMotion ? Duration.zero : _glideDuration;

  bool _loading = true;
  bool _loadFailed = false;
  Duration _duration = Duration.zero;

  late int _offsetMs;
  bool _isPreviewing = false;
  bool _isDragging = false;

  /// Un geste en cours déplace la tête de lecture (et non la poignée).
  bool _isScrubbingPlayhead = false;
  _Grab? _hover;

  /// Position (0→1) du pointeur souris au-dessus de la waveform, ou `null`.
  double? _pointerFraction;
  int? _activePointer;
  final _focusNode = FocusNode(debugLabel: 'StartOffsetEditor');
  Ticker? _ticker;

  /// Tête de lecture, toujours affichée. À l'arrêt elle marque d'où repartira
  /// ▶ : elle suit le point d'entrée tant qu'on ne l'a pas déplacée à la main.
  Duration _playhead = Duration.zero;

  SamplerNotifier? get _notifier => widget.notifier;

  @override
  void initState() {
    super.initState();
    _offsetMs = widget.initialOffsetMs;
    _notifier?.addListener(_onNotifierChanged);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(StartOffsetEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Le volume suit en direct : `SoundEditForm` le répercute sur le lecteur.
    if (oldWidget.autoPlay && !widget.autoPlay && _isPreviewing) {
      _notifier?.stopLibraryPreview();
    }
    if (!identical(oldWidget.waveform, widget.waveform)) {
      _bars = decodeWaveformBars(widget.waveform);
    }
    _syncWaveformMotion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncWaveformMotion();
  }

  /// Aligne les animations sur l'état : pulsation tant que l'enveloppe est
  /// attendue, transformation une fois par enveloppe quand le son est chargé.
  void _syncWaveformMotion() {
    final waiting = _bars.isEmpty && (_loading || widget.waveformPending);
    if (waiting && !_reduceMotion) {
      if (!_pulse.isAnimating) unawaited(_pulse.repeat(reverse: true));
    } else {
      _pulse.reset();
    }
    // D'un son à l'autre, la transformation part dès l'affichage — avec le
    // glissement du curseur de volume — sans attendre le chargement du son ;
    // à la première ouverture, elle accompagne l'apparition de la piste.
    if ((_loading && !_hasPrevious) || _loadFailed || waiting) return;
    if (identical(_revealedFor, _bars)) return;
    // Une enveloppe a déjà été montrée (plate, en attendant celle-ci) : c'est
    // d'elle que la suivante part.
    final shown = _revealedFor;
    if (shown != null) _morphFrom = shown;
    _revealedFor = _bars;
    widget.memory?.waveformBars = _bars;
    if (_reduceMotion) {
      _reveal.value = 1;
    } else {
      unawaited(_reveal.forward(from: 0));
    }
  }

  /// Laisse au formulaire suivant la position du point d'entrée, d'où sa
  /// poignée partira.
  void _rememberOffset() =>
      widget.memory?.offsetFraction = _fractionOf(_offsetMs);

  Future<void> _load() async {
    final duration = await _notifier?.loadLibraryPreview(widget.soundId);
    if (!mounted) return;
    if (duration == null) {
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
      return;
    }
    setState(() {
      _duration = duration;
      _offsetMs = _offsetMs.clamp(0, duration.inMilliseconds);
      _playhead = _offset;
      _loading = false;
    });
    _syncWaveformMotion();
    _rememberOffset();
    // Les repères viennent de se poser : à partir de l'image suivante, ils
    // glissent d'une position à l'autre.
    if (!_glideEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _glideEnabled = true);
      });
    }
    // Un aperçu déjà en cours pour ce son (lancé depuis la liste) : on le suit.
    _onNotifierChanged();
    if (!widget.autoPlay || duration <= Duration.zero || _isPreviewing) return;
    // Silencieux : un son pas encore prêt ne doit pas noyer la file sous les
    // messages (le ▶ manuel reste disponible et, lui, signale son échec).
    await _togglePreview(reportFailure: false);
  }

  /// Le lecteur est partagé : on suit son état plutôt que le nôtre, que la
  /// lecture vienne d'ici, du bouton de ligne ou d'une fin de piste.
  void _onNotifierChanged() {
    final notifier = _notifier;
    if (notifier == null || !mounted || _loading) return;
    final playing = notifier.libraryPreviewIsPlaying(widget.soundId);
    if (playing == _isPreviewing) return;
    setState(() {
      _isPreviewing = playing;
      // Arrêt (manuel ou fin de piste) : la tête revient au point d'entrée.
      if (!playing) _playhead = _offset;
    });
    _syncTicker();
  }

  @override
  void dispose() {
    _notifier?.removeListener(_onNotifierChanged);
    _ticker?.dispose();
    _reveal.dispose();
    _pulse.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Duration get _offset => Duration(milliseconds: _offsetMs);

  void _setOffsetMs(int ms) {
    final clamped = ms.clamp(0, _duration.inMilliseconds);
    if (clamped == _offsetMs) return;
    setState(() {
      _offsetMs = clamped;
      // À l'arrêt, la tête reste calée sur le point d'entrée.
      if (!_isPreviewing) _playhead = _offset;
    });
    _rememberOffset();
    widget.onChanged(clamped);
  }

  void _nudge(int signMs) => _setOffsetMs(_offsetMs + signMs);

  /// Seul cas où la tête diffère du point d'entrée : un aperçu en cours.
  bool get _canPlaceHere => _isPreviewing && _playhead != _offset;

  /// Fixe le point d'entrée à la position de lecture (écouter, puis valider au
  /// bon moment). L'aperçu continue sans interruption.
  void _placeAtPlayhead() {
    if (_canPlaceHere) _setOffsetMs(_playhead.inMilliseconds);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_loading || _loadFailed || _duration <= Duration.zero) {
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final step = HardwareKeyboard.instance.isShiftPressed
        ? _kKeyBigStepMs
        : _kKeyStepMs;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _nudge(-step);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _nudge(step);
      return KeyEventResult.handled;
    }
    // Les actions ci-dessous ne se répètent pas quand la touche reste enfoncée.
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.space) {
      unawaited(_togglePreview());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _placeAtPlayhead();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// ▶ lance l'aperçu depuis la tête de lecture, au volume et au point réglés
  /// ici (pas encore enregistrés) ; ⏸ l'arrête.
  Future<void> _togglePreview({bool reportFailure = true}) async {
    final notifier = _notifier;
    if (notifier == null) return;
    final ok = await notifier.toggleLibraryPreview(
      widget.soundId,
      from: _playhead,
      volume: widget.volume,
    );
    if (ok || !reportFailure || !mounted) return;
    // Refus de pré-écoute au casque (jamais avalé) ou son indisponible.
    showCopyableSnackBar(
      context,
      notifier.consumeLastPreviewError() ??
          'Aperçu impossible — vérifiez que le son est disponible.',
    );
  }

  void _syncTicker() {
    if (_isPreviewing) {
      _ticker ??= Ticker((_) {
        if (!mounted || _isScrubbingPlayhead) return;
        setState(
          () => _playhead =
              _notifier?.libraryPreviewPosition(widget.soundId) ?? _playhead,
        );
      });
      if (!_ticker!.isActive) _ticker!.start();
    } else if (_ticker?.isActive ?? false) {
      _ticker!.stop();
    }
  }

  String _fmt(Duration d) {
    final totalMs = d.inMilliseconds;
    final minutes = totalMs ~/ 60000;
    final seconds = (totalMs ~/ 1000) % 60;
    final tenths = (totalMs % 1000) ~/ 100;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.$tenths';
  }

  double _handleHitHalfWidth() => isNativeDesktopPlatform()
      ? _kHandleHitHalfWidthDesktop
      : _kHandleHitHalfWidthMobile;

  double _fractionOf(num ms) => _duration.inMilliseconds == 0
      ? 0.0
      : (ms / _duration.inMilliseconds).clamp(0.0, 1.0);

  /// Élément attrapable sous le curseur [p], ou `null` s'il n'y en a aucun à
  /// portée. Le plus proche l'emporte (sinon la zone de la poignée, large,
  /// avalerait la tête de lecture). Quand les deux sont superposées — cas
  /// normal à l'arrêt, où la tête repose sur le point d'entrée — la moitié
  /// haute de la waveform (pastille de la poignée) attrape la poignée, la
  /// moitié basse (repère de la tête) attrape la tête.
  _Grab? _hitAt(Offset p, double width) {
    final track = width - 2 * _kTrackInset;
    if (track <= 0) return null;
    final handleDistance =
        (p.dx - _kTrackInset - track * _fractionOf(_offsetMs)).abs();
    final playheadDistance =
        (p.dx - _kTrackInset - track * _fractionOf(_playhead.inMilliseconds))
            .abs();
    final reach = _handleHitHalfWidth();
    final nearHandle = handleDistance <= reach;
    final nearPlayhead = playheadDistance <= reach;
    if (nearHandle && nearPlayhead) {
      if ((handleDistance - playheadDistance).abs() <= _kOverlapPx) {
        return p.dy > _waveHeight / 2 ? _Grab.playhead : _Grab.handle;
      }
      return handleDistance < playheadDistance ? _Grab.handle : _Grab.playhead;
    }
    if (nearHandle) return _Grab.handle;
    if (nearPlayhead) return _Grab.playhead;
    return null;
  }

  /// Cible d'un geste qui démarre en [p] : l'élément touché ; à défaut, en
  /// aperçu la tête de lecture (le clic la déplace), sinon la poignée.
  _Grab _grabTarget(Offset p, double width) =>
      _hitAt(p, width) ?? (_isPreviewing ? _Grab.playhead : _Grab.handle);

  SystemMouseCursor _waveformCursor() {
    if (_isDragging || _isScrubbingPlayhead || _hover != null) {
      return SystemMouseCursors.resizeLeftRight;
    }
    // En aperçu, hors de la poignée, le geste déplace la tête de lecture.
    if (_isPreviewing) return SystemMouseCursors.click;
    return isNativeDesktopPlatform()
        ? SystemMouseCursors.resizeLeftRight
        : SystemMouseCursors.click;
  }

  double _fractionAtDx(double dx, double width) {
    final track = width - 2 * _kTrackInset;
    return track <= 0 ? 0.0 : ((dx - _kTrackInset) / track).clamp(0.0, 1.0);
  }

  void _updateHover(Offset p, double width) {
    final hover = _hitAt(p, width);
    final fraction = _fractionAtDx(p.dx, width);
    if (hover == _hover && fraction == _pointerFraction) return;
    setState(() {
      _hover = hover;
      _pointerFraction = fraction;
    });
  }

  /// Repère de temps flottant : l'élément en cours de glisser, sinon l'élément
  /// survolé, sinon la position du pointeur — dans la couleur de ce qu'un clic
  /// déplacerait (tête en aperçu, point d'entrée sinon).
  _TimeTagData? _tagData(ColorScheme scheme) {
    if (_isScrubbingPlayhead || (!_isDragging && _hover == _Grab.playhead)) {
      return _TimeTagData(
        _fractionOf(_playhead.inMilliseconds),
        _playhead,
        scheme.tertiary,
      );
    }
    if (_isDragging || _hover == _Grab.handle) {
      return _TimeTagData(_fractionOf(_offsetMs), _offset, scheme.primary);
    }
    final fraction = _pointerFraction;
    if (fraction == null) return null;
    return _TimeTagData(
      fraction,
      Duration(milliseconds: (fraction * _duration.inMilliseconds).round()),
      _isPreviewing ? scheme.tertiary : scheme.primary,
    );
  }

  void _endDrag() {
    if (!_isDragging && _activePointer == null) return;
    setState(() {
      _isDragging = false;
      _isScrubbingPlayhead = false;
      _dragMoved = false;
      _activePointer = null;
    });
  }

  void _scrubPlayheadTo(double fraction) {
    setState(() {
      _playhead = Duration(
        milliseconds: (fraction * _duration.inMilliseconds).round(),
      );
    });
  }

  /// Relâchement d'un geste sur la tête de lecture : l'audio repart de là.
  /// Sans effet si l'aperçu s'est arrêté entre-temps (fin de piste).
  void _commitPlayheadSeek() {
    if (!_isPreviewing) return;
    unawaited(
      _notifier?.seekLibraryPreview(
        widget.soundId,
        _playhead,
        volume: widget.volume,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (!_loading && (_loadFailed || _duration <= Duration.zero)) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: AppRadius.radiusLg,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            StrokeIcon(
              AppIcons.info,
              size: AppIconSize.sm,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Téléchargez le son pour régler son point d\'entrée.',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Chargement : la barre de contrôles est déjà là (désactivée) et la bande
    // du repère de temps est réservée, pour que rien ne « saute » à l'arrivée
    // de la source.
    final tag = _loading ? null : _tagData(scheme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _kTagStripHeight,
          child: tag == null
              ? null
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _kTrackInset),
                  // L'alignement garde l'étiquette entière dans la piste : elle
                  // glisse avec le pointeur sans jamais déborder aux extrémités.
                  child: Align(
                    alignment: Alignment(tag.fraction * 2 - 1, 0),
                    child: _TimeTag(text: _fmt(tag.time), color: tag.color),
                  ),
                ),
        ),
        // Inerte tant que le son charge : la piste est déjà là (même hauteur,
        // aucun saut), avec l'enveloppe du son précédent.
        IgnorePointer(ignoring: _loading, child: _buildTrack(scheme)),
        const SizedBox(height: 8),
        _buildControls(context),
      ],
    );
  }

  /// Position (0→1) animée vers [target] : d'un son à l'autre elle glisse, un
  /// geste en cours ([live]) la suit sans retard.
  Widget _glide({
    required double target,
    required bool live,
    required Widget Function(BuildContext context, double value) builder,
  }) => TweenAnimationBuilder<double>(
    tween: Tween(end: target),
    duration: _glideFor(live: live),
    curve: Curves.easeOutCubic,
    builder: (context, value, _) => builder(context, value),
  );

  /// Piste interactive : waveform, poignée, tête de lecture, clavier.
  Widget _buildTrack(ColorScheme scheme) {
    // Pendant le chargement, repères au point d'entrée du son précédent : au
    // chargement ils glissent de là jusqu'à leur place.
    final previous = widget.memory?.offsetFraction ?? 0.0;
    final offsetTarget = _loading ? previous : _fractionOf(_offsetMs);
    final playheadTarget = _loading
        ? previous
        : _fractionOf(_playhead.inMilliseconds);
    final tag = _tagData(scheme);
    // Trait fantôme : seulement quand le pointeur ne tient aucun élément.
    final ghostActive =
        _pointerFraction != null &&
        _hover == null &&
        !_isDragging &&
        !_isScrubbingPlayhead;

    return Semantics(
      label: 'Point d\'entrée',
      value: _fmt(_offset),
      increasedValue: _fmt(_offset + _nudgeStep),
      decreasedValue: _fmt(_offset - _nudgeStep),
      onIncrease: () => _nudge(_nudgeStep.inMilliseconds),
      onDecrease: () => _nudge(-_nudgeStep.inMilliseconds),
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            double fractionAt(double dx) => _fractionAtDx(dx, width);

            void seekTo(double dx) {
              _setOffsetMs((fractionAt(dx) * _duration.inMilliseconds).round());
            }

            void dragTo(double dx) => _isScrubbingPlayhead
                ? _scrubPlayheadTo(fractionAt(dx))
                : seekTo(dx);

            final cursor = _waveformCursor();

            return AnnotatedRegion<MouseCursor>(
              value: cursor,
              child: MouseRegion(
                cursor: cursor,
                onHover: (event) => _updateHover(event.localPosition, width),
                onExit: (_) {
                  if (_activePointer != null) return;
                  if (_hover != null || _pointerFraction != null) {
                    setState(() {
                      _hover = null;
                      _pointerFraction = null;
                    });
                  }
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) {
                    _focusNode.requestFocus();
                    final scrub =
                        _grabTarget(event.localPosition, width) ==
                        _Grab.playhead;
                    setState(() {
                      _activePointer = event.pointer;
                      _isScrubbingPlayhead = scrub;
                      _isDragging = !scrub;
                    });
                    dragTo(event.localPosition.dx);
                  },
                  onPointerMove: (event) {
                    if (_activePointer != event.pointer) return;
                    _dragMoved = true;
                    dragTo(event.localPosition.dx);
                  },
                  onPointerUp: (event) {
                    if (_activePointer != event.pointer) return;
                    if (_isScrubbingPlayhead) _commitPlayheadSeek();
                    _endDrag();
                  },
                  onPointerCancel: (event) {
                    if (_activePointer != event.pointer) return;
                    _endDrag();
                  },
                  // Sans son précédent, poignée, tête et couleur apparaissent
                  // une fois le son chargé (`settled`). Avec, tout reste tel
                  // quel (inerte) puis se déplace vers le nouveau son.
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: _loading && !_hasPrevious ? 0.0 : 1.0),
                    duration: _reduceMotion ? Duration.zero : _settleDuration,
                    builder: (context, settled, _) => _glide(
                      target: offsetTarget,
                      live: _dragMoved && _isDragging,
                      builder: (context, offsetFraction) => _glide(
                        target: playheadTarget,
                        // En lecture la tête suit l'audio image par image ;
                        // glisser la retarderait.
                        live:
                            _isPreviewing ||
                            (_dragMoved && _isScrubbingPlayhead),
                        builder: (context, playheadFraction) => SizedBox(
                          height: _waveHeight,
                          child: CustomPaint(
                            painter: _OffsetWaveformPainter(
                              bars: _bars,
                              fromBars: _morphFrom,
                              volume: widget.displayVolume,
                              offsetFraction: offsetFraction,
                              playheadFraction: playheadFraction,
                              skippedColor: scheme.onSurfaceVariant.withValues(
                                alpha: 0.28,
                              ),
                              keptColor: scheme.primary,
                              handleColor: scheme.primary,
                              playheadColor: scheme.tertiary,
                              handleHovered:
                                  _hover == _Grab.handle || _isDragging,
                              handleHitHalfWidth: _handleHitHalfWidth(),
                              ghostFraction: ghostActive
                                  ? _pointerFraction
                                  : null,
                              ghostColor: tag?.color ?? scheme.primary,
                              settled: settled,
                              reveal: _reveal,
                              pulse: _pulse,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Barre ▶ / ±0,1 s / position. Affichée dès le chargement (boutons
  /// désactivés, durée inconnue) pour éviter qu'elle n'apparaisse d'un coup.
  Widget _buildControls(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final ready = !_loading;
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: ready ? _togglePreview : null,
          icon: TransportIcon(
            _isPreviewing ? TransportGlyph.pause : TransportGlyph.play,
          ),
          tooltip: _isPreviewing ? 'Pause' : 'Aperçu depuis le point',
        ),
        const SizedBox(width: 4),
        _NudgeButton(
          glyph: TransportGlyph.previous,
          onPressed: ready && _offsetMs > 0
              ? () => _nudge(-_nudgeStep.inMilliseconds)
              : null,
          tooltip: '-0,1 s',
        ),
        _NudgeButton(
          glyph: TransportGlyph.next,
          onPressed: ready && _offsetMs < _duration.inMilliseconds
              ? () => _nudge(_nudgeStep.inMilliseconds)
              : null,
          tooltip: '+0,1 s',
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: 'Fixer le point d\'entrée à la position de lecture (Entrée)',
          child: TextButton(
            onPressed: ready && _canPlaceHere ? _placeAtPlayhead : null,
            child: const Text('Placer ici'),
          ),
        ),
        const SizedBox(width: 8),
        // Couleurs = celles de la waveform : point d'entrée (accent) et, en
        // aperçu, tête de lecture. Réduit plutôt que de déborder si l'espace manque.
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(
                TextSpan(
                  children: [
                    if (_isPreviewing)
                      TextSpan(
                        text: '${_fmt(_playhead)}  ',
                        style: TextStyle(color: scheme.tertiary),
                      ),
                    TextSpan(
                      text: _fmt(_offset),
                      style: TextStyle(color: scheme.primary),
                    ),
                    TextSpan(
                      text: ' / ${ready ? _fmt(_duration) : '–:––.–'}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                style: AppFonts.monoStyle(textTheme.labelLarge!),
                maxLines: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Ce que le repère de temps montre : où (0→1), quand, et de quelle couleur.
class _TimeTagData {
  final double fraction;
  final Duration time;
  final Color color;

  const _TimeTagData(this.fraction, this.time, this.color);
}

/// Pastille de temps au-dessus de la waveform (même pattern que les pastilles
/// bordées du thème : fond `surfaceContainer`, hairline, `AppRadius.sm`).
class _TimeTag extends StatelessWidget {
  final String text;
  final Color color;

  const _TimeTag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: AppRadius.radiusSm,
        border: Border.fromBorderSide(AppElevation.border(scheme)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          text,
          style: AppFonts.monoStyle(
            Theme.of(context).textTheme.labelSmall!.copyWith(color: color),
          ),
        ),
      ),
    );
  }
}

class _NudgeButton extends StatelessWidget {
  final TransportGlyph glyph;
  final VoidCallback? onPressed;
  final String tooltip;

  const _NudgeButton({
    required this.glyph,
    required this.onPressed,
    required this.tooltip,
  });

  /// Même glyphe de transport plein que ▶/⏸, mais sans fond : ▶/⏸ reste le
  /// bouton principal de la barre, les ±0,1 s sont des réglages secondaires.
  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: TransportIcon(glyph),
      tooltip: tooltip,
    );
  }
}

/// Waveform de l'éditeur : enveloppe continue remplie (miroir autour de l'axe),
/// grisée avant le point d'entrée, colorée après ; trait vertical de poignée au
/// point d'entrée ; tête de lecture toujours affichée. Rendu par
/// enveloppe (plus précis que l'ancien « bâton »), rééchantillonné par pic pour
/// préserver les crêtes.
class _OffsetWaveformPainter extends CustomPainter {
  final List<double> bars;

  /// Échelle de l'enveloppe (volume montré), écoutée comme `reveal` et `pulse`.
  final ValueListenable<double> volume;
  final double offsetFraction;
  final double playheadFraction;
  final Color skippedColor;
  final Color keptColor;
  final Color handleColor;
  final Color playheadColor;
  final bool handleHovered;
  final double handleHitHalfWidth;

  /// Trait fantôme sous le pointeur (là où un clic poserait la tête ou le point
  /// d'entrée), ou `null`.
  final double? ghostFraction;
  final Color ghostColor;

  /// Enveloppe d'où part la transformation (vide = depuis l'axe médian), et
  /// apparition des repères / de la couleur (0 = son en chargement → 1).
  final List<double> fromBars;
  final double settled;

  /// Transformation `fromBars` → `bars` (0 → 1) et pulsation de la ligne
  /// médiane tant que l'enveloppe est attendue. Écoutées directement :
  /// l'animation ne reconstruit pas le widget.
  final Animation<double> reveal;
  final Animation<double> pulse;

  _OffsetWaveformPainter({
    required this.bars,
    required this.fromBars,
    required this.settled,
    required this.volume,
    required this.offsetFraction,
    required this.playheadFraction,
    required this.skippedColor,
    required this.keptColor,
    required this.handleColor,
    required this.playheadColor,
    this.handleHovered = false,
    this.handleHitHalfWidth = _kHandleHitHalfWidthDesktop,
    this.ghostFraction,
    required this.ghostColor,
    required this.reveal,
    required this.pulse,
  }) : super(repaint: Listenable.merge([reveal, pulse, volume]));

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final track = size.width - 2 * _kTrackInset;
    if (track <= 0) return;
    // `CustomPaint` ne rogne pas : seul le halo de survol (fond, large) peut
    // approcher le bord, on le coupe plutôt que de le laisser déborder.
    canvas.clipRect(Offset.zero & size);
    final centerY = size.height / 2;
    // Piste (waveform) en coordonnées locales, décalée de la marge.
    final trackOffsetX = track * offsetFraction;
    final offsetX = _kTrackInset + trackOffsetX;
    final trackSize = Size(track, size.height);
    canvas.save();
    canvas.translate(_kTrackInset, 0);

    // Avant que le son soit chargé, la partie « gardée » est grise ; elle
    // prend sa couleur en même temps que la poignée apparaît.
    final kept = Color.lerp(skippedColor, keptColor, settled) ?? keptColor;
    final progress = reveal.value;
    // Une enveloppe qui se résorbe vers rien (son sans waveform) reste dessinée
    // le temps de la transformation, puis laisse place à la ligne médiane.
    final fading = fromBars.isNotEmpty && progress < 1;
    if (bars.isNotEmpty || fading) {
      final count = WaveformEnvelope.pointCountFor(track);
      if (count > 0) {
        // L'enveloppe stockée est normalisée au pic : on la met à l'échelle du
        // volume pour montrer le niveau réellement restitué.
        final to = bars.isEmpty ? null : WaveformEnvelope.resample(bars, count);
        final from = fromBars.isEmpty
            ? null
            : WaveformEnvelope.resample(fromBars, count);
        // Transformation en balayage gauche → droite : chaque point démarre un
        // peu après son voisin de gauche (à 1, tout est à son niveau final ; à
        // 0, c'est l'enveloppe précédente, ou le plancher d'une fine bande
        // médiane s'il n'y en a pas).
        final amps = [
          for (var i = 0; i < count; i++)
            (from?[i] ?? 0.0) +
                ((to?[i] ?? 0.0) - (from?[i] ?? 0.0)) *
                    Curves.easeOutCubic.transform(
                      (progress * _kRevealSweep -
                              i / count * (_kRevealSweep - 1))
                          .clamp(0.0, 1.0),
                    ),
        ].map((amp) => amp * volume.value).toList();
        final path = WaveformEnvelope.buildPath(amps, trackSize);
        // Même enveloppe remplie deux fois, découpée au point d'entrée : grisée
        // avant (sautée à la lecture), colorée après.
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(0, 0, trackOffsetX, size.height));
        canvas.drawPath(path, Paint()..color = skippedColor);
        canvas.restore();

        canvas.save();
        canvas.clipRect(Rect.fromLTRB(trackOffsetX, 0, track, size.height));
        canvas.drawPath(path, Paint()..color = kept);
        canvas.restore();
      }
    } else {
      // Pas de waveform : ligne médiane, grisée avant le point d'entrée.
      // `pulse` vaut 0 hors attente : la ligne garde alors son opacité pleine.
      final dim = 1 - 0.5 * pulse.value;
      final baseline = Paint()..strokeWidth = 2;
      baseline.color = skippedColor.withValues(alpha: skippedColor.a * dim);
      canvas.drawLine(
        Offset(0, centerY),
        Offset(trackOffsetX, centerY),
        baseline,
      );
      baseline.color = kept.withValues(alpha: kept.a * dim);
      canvas.drawLine(
        Offset(trackOffsetX, centerY),
        Offset(track, centerY),
        baseline,
      );
    }
    canvas.restore();

    // Repères (fantôme, poignée, tête) : absents tant que le son charge, puis
    // fondus avec `settled`.
    if (settled <= 0) return;
    if (settled < 1) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = Color.fromRGBO(0, 0, 0, settled),
      );
    }

    // Trait fantôme sous le pointeur, sous la poignée et la tête.
    final ghost = ghostFraction;
    if (ghost != null) {
      final ghostX = _kTrackInset + track * ghost;
      canvas.drawLine(
        Offset(ghostX, 0),
        Offset(ghostX, size.height),
        Paint()
          ..color = ghostColor.withValues(alpha: 0.55)
          ..strokeWidth = 1,
      );
    }

    // Poignée du point d'entrée : trait vertical + pastille en tête.
    final handlePaint = Paint()
      ..color = handleColor
      ..strokeWidth = handleHovered ? 2.5 : 2;
    canvas.drawLine(
      Offset(offsetX, 0),
      Offset(offsetX, size.height),
      handlePaint,
    );
    final knobRadius = handleHovered ? 5.5 : 4.0;
    canvas.drawCircle(Offset(offsetX, 6), knobRadius, handlePaint);
    if (handleHovered) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(offsetX, size.height / 2),
            width: handleHitHalfWidth * 2,
            height: size.height,
          ),
          const Radius.circular(4),
        ),
        Paint()..color = handleColor.withValues(alpha: 0.12),
      );
    }

    // Tête de lecture, par-dessus la poignée : toujours visible, même
    // superposée au point d'entrée grâce à son repère triangulaire en bas
    // (la pastille de la poignée est en haut).
    final phX = _kTrackInset + track * playheadFraction;
    final playheadPaint = Paint()..color = playheadColor;
    canvas.drawLine(
      Offset(phX, 0),
      Offset(phX, size.height),
      playheadPaint..strokeWidth = 1.5,
    );
    canvas.drawPath(
      Path()
        ..moveTo(phX - 5, size.height)
        ..lineTo(phX + 5, size.height)
        ..lineTo(phX, size.height - 8)
        ..close(),
      playheadPaint,
    );
    if (settled < 1) canvas.restore();
  }

  @override
  bool shouldRepaint(_OffsetWaveformPainter old) =>
      old.offsetFraction != offsetFraction ||
      old.playheadFraction != playheadFraction ||
      old.bars != bars ||
      old.fromBars != fromBars ||
      old.settled != settled ||
      old.volume != volume ||
      old.keptColor != keptColor ||
      old.handleHovered != handleHovered ||
      old.ghostFraction != ghostFraction ||
      old.ghostColor != ghostColor ||
      old.reveal != reveal ||
      old.pulse != pulse;
}
