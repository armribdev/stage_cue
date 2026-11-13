import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

/// Curseur du volume par défaut d'un son, avec sa valeur en pourcentage et, si
/// [onAuto] est fourni, le bouton « Auto » (normalisation par la sonie).
class SoundVolumeField extends StatelessWidget {
  final double volume;
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
    final percent = '${(volume * 100).round()}%';
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: volume,
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
