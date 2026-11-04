import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../core/audio/cue_audio_service.dart';
import '../../../../core/audio/preview_playback.dart';
import '../../../../core/audio/waveform_extractor.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/skeleton.dart';
import '../../../../core/utils/layout_utils.dart';
import 'waveform_envelope.dart';

/// Zone cliquable autour de la poignée sur desktop (souris).
const _kHandleHitHalfWidthDesktop = 14.0;
const _kHandleHitHalfWidthMobile = 28.0;

/// Écart (px) sous lequel poignée et tête de lecture comptent comme superposées.
const _kOverlapPx = 8.0;

/// Marge horizontale de part et d'autre de la piste : pastille de la poignée
/// (rayon 5,5 au survol) et repère de la tête (±5) restent entiers, même au
/// tout début ou à la toute fin du son, sans dépasser du cadre de l'éditeur.
const _kTrackInset = 7.0;

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
/// Charge sa propre source audio (durée + aperçu). Si le fichier n'est pas
/// disponible localement, l'éditeur s'affiche désactivé avec un message.
class StartOffsetEditor extends StatefulWidget {
  final String filePath;
  final Uint8List? waveform;
  final int initialOffsetMs;

  /// Volume d'écoute (0.0 → 1.0) : celui du son, pour que l'audition du point
  /// d'entrée soit au niveau réel. Relu à chaque lecture.
  final double volume;

  /// Notifié à chaque changement de valeur (drag, nudge, reset).
  final ValueChanged<int> onChanged;

  /// Lance l'aperçu depuis le point d'entrée dès que la source est chargée
  /// (file de traitement : trier se fait à l'oreille, tête de lecture visible).
  /// Lu au chargement seulement ; passer à `false` ensuite coupe l'aperçu en
  /// cours.
  final bool autoPlay;

  const StartOffsetEditor({
    super.key,
    required this.filePath,
    required this.waveform,
    required this.initialOffsetMs,
    required this.volume,
    required this.onChanged,
    this.autoPlay = false,
  });

  @override
  State<StartOffsetEditor> createState() => _StartOffsetEditorState();
}

class _StartOffsetEditorState extends State<StartOffsetEditor> {
  static const _nudgeStep = Duration(milliseconds: 100);
  static const _waveHeight = 56.0;

  PreviewPlayback? _player;
  bool _loading = true;
  bool _loadFailed = false;
  Duration _duration = Duration.zero;

  late int _offsetMs;
  bool _isPreviewing = false;
  bool _isDragging = false;

  /// Un geste en cours déplace la tête de lecture (et non la poignée).
  bool _isScrubbingPlayhead = false;
  _Grab? _hover;
  int? _activePointer;
  Ticker? _ticker;

  /// Tête de lecture, toujours affichée. À l'arrêt elle marque d'où repartira
  /// ▶ : elle suit le point d'entrée tant qu'on ne l'a pas déplacée à la main.
  Duration _playhead = Duration.zero;

  @override
  void initState() {
    super.initState();
    _offsetMs = widget.initialOffsetMs;
    _load();
  }

