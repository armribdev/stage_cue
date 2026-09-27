part of 'music_preview_panel.dart';

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

/// Position/durée du morceau à l'antenne en une ligne compacte
/// ("01:12 / 03:52", police technique) — mise à jour en direct pendant la
/// lecture. Même logique de ticker que [_RegieProgressBar], en plus simple
/// (pas de waveform/seek) : la barre réduite n'affiche qu'un repère temporel.
class _CompactNowPlayingTime extends StatefulWidget {
  final PadItem padItem;
  final bool isPlaying;
  final Color color;

  const _CompactNowPlayingTime({
    required this.padItem,
    required this.isPlaying,
    required this.color,
  });

  @override
  State<_CompactNowPlayingTime> createState() =>
      _CompactNowPlayingTimeState();
}

class _CompactNowPlayingTimeState extends State<_CompactNowPlayingTime>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  bool get _isLive => widget.isPlaying && widget.padItem.isPlaying;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    });
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _CompactNowPlayingTime oldWidget) {
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

  String _format(Duration d) {
    final totalSeconds = d.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.padItem.progressPlayer;
    final duration = player?.duration ?? Duration.zero;
    final position = _isLive && widget.padItem.currentPlayer != null
        ? widget.padItem.currentPlayer!.position
        : widget.padItem.pausedPlaybackPosition ?? Duration.zero;

    return Text(
      '${_format(position)} / ${_format(duration)}',
      style: AppFonts.monoStyle(TextStyle(fontSize: 11, color: widget.color)),
    );
  }
}

class _RegieProgressBar extends StatefulWidget {
  final PadItem? padItem;
  final bool isPlaying;
  final bool showTimes;
  final double height;

  /// Hauteur de la waveform quand le son courant en possède une ; à défaut on
  /// retombe sur la barre linéaire d'épaisseur [height].
  final double waveformHeight;

  /// Repositionne la lecture (scrub) — actif uniquement quand le pad est en
  /// pause et qu'une waveform est affichée. `null` = pas de seek.
  final ValueChanged<Duration>? onSeek;

  const _RegieProgressBar({
    required this.padItem,
    this.isPlaying = false,
    this.showTimes = false,
    this.onSeek,
  }) : height = 4,
       waveformHeight = 34;

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

  /// Son actuellement à l'antenne (ou en pause), pour résoudre sa waveform.
  Sound? get _currentSound {
    final padItem = widget.padItem;
    if (padItem == null || padItem.pad.sounds.isEmpty) return null;
    final idx = padItem.currentSoundIndex ?? padItem.pausedPlayerIndex ?? 0;
    if (idx < 0 || idx >= padItem.pad.sounds.length) {
      return padItem.pad.sounds.first;
    }
    return padItem.pad.sounds[idx];
  }

  /// Traduit une abscisse tactile [dx] (sur une largeur [width]) en position de
  /// lecture et la transmet via [widget.onSeek].
  void _handleSeek(double dx, double width, Duration duration) {
    if (width <= 0 || duration <= Duration.zero) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    widget.onSeek?.call(duration * fraction);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playback = _playbackState();
    final bars = _hasTrack
        ? decodeWaveformBars(_currentSound?.waveform)
        : const <double>[];

    final Widget progressWidget;
    if (bars.isNotEmpty) {
      final Widget waveform = _WaveformProgress(
        bars: bars,
        progress: _hasTrack ? playback.value : 0,
        height: widget.waveformHeight,
        playedColor: scheme.primary,
        remainingColor: scheme.outlineVariant.withValues(alpha: 0.55),
      );

      // Scrub tactile — uniquement quand la régie est en pause : on repère une
      // nouvelle position de reprise sans relancer la lecture.
      final canSeek =
          widget.onSeek != null && (widget.padItem?.isPaused ?? false);
      if (canSeek && playback.duration > Duration.zero) {
        progressWidget = LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            void seekTo(double dx) =>
                _handleSeek(dx, width, playback.duration);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => seekTo(d.localPosition.dx),
              onHorizontalDragStart: (d) => seekTo(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => seekTo(d.localPosition.dx),
              child: waveform,
            );
          },
        );
      } else {
        progressWidget = waveform;
      }
    } else {
      progressWidget = ClipRRect(
        borderRadius: BorderRadius.circular(widget.height),
        child: LinearProgressIndicator(
          value: _hasTrack ? playback.value : 0,
          minHeight: widget.height,
          backgroundColor: scheme.outlineVariant.withValues(alpha: 0.35),
          valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
        ),
      );
    }

    return Column(
      children: [
        progressWidget,
        if (widget.showTimes) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(playback.position),
                style: AppFonts.monoStyle(
                  TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ),
              Text(
                _formatDuration(playback.duration),
                style: AppFonts.monoStyle(
                  TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
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

/// Waveform de régie : enveloppe continue remplie (miroir autour de l'axe),
/// tracée à la densité de pixels disponible et hugant les crêtes point par
/// point — plus précise que l'ancien rendu « bâton ». L'enveloppe stockée est
/// rééchantillonnée par PIC (max) pour ne pas écraser les crêtes. La portion
/// jouée (gauche) est colorée [playedColor].
class _WaveformProgress extends StatelessWidget {
  final List<double> bars;
  final double progress;
  final double height;
  final Color playedColor;
  final Color remainingColor;

  const _WaveformProgress({
    required this.bars,
    required this.progress,
    required this.height,
    required this.playedColor,
    required this.remainingColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final count = WaveformEnvelope.pointCountFor(width);
          if (count <= 0 || bars.isEmpty) {
            return const SizedBox.shrink();
          }
          final amps = WaveformEnvelope.resample(bars, count);
          return CustomPaint(
            size: Size(width, height),
            painter: _WaveformPainter(
              amps: amps,
              progress: progress.clamp(0.0, 1.0),
              playedColor: playedColor,
              remainingColor: remainingColor,
            ),
          );
        },
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> amps;
  final double progress;
  final Color playedColor;
  final Color remainingColor;

  _WaveformPainter({
    required this.amps,
    required this.progress,
    required this.playedColor,
    required this.remainingColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (amps.isEmpty || size.width <= 0) return;

    final path = WaveformEnvelope.buildPath(amps, size);
    final playedX = size.width * progress;

    // Même enveloppe remplie deux fois, découpée au point de lecture : jouée à
    // gauche, restante à droite.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, playedX, size.height));
    canvas.drawPath(path, Paint()..color = playedColor);
    canvas.restore();

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(playedX, 0, size.width, size.height));
    canvas.drawPath(path, Paint()..color = remainingColor);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.amps != amps ||
      old.playedColor != playedColor ||
      old.remainingColor != remainingColor;
}
