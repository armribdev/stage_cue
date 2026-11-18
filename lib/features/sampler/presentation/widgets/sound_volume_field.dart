import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import 'sound_edit_preload.dart';

/// Volume tel qu'il est montré (curseur, pourcentage, hauteur de la waveform) :
/// il suit le volume du formulaire, mais une valeur posée d'un coup — celui d'un
/// autre son, le résultat d'« Auto » — est atteinte par un glissement, partagé
/// par tout ce qui l'affiche pour que ça reste cohérent.
///
/// Un geste sur le curseur, lui, passe par [jumpTo] : suivi sans retard.
class VolumeGlide extends ValueNotifier<double> {
  final AnimationController _controller;
  double _from = 0;
  double _to = 0;

  VolumeGlide({required TickerProvider vsync, required double initial})
    : _controller = AnimationController(
        vsync: vsync,
        duration: kSoundSwitchDuration,
      ),
      super(initial) {
    _controller.addListener(_tick);
  }

  void _tick() {
    value =
        _from +
        (_to - _from) * Curves.easeOutCubic.transform(_controller.value);
  }

  /// Glisse jusqu'à [target] ; d'emblée si [instant] (réduction des animations).
  void glideTo(double target, {bool instant = false}) {
    if (instant || value == target) return jumpTo(target);
    _from = value;
    _to = target;
    _controller.forward(from: 0);
  }

  /// Pose [target] tout de suite, en interrompant un glissement en cours.
  void jumpTo(double target) {
    _controller.stop();
    value = target;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// Curseur du volume par défaut d'un son, avec sa valeur en pourcentage et, si
/// [onAuto] est fourni, le bouton « Auto » (normalisation par la sonie).
/// Montre [volume] ([VolumeGlide]) ; [onChanged] reçoit les gestes sur le
/// curseur.
class SoundVolumeField extends StatelessWidget {
  final ValueListenable<double> volume;
  final ValueChanged<double> onChanged;

  /// `null` = pas de bouton « Auto » (aucun moteur audio pour mesurer).
  final VoidCallback? onAuto;
  final bool isMeasuring;

  const SoundVolumeField({
    super.key,
    required this.volume,
    required this.onChanged,
    this.onAuto,
    this.isMeasuring = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ValueListenableBuilder<double>(
            valueListenable: volume,
            builder: (context, shown, _) {
              final percent = '${(shown * 100).round()}%';
              return Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: shown.clamp(0.0, 1.0),
                      min: 0.0,
                      max: 1.0,
                      label: percent,
                      onChanged: onChanged,
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      percent,
                      textAlign: TextAlign.end,
                      style: AppFonts.monoStyle(const TextStyle(fontSize: 13)),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        if (onAuto != null) ...[
          const SizedBox(width: 8),
          Tooltip(
            message:
                'Mesure la sonie du fichier et règle le volume pour '
                'normaliser',
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(64, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: isMeasuring ? null : onAuto,
              child: isMeasuring
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Auto'),
            ),
          ),
        ],
      ],
    );
  }
}