  @override
  void didUpdateWidget(StartOffsetEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.volume != widget.volume) _player?.setVolume(widget.volume);
    if (oldWidget.autoPlay && !widget.autoPlay && _isPreviewing) {
      unawaited(_player?.stop());
    }
  }

  Future<void> _load() async {
    var loaded = false;
    try {
      final player = await CueAudioService.instance.createPreviewPlayer(
        widget.filePath,
        ephemeral: true,
      );
      if (!mounted) {
        player.dispose();
        return;
      }
      _player = player;
      _duration = player.duration;
      _offsetMs = _offsetMs.clamp(0, _duration.inMilliseconds);
      _playhead = _offset;
      player.onPlayerStateChanged.listen((playing) {
        if (!mounted) return;
        setState(() {
          _isPreviewing = playing;
          // Arrêt (manuel ou fin de piste) : la tête revient au point d'entrée.
          if (!playing) _playhead = _offset;
        });
        _syncTicker();
      });
      setState(() => _loading = false);
      loaded = true;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
    if (!loaded || !mounted || !widget.autoPlay || _duration <= Duration.zero) {
      return;
    }
    // Hors du `try` de chargement : un échec de lecture ne doit pas griser
    // l'éditeur. Silencieux — un son pas encore prêt ne doit pas noyer la file
    // sous les messages (le ▶ manuel reste disponible).
    try {
      await _togglePreview();
    } catch (_) {}
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _player?.dispose();
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
    widget.onChanged(clamped);
  }

  void _nudge(int signMs) => _setOffsetMs(_offsetMs + signMs);

  Future<void> _togglePreview() async {
    final player = _player;
    if (player == null) return;
    if (_isPreviewing) {
      await player.stop();
      return;
    }
    await player.playFromPosition(_playhead, volume: widget.volume);
  }

  void _syncTicker() {
    if (_isPreviewing) {
      _ticker ??= Ticker((_) {
        if (!mounted || _isScrubbingPlayhead) return;
        setState(() => _playhead = _player?.position ?? _playhead);
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

  void _updateHover(Offset p, double width) {
    final hover = _hitAt(p, width);
    if (hover != _hover) setState(() => _hover = hover);
  }

  void _endDrag() {
    if (!_isDragging && _activePointer == null) return;
    setState(() {
      _isDragging = false;
      _isScrubbingPlayhead = false;
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
    final player = _player;
    if (player == null || !_isPreviewing) return;
    unawaited(player.playFromPosition(_playhead, volume: widget.volume));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_loading) {
      // Placeholder à la forme de la waveform pendant l'extraction ; la barre
      // de contrôles est déjà là (désactivée) pour que rien ne « saute » à
      // l'arrivée de la source.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: _kTrackInset),
            child: Skeleton(
              child: SkeletonBox(height: _waveHeight, intensity: 0.85),
            ),
          ),
          const SizedBox(height: 8),
          _buildControls(context),
        ],
      );
    }

    if (_loadFailed || _duration <= Duration.zero) {
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
            Icon(
              Icons.info_outline_rounded,
              size: 18,
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

    final bars = decodeWaveformBars(widget.waveform);
    final fraction = _fractionOf(_offsetMs);
    final playheadFraction = _fractionOf(_playhead.inMilliseconds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            double fractionAt(double dx) {
              final track = width - 2 * _kTrackInset;
              return track <= 0
                  ? 0.0
                  : ((dx - _kTrackInset) / track).clamp(0.0, 1.0);
            }

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
                  if (_hover != null) setState(() => _hover = null);
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) {
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
                  child: SizedBox(
                    height: _waveHeight,
                    child: CustomPaint(
                      painter: _OffsetWaveformPainter(
                        bars: bars,
                        volume: widget.volume,
                        offsetFraction: fraction,
                        playheadFraction: playheadFraction,
                        skippedColor: scheme.onSurfaceVariant.withValues(
                          alpha: 0.28,
                        ),
                        keptColor: scheme.primary,
                        handleColor: scheme.primary,
                        playheadColor: scheme.tertiary,
                        handleHovered: _hover == _Grab.handle || _isDragging,
                        handleHitHalfWidth: _handleHitHalfWidth(),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        _buildControls(context),
      ],
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
          icon: Icon(
            _isPreviewing ? Icons.stop_rounded : Icons.play_arrow_rounded,
          ),
          tooltip: _isPreviewing ? 'Arrêter' : 'Aperçu depuis le point',
        ),
        const SizedBox(width: 4),
        _NudgeButton(
          icon: Icons.fast_rewind_rounded,
          onPressed: ready && _offsetMs > 0
              ? () => _nudge(-_nudgeStep.inMilliseconds)
              : null,
          tooltip: '-0,1 s',
        ),
        _NudgeButton(
          icon: Icons.fast_forward_rounded,
          onPressed: ready && _offsetMs < _duration.inMilliseconds
              ? () => _nudge(_nudgeStep.inMilliseconds)
              : null,
          tooltip: '+0,1 s',
        ),
        const Spacer(),
        Text(
          '${_fmt(_offset)} / ${ready ? _fmt(_duration) : '–:––.–'}',
          style: AppFonts.monoStyle(
            textTheme.labelLarge!.copyWith(color: scheme.onSurface),
          ),
        ),
      ],
    );
  }
}

class _NudgeButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  const _NudgeButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      visualDensity: VisualDensity.compact,
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
  final double volume;
  final double offsetFraction;
  final double playheadFraction;
  final Color skippedColor;
  final Color keptColor;
  final Color handleColor;
  final Color playheadColor;
  final bool handleHovered;
  final double handleHitHalfWidth;

  _OffsetWaveformPainter({
    required this.bars,
    required this.volume,
    required this.offsetFraction,
    required this.playheadFraction,
    required this.skippedColor,
    required this.keptColor,
    required this.handleColor,
    required this.playheadColor,
    this.handleHovered = false,
    this.handleHitHalfWidth = _kHandleHitHalfWidthDesktop,
  });

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

    if (bars.isNotEmpty) {
      final count = WaveformEnvelope.pointCountFor(track);
      if (count > 0) {
        // L'enveloppe stockée est normalisée au pic : on la met à l'échelle du
        // volume pour montrer le niveau réellement restitué.
        final amps = [
          for (final amp in WaveformEnvelope.resample(bars, count))
            amp * volume,
        ];
        final path = WaveformEnvelope.buildPath(amps, trackSize);
        // Même enveloppe remplie deux fois, découpée au point d'entrée : grisée
        // avant (sautée à la lecture), colorée après.
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(0, 0, trackOffsetX, size.height));
        canvas.drawPath(path, Paint()..color = skippedColor);
        canvas.restore();

        canvas.save();
        canvas.clipRect(Rect.fromLTRB(trackOffsetX, 0, track, size.height));
        canvas.drawPath(path, Paint()..color = keptColor);
        canvas.restore();
      }
    } else {
      // Pas de waveform : ligne médiane, grisée avant le point d'entrée.
      final baseline = Paint()..strokeWidth = 2;
      baseline.color = skippedColor;
      canvas.drawLine(
        Offset(0, centerY),
        Offset(trackOffsetX, centerY),
        baseline,
      );
      baseline.color = keptColor;
      canvas.drawLine(
        Offset(trackOffsetX, centerY),
        Offset(track, centerY),
        baseline,
      );
    }
    canvas.restore();

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
  }

  @override
  bool shouldRepaint(_OffsetWaveformPainter old) =>
      old.offsetFraction != offsetFraction ||
      old.playheadFraction != playheadFraction ||
      old.bars != bars ||
      old.volume != volume ||
      old.keptColor != keptColor ||
      old.handleHovered != handleHovered;
}
