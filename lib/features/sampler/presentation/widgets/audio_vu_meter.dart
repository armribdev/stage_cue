import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Vumètre du niveau de sortie master, alimenté par la visualisation SoLoud.
///
/// Affiche en temps réel le niveau du mix de sortie global (toutes voix
/// confondues) sous forme de segments type LED (vert → ambre → rouge). Compact,
/// pensé pour la barre du haut sur les layouts larges (tablette/desktop) où la
/// place ne manque pas.
///
/// La visualisation SoLoud (échantillonnage du buffer de sortie) est activée à
/// l'insertion du widget et coupée à sa disparition, pour ne pas payer le coût
/// du sampling quand le vumètre n'est pas affiché.
class AudioVuMeter extends StatefulWidget {
  const AudioVuMeter({
    super.key,
    this.segmentCount = 14,
    this.width = 104,
    this.height = 16,
  });

  /// Nombre de segments « LED » du bargraphe.
  final int segmentCount;
  final double width;
  final double height;

  @override
  State<AudioVuMeter> createState() => _AudioVuMeterState();
}

class _AudioVuMeterState extends State<AudioVuMeter>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  AudioData? _audioData;

  /// true si c'est ce widget qui a activé la visualisation — pour ne la couper
  /// qu'en la restaurant à son état d'origine.
  bool _visualizationOwned = false;

  /// Niveau lissé + maintien de crête, exposés au painter sans reconstruire
  /// l'arbre de widgets (le CustomPainter repeint seul sur notification).
  final ValueNotifier<_VuLevels> _levels = ValueNotifier<_VuLevels>(
    const _VuLevels(0, 0),
  );

  @override
  void initState() {
    super.initState();
    _startIfPossible();
  }

  void _startIfPossible() {
    // Moteur audio éventuellement non initialisé (échec d'init) → pas de vumètre.
    if (!SoLoud.instance.isInitialized) return;
    try {
      if (!SoLoud.instance.getVisualizationEnabled()) {
        SoLoud.instance.setVisualizationEnabled(true);
        _visualizationOwned = true;
      }
      _audioData = AudioData(GetSamplesKind.wave);
      _ticker = createTicker(_tick)..start();
    } catch (e) {
      debugPrint('[VU] initialisation impossible: $e');
      _audioData?.dispose();
      _audioData = null;
    }
  }

  void _tick(Duration _) {
    final data = _audioData;
    if (data == null) return;

    double peak = 0;
    try {
      data.updateSamples();
      final samples = data.getAudioData();
      // 256 floats d'onde dans [-1, 1] : la crête absolue donne le niveau.
      final n = math.min(samples.length, 256);
      for (var i = 0; i < n; i++) {
        final a = samples[i].abs();
        if (a > peak) peak = a;
      }
    } catch (e) {
      // updateSamples peut lever si le moteur se ferme — on saute la frame.
      return;
    }
    if (peak.isNaN || peak.isInfinite) peak = 0;
    peak = peak.clamp(0.0, 1.0);

    final previous = _levels.value;

    // Lissage type VU : attaque rapide, retombée lente.
    final level = peak > previous.level
        ? previous.level + (peak - previous.level) * 0.55
        : previous.level + (peak - previous.level) * 0.14;

    // Maintien de crête : suit les pics vers le haut, redescend doucement.
    final hold = peak >= previous.hold
        ? peak
        : math.max(level, previous.hold - 0.012);

    final next = _VuLevels(level < 0.001 ? 0 : level, hold);
    if (next != previous) _levels.value = next;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _audioData?.dispose();
    if (_visualizationOwned && SoLoud.instance.isInitialized) {
      try {
        SoLoud.instance.setVisualizationEnabled(false);
      } catch (_) {
        // Moteur peut-être déjà arrêté — sans conséquence.
      }
    }
    _levels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Moteur indisponible : rien à afficher (n'occupe aucune place).
    if (_ticker == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Niveau de sortie audio',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _VuMeterPainter(
                levels: _levels,
                segmentCount: widget.segmentCount,
                idleColor: scheme.onSurfaceVariant.withValues(alpha: 0.18),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Niveau instantané lissé et maintien de crête, tous deux dans [0, 1].
@immutable
class _VuLevels {
  const _VuLevels(this.level, this.hold);

  final double level;
  final double hold;

  @override
  bool operator ==(Object other) =>
      other is _VuLevels && other.level == level && other.hold == hold;

  @override
  int get hashCode => Object.hash(level, hold);
}

class _VuMeterPainter extends CustomPainter {
  _VuMeterPainter({
    required this.levels,
    required this.segmentCount,
    required this.idleColor,
  }) : super(repaint: levels);

  final ValueNotifier<_VuLevels> levels;
  final int segmentCount;
  final Color idleColor;

  // Répartition des couleurs des segments : vert (sûr) → ambre → rouge (crête).
  static const _amberFrom = 0.62;
  static const _redFrom = 0.86;

  Color _segmentColor(double fraction) {
    if (fraction >= _redFrom) return const Color(0xFFFF5252);
    if (fraction >= _amberFrom) return const Color(0xFFFFB300);
    return const Color(0xFF34D07F);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final value = levels.value;
    const gap = 2.0;
    final segWidth = (size.width - gap * (segmentCount - 1)) / segmentCount;
    final radius = Radius.circular(math.min(2, segWidth / 2));

    final litCount = (value.level * segmentCount).ceil();
    final holdIndex = (value.hold * segmentCount).ceil() - 1;

    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < segmentCount; i++) {
      final fraction = (i + 1) / segmentCount;
      final left = i * (segWidth + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, 0, segWidth, size.height),
        radius,
      );

      final lit = i < litCount;
      if (lit) {
        paint.color = _segmentColor(fraction);
      } else if (i == holdIndex && holdIndex >= 0) {
        // Segment de maintien de crête, atténué.
        paint.color = _segmentColor(fraction).withValues(alpha: 0.5);
      } else {
        paint.color = idleColor;
      }
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_VuMeterPainter oldDelegate) =>
      oldDelegate.segmentCount != segmentCount ||
      oldDelegate.idleColor != idleColor;
}
