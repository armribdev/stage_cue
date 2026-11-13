import 'package:flutter/material.dart';

import '../providers/sampler_provider.dart';

/// Barre de progression de lecture d'un pad musique, synchronisée sur la
/// position **réelle** du lecteur. Contrairement à une simple animation 0→1
/// relancée à chaque `play`, elle se ré-aligne à chaque rebuild sur
/// `player.position` (ou sur la position mémorisée en pause) : une reprise après
/// pause repart de l'endroit où le son a été suspendu, jamais de zéro.
class MusicProgressBar extends StatefulWidget {
  final PadItem padItem;
  final Color color;

  const MusicProgressBar({
    super.key,
    required this.padItem,
    required this.color,
  });

  @override
  State<MusicProgressBar> createState() => _MusicProgressBarState();
}

class _MusicProgressBarState extends State<MusicProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _syncToPlayback();
  }

  @override
  void didUpdateWidget(covariant MusicProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Le grid se reconstruit à chaque `_notify()` du notifier : on en profite
    // pour recaler la barre sur la position réelle (corrige aussi la dérive).
    _syncToPlayback();
  }

  /// Ré-aligne la barre sur l'état de lecture courant du pad :
  /// - en lecture : anime depuis la position réelle jusqu'à la fin, sur le temps
  ///   restant — l'`AnimationController` de durée = durée totale interpole
  ///   linéairement le reste depuis `value` (`forward()` prend `durée × (1 −
  ///   value)`) ;
  /// - en pause : fige à la position mémorisée d'où la reprise repartira ;
  /// - arrêté : ramène à zéro (barre masquée).
  void _syncToPlayback() {
    final pad = widget.padItem;
    final totalMs =
        (pad.progressPlayer?.duration ?? Duration.zero).inMilliseconds;

    if (pad.isPlaying && totalMs > 0) {
      final posMs = (pad.progressPlayer?.position.inMilliseconds ?? 0).clamp(
        0,
        totalMs,
      );
      _controller.duration = Duration(milliseconds: totalMs);
      _controller.value = posMs / totalMs;
      _controller.forward();
    } else if (pad.isPaused && totalMs > 0) {
      final posMs = (pad.pausedPlaybackPosition?.inMilliseconds ?? 0).clamp(
        0,
        totalMs,
      );
      _controller.stop();
      _controller.value = posMs / totalMs;
    } else {
      _controller.stop();
      _controller.value = 0.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const _barHeight = 3.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final value = _controller.value;
        // Rien à afficher tant que le pad est arrêté et la barre vide.
        if (!widget.padItem.isPlaying && value <= 0.0) {
          return const SizedBox.shrink();
        }
        return LinearProgressIndicator(
          value: value,
          backgroundColor: widget.color.withValues(alpha: 0.16),
          valueColor: AlwaysStoppedAnimation<Color>(widget.color),
          minHeight: _barHeight,
        );
      },
    );
  }
}

/// Barre de progression d'une voix polyphonique : anime 0→1 sur la durée du son
/// à partir de sa position réelle (au cas où la barre apparaît après le départ),
/// indépendamment des rebuilds du pad (chevauchements superposés).
class PolyphonicProgressBar extends StatefulWidget {
  final PadPlaybackTicket ticket;
  final Color color;

  const PolyphonicProgressBar({
    super.key,
    required this.ticket,
    required this.color,
  });

  @override
  State<PolyphonicProgressBar> createState() => _PolyphonicProgressBarState();
}

class _PolyphonicProgressBarState extends State<PolyphonicProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final total = widget.ticket.duration;
    final elapsed = DateTime.now().difference(widget.ticket.startedAt);
    final totalMs = total.inMilliseconds;
    final startValue = totalMs > 0
        ? (elapsed.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 1.0;
    _controller = AnimationController(
      vsync: this,
      duration: total > Duration.zero ? total : const Duration(milliseconds: 1),
    );
    _controller.value = startValue;
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const _barHeight = 3.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Positioned.fill(
        child: LinearProgressIndicator(
          value: _controller.value,
          backgroundColor: Colors.transparent,
          valueColor: AlwaysStoppedAnimation<Color>(widget.color),
          minHeight: _barHeight,
        ),
      ),
    );
  }
}
