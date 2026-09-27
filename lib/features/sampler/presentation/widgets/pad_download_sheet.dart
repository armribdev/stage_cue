import 'package:flutter/material.dart';

import '../models/pad_sound_slot.dart';
import '../providers/sampler_provider.dart';
import 'pad_button.dart' show padSoundAvailabilityIcon;

/// Feuille bottom-sheet pour télécharger les sons manquants d'un pad.
class PadDownloadSheet extends StatefulWidget {
  final PadItem padItem;
  final SamplerNotifier notifier;

  const PadDownloadSheet({super.key, required this.padItem, required this.notifier});

  @override
  State<PadDownloadSheet> createState() => _PadDownloadSheetState();
}

class _PadDownloadSheetState extends State<PadDownloadSheet> {
  bool _isDownloading = false;
  bool _failed = false;

  Future<void> _download() async {
    setState(() {
      _isDownloading = true;
      _failed = false;
    });
    final ok = await widget.notifier.downloadAndLoadPad(widget.padItem);
    if (!mounted) return;
    if (widget.padItem.isFullyReady) {
      Navigator.of(context).pop();
      return;
    }
    if (widget.padItem.isPlayable) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isDownloading = false;
      _failed = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final padItem = widget.padItem;
    final isMulti = padItem.totalSoundCount > 1;
    final ready = padItem.readySoundCount;
    final total = padItem.totalSoundCount;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        32 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isMulti ? 'Variantes du pad' : 'Son non téléchargé',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            isMulti
                ? ready > 0
                      ? '$ready sur $total variantes disponibles localement.'
                      : 'Ce pad contient $total variantes non encore téléchargées.'
                : 'Ce pad n\'est pas encore disponible localement.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (isMulti) ...[
            const SizedBox(height: 16),
            ...List.generate(total, (index) {
              final sound = padItem.pad.sounds[index];
              final availability = index < padItem.slots.length
                  ? padItem.slots[index].availability
                  : PadSoundAvailability.needsDownload;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    padSoundAvailabilityIcon(availability, scheme, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        sound.displayName ?? sound.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          if (_failed) ...[
            const SizedBox(height: 8),
            Text(
              padItem.unavailabilityReason ==
                      PadUnavailabilityReason.unsupportedFormat
                  ? 'Format audio non supporté sur cette plateforme. Convertissez le fichier en MP3 ou WAV.'
                  : padItem.unavailabilityReason ==
                        PadUnavailabilityReason.missingFile
                  ? 'Fichier introuvable sur Drive. Resynchronisez la bibliothèque dans les paramètres.'
                  : padItem.unavailabilityReason ==
                        PadUnavailabilityReason.offline
                  ? 'Hors-ligne. Reconnectez-vous à Drive dans les paramètres.'
                  : 'Téléchargement échoué. Vérifiez la connexion.',
              style: TextStyle(color: scheme.error, fontSize: 13),
            ),
          ],
          if (_isDownloading && padItem.downloadTotal > 0) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: padItem.downloadDone / padItem.downloadTotal,
            ),
            const SizedBox(height: 4),
            Text(
              'Téléchargement ${padItem.downloadDone}/${padItem.downloadTotal}…',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isDownloading || padItem.isFullyReady
                  ? null
                  : _download,
              icon: _isDownloading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.cloud_download_outlined, size: 18),
              label: Text(
                padItem.isFullyReady
                    ? 'Tout est prêt'
                    : _isDownloading
                    ? 'Téléchargement…'
                    : isMulti
                    ? 'Télécharger les variantes manquantes'
                    : 'Télécharger',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
