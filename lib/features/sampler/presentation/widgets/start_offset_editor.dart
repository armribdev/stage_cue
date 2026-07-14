import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../core/audio/audio_player_service.dart';
import '../../../../core/audio/waveform_extractor.dart';
import '../../../../core/theme/skeleton.dart';
import '../../../../core/utils/layout_utils.dart';

/// Zone cliquable autour de la poignée sur desktop (souris).
const _kHandleHitHalfWidthDesktop = 14.0;
const _kHandleHitHalfWidthMobile = 28.0;

/// Éditeur du point d'entrée d'un son : waveform scrubbable avec une poignée
/// draggable, aperçu audio depuis le point choisi et réglage fin (±0,1 s).
/// La zone avant le point d'entrée est grisée pour montrer d'un coup d'œil ce
/// qui sera sauté à la lecture.
///
/// Charge sa propre source audio (durée + aperçu). Si le fichier n'est pas
/// disponible localement, l'éditeur s'affiche désactivé avec un message.
class StartOffsetEditor extends StatefulWidget {
  final String filePath;
  final Uint8List? waveform;
  final int initialOffsetMs;

  /// Notifié à chaque changement de valeur (drag, nudge, reset).
  final ValueChanged<int> onChanged;

  const StartOffsetEditor({
    super.key,
    required this.filePath,
    required this.waveform,
    required this.initialOffsetMs,
    required this.onChanged,
  });

  @override
  State<StartOffsetEditor> createState() => _StartOffsetEditorState();
}

class _StartOffsetEditorState extends State<StartOffsetEditor> {
  static const _nudgeStep = Duration(milliseconds: 100);
  static const _waveHeight = 56.0;

  AudioPlayerService? _player;
  bool _loading = true;
  bool _loadFailed = false;
  Duration _duration = Duration.zero;

  late int _offsetMs;
  bool _isPreviewing = false;
  bool _isDragging = false;
  bool _isOverHandle = false;
  int? _activePointer;
  Ticker? _ticker;
  Duration _playhead = Duration.zero;

  @override
  void initState() {
    super.initState();
    _offsetMs = widget.initialOffsetMs;
    _load();
  }

