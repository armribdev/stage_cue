import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../../core/audio/gain.dart';
import '../../../../core/theme/app_tokens.dart';
import 'sound_edit_preload.dart';

/// Gain en dB tel qu'il est montré (curseur, valeur, hauteur de la waveform) :
/// il suit le gain du formulaire, mais une valeur posée d'un coup — celle d'un
/// autre son, le résultat d'« Auto » — est atteinte par un glissement, partagé
/// par tout ce qui l'affiche pour que ça reste cohérent.
///
/// Il glisse en dB (pas en facteur linéaire) : c'est l'échelle du curseur, la
/// poignée avance donc à vitesse régulière. Un geste sur le curseur, lui, passe
/// par [jumpTo] : suivi sans retard.
class GainGlide extends ValueNotifier<double> {
  final AnimationController _controller;
  double _from = 0;
  double _to = 0;

  GainGlide({required TickerProvider vsync, required double initialDb})
    : _controller = AnimationController(
        vsync: vsync,
        duration: kSoundSwitchDuration,
      ),
      super(initialDb) {
    _controller.addListener(_tick);
  }

  void _tick() {
    value =
        _from +
        (_to - _from) * Curves.easeOutCubic.transform(_controller.value);
  }

  /// Glisse jusqu'à [targetDb] ; d'emblée si [instant] (réduction des
  /// animations).
  void glideTo(double targetDb, {bool instant = false}) {
    if (instant || value == targetDb) return jumpTo(targetDb);
    _from = value;
    _to = targetDb;
    _controller.forward(from: 0);
  }

  /// Pose [targetDb] tout de suite, en interrompant un glissement en cours.
  void jumpTo(double targetDb) {
    _controller.stop();
    value = targetDb;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// Gain en dB, signé, à la décimale : « +3,5 dB », « −6,0 dB », « 0 dB ».
String formatGainDb(double db) {
  final rounded = (db * 10).round() / 10;
  if (rounded == 0) return '0 dB';
  final sign = rounded > 0 ? '+' : '−';
  return '$sign${rounded.abs().toStringAsFixed(1).replaceAll('.', ',')} dB';
}

/// Curseur du gain d'un son (−24 à +12 dB, par pas de 0,5 dB) avec sa valeur et,
/// si [onAuto] est fourni, le bouton « Auto » (normalisation par la sonie).
/// Montre [gainDb] ([GainGlide]) ; [onChanged] reçoit, en dB, les gestes sur le
/// curseur.
class SoundGainField extends StatelessWidget {
  final ValueListenable<double> gainDb;
  final ValueChanged<double> onChanged;

  /// `null` = pas de bouton « Auto » (aucun moteur audio pour mesurer).
  final VoidCallback? onAuto;
  final bool isMeasuring;

  const SoundGainField({
    super.key,
    required this.gainDb,
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
            valueListenable: gainDb,
            builder: (context, shown, _) {
              final text = formatGainDb(shown);
              return Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: shown.clamp(kGainMinDb, kGainMaxDb),
                      min: kGainMinDb,
                      max: kGainMaxDb,
                      label: text,
                      // Pas de `divisions` : elles dessinent un trait par pas.
                      // Le pas de 0,5 dB est appliqué ici.
                      onChanged: (db) => onChanged((db * 2).round() / 2),
                    ),
                  ),
                  SizedBox(
                    width: 76,
                    child: Text(
                      text,
                      maxLines: 1,
                      softWrap: false,
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
                'Mesure la sonie du fichier et règle le gain pour '
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