  Future<void> _load() async {
    try {
      final player = await AudioPlayerService.createEphemeral(widget.filePath);
      if (!mounted) {
        player.dispose();
        return;
      }
      _player = player;
      _duration = player.duration;
      _offsetMs = _offsetMs.clamp(0, _duration.inMilliseconds);
      player.onPlayerStateChanged.listen((playing) {
        if (!mounted) return;
        setState(() => _isPreviewing = playing);
        _syncTicker();
      });
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
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
    setState(() => _offsetMs = clamped);
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
    _playhead = _offset;
    await player.playFromPosition(_offset);
  }

  void _syncTicker() {
    if (_isPreviewing) {
      _ticker ??= Ticker((_) {
        if (!mounted) return;
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

  double _handleHitHalfWidth() =>
      isNativeDesktopPlatform() ? _kHandleHitHalfWidthDesktop : _kHandleHitHalfWidthMobile;

  bool _isNearHandle(double dx, double width, double fraction) {
    if (width <= 0) return false;
    final handleX = width * fraction;
    return (dx - handleX).abs() <= _handleHitHalfWidth();
  }

  SystemMouseCursor _waveformCursor() {
    if (isNativeDesktopPlatform() || _isDragging || _isOverHandle) {
      return SystemMouseCursors.resizeLeftRight;
    }
    return SystemMouseCursors.click;
  }

  void _updateHandleHover(double dx, double width, double fraction) {
    final overHandle = _isNearHandle(dx, width, fraction);
    if (overHandle != _isOverHandle) {
      setState(() => _isOverHandle = overHandle);
    }
  }

  void _endDrag() {
    if (!_isDragging && _activePointer == null) return;
    setState(() {
      _isDragging = false;
      _activePointer = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_loading) {
      // Placeholder à la forme de la waveform pendant l'extraction.
      return const Skeleton(
        child: SkeletonBox(height: _waveHeight, intensity: 0.85),
      );
    }

    if (_loadFailed || _duration <= Duration.zero) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded,
                size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Téléchargez le son pour régler son point d\'entrée.',
                style: textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    final bars = decodeWaveformBars(widget.waveform);
    final fraction = _duration.inMilliseconds == 0
        ? 0.0
        : (_offsetMs / _duration.inMilliseconds).clamp(0.0, 1.0);
    final playheadFraction = _duration.inMilliseconds == 0
        ? 0.0
        : (_playhead.inMilliseconds / _duration.inMilliseconds)
            .clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            double offsetFraction() => _duration.inMilliseconds == 0
                ? 0.0
                : (_offsetMs / _duration.inMilliseconds).clamp(0.0, 1.0);

            void seekTo(double dx) {
              final f = (dx / width).clamp(0.0, 1.0);
              _setOffsetMs((f * _duration.inMilliseconds).round());
            }

            final cursor = _waveformCursor();

            return AnnotatedRegion<MouseCursor>(
              value: cursor,
              child: MouseRegion(
                cursor: cursor,
                onHover: (event) => _updateHandleHover(
                  event.localPosition.dx,
                  width,
                  offsetFraction(),
                ),
                onExit: (_) {
                  if (_isDragging) return;
                  if (_isOverHandle) setState(() => _isOverHandle = false);
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) {
                    setState(() {
                      _activePointer = event.pointer;
                      _isDragging = true;
                    });
                    seekTo(event.localPosition.dx);
                  },
                  onPointerMove: (event) {
                    if (_activePointer != event.pointer) return;
                    seekTo(event.localPosition.dx);
                    _updateHandleHover(
                      event.localPosition.dx,
                      width,
                      offsetFraction(),
                    );
                  },
                  onPointerUp: (event) {
                    if (_activePointer != event.pointer) return;
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
                        offsetFraction: fraction,
                        playheadFraction:
                            _isPreviewing ? playheadFraction : null,
                        skippedColor:
                            scheme.onSurfaceVariant.withValues(alpha: 0.28),
                        keptColor: scheme.primary,
                        handleColor: scheme.primary,
                        playheadColor: scheme.tertiary,
                        handleHovered: _isOverHandle || _isDragging,
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
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: _togglePreview,
              icon: Icon(
                _isPreviewing
                    ? Icons.stop_rounded
                    : Icons.play_arrow_rounded,
              ),
              tooltip: _isPreviewing ? 'Arrêter' : 'Aperçu depuis le point',
            ),
            const SizedBox(width: 4),
            _NudgeButton(
              icon: Icons.fast_rewind_rounded,
              onPressed:
                  _offsetMs > 0 ? () => _nudge(-_nudgeStep.inMilliseconds) : null,
              tooltip: '-0,1 s',
            ),
            _NudgeButton(
              icon: Icons.fast_forward_rounded,
              onPressed: _offsetMs < _duration.inMilliseconds
                  ? () => _nudge(_nudgeStep.inMilliseconds)
                  : null,
              tooltip: '+0,1 s',
            ),
            const Spacer(),
            Text(
              '${_fmt(_offset)} / ${_fmt(_duration)}',
              style: textTheme.labelLarge?.copyWith(
                color: scheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
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

/// Waveform de l'éditeur : barres grisées avant le point d'entrée, colorées
/// après ; trait vertical de poignée au point d'entrée ; tête de lecture
/// optionnelle pendant l'aperçu. Barres de largeur fixe rééchantillonnées par
/// pic pour préserver les crêtes.
class _OffsetWaveformPainter extends CustomPainter {
  final List<double> bars;
  final double offsetFraction;
  final double? playheadFraction;
  final Color skippedColor;
  final Color keptColor;
  final Color handleColor;
  final Color playheadColor;
  final bool handleHovered;
  final double handleHitHalfWidth;

  static const double _barWidth = 2.0;
  static const double _barGap = 2.0;
  static const double _slot = _barWidth + _barGap;

  _OffsetWaveformPainter({
    required this.bars,
    required this.offsetFraction,
    required this.playheadFraction,
    required this.skippedColor,
    required this.keptColor,
    required this.handleColor,
    required this.playheadColor,
    this.handleHovered = false,
    this.handleHitHalfWidth = _kHandleHitHalfWidthDesktop,
  });

  static List<double> _resamplePeaks(List<double> src, int target) {
    if (src.isEmpty || target <= 0) return const [];
    if (target >= src.length) {
      return [
        for (var i = 0; i < target; i++)
          src[((i * src.length) ~/ target).clamp(0, src.length - 1)],
      ];
    }
    final out = List<double>.filled(target, 0);
    for (var t = 0; t < target; t++) {
      final start = (t * src.length) ~/ target;
      var end = ((t + 1) * src.length) ~/ target;
      if (end <= start) end = start + 1;
      if (end > src.length) end = src.length;
      var peak = 0.0;
      for (var j = start; j < end; j++) {
        if (src[j] > peak) peak = src[j];
      }
      out[t] = peak;
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final centerY = size.height / 2;
    final maxHalf = size.height / 2;
    final offsetX = size.width * offsetFraction;

    if (bars.isNotEmpty) {
      final count = (size.width / _slot).floor();
      if (count > 0) {
        final peaks = _resamplePeaks(bars, count);
        final marginX = (size.width - count * _slot) / 2;
        final radius = Radius.circular(_barWidth / 2);
        final skippedPaint = Paint()..color = skippedColor;
        final keptPaint = Paint()..color = keptColor;
        for (var i = 0; i < peaks.length; i++) {
          final x = (marginX + i * _slot).roundToDouble();
          final half = (peaks[i] * maxHalf).clamp(1.0, maxHalf);
          final rect = RRect.fromRectAndRadius(
            Rect.fromLTRB(x, centerY - half, x + _barWidth, centerY + half),
            radius,
          );
          canvas.drawRRect(
            rect,
            x + _barWidth / 2 < offsetX ? skippedPaint : keptPaint,
          );
        }
      }
    } else {
      // Pas de waveform : ligne médiane, grisée avant le point d'entrée.
      final baseline = Paint()..strokeWidth = 2;
      baseline.color = skippedColor;
      canvas.drawLine(Offset(0, centerY), Offset(offsetX, centerY), baseline);
      baseline.color = keptColor;
      canvas.drawLine(
          Offset(offsetX, centerY), Offset(size.width, centerY), baseline);
    }

    // Tête de lecture (aperçu).
    final ph = playheadFraction;
    if (ph != null) {
      final phX = size.width * ph;
      canvas.drawLine(
        Offset(phX, 0),
        Offset(phX, size.height),
        Paint()
          ..color = playheadColor
          ..strokeWidth = 1.5,
      );
    }

    // Poignée du point d'entrée : trait vertical + pastille en tête.
    final handlePaint = Paint()
      ..color = handleColor
      ..strokeWidth = handleHovered ? 2.5 : 2;
    canvas.drawLine(
        Offset(offsetX, 0), Offset(offsetX, size.height), handlePaint);
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
  }

  @override
  bool shouldRepaint(_OffsetWaveformPainter old) =>
      old.offsetFraction != offsetFraction ||
      old.playheadFraction != playheadFraction ||
      old.bars != bars ||
      old.keptColor != keptColor ||
      old.handleHovered != handleHovered;
}
