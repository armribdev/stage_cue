part of 'sampler_provider.dart';

/// Disponibilité d'un pad musique (chargement, téléchargement) et erreurs
/// de lecture destinées à la régie.
/// Méthodes de [MusicController] extraites via extension dans le même `part`.

extension MusicAvailability on MusicController {
  Future<void> _refreshPadAvailability(PadItem padItem) async {
    if (padItem.isPlayable) return;
    await _o._loadPlayersForPad(padItem, padItem.pad);
  }

  Future<bool> _prepareMusicPadForPlayback(
    PadItem padItem, {
    required bool downloadIfNeeded,
  }) async {
    if (padItem.isPlayable) return true;
    await _o._loadPlayersForPad(padItem, padItem.pad);
    if (padItem.isPlayable) return true;
    if (!downloadIfNeeded) return false;
    return _o.downloadAndLoadPad(padItem);
  }

  bool _isMusicPadPermanentlyUnavailable(PadItem padItem) {
    return padItem.unavailabilityReason == PadUnavailabilityReason.offline ||
        padItem.unavailabilityReason == PadUnavailabilityReason.missingFile ||
        padItem.unavailabilityReason ==
            PadUnavailabilityReason.unsupportedFormat;
  }

  void _scheduleMusicPadDownload(PadItem padItem) {
    if (padItem.isPlayable) return;
    if (_isMusicPadPermanentlyUnavailable(padItem)) return;
    if (padItem.pendingDownloadCount == 0) return;
    unawaited(_o.downloadAndLoadPad(padItem));
  }

  /// [detail] : cause précise de l'échec (ex. raison du lecteur) — à défaut, la
  /// raison de disponibilité du pad sert de motif au journal.
  void _setMusicLoadError([PadItem? padItem, String? detail]) {
    final reason = padItem?.unavailabilityReason;
    // Un token révoqué remonte en `offline` (cf. correction du classement dans
    // `resolvePlayablePath`) : distinguer « session expirée » d'un vrai hors-ligne
    // pour ne pas envoyer l'opérateur vérifier une connexion pourtant active.
    if ((reason == PadUnavailabilityReason.offline || reason == null) &&
        _o.driveSessionExpired) {
      _lastPlaybackError = 'Session Google expirée — touchez « Reconnecter ».';
    } else {
      _lastPlaybackError = switch (reason) {
        PadUnavailabilityReason.offline => 'Son indisponible hors-ligne.',
        PadUnavailabilityReason.missingFile => 'Fichier audio introuvable.',
        PadUnavailabilityReason.unsupportedFormat =>
          'Format audio non supporté.',
        _ => 'Fichier audio introuvable ou indisponible hors-ligne.',
      };
    }
    if (padItem != null) {
      _o.reportPadTriggerFailure(
        padItem,
        reason: detail ?? _o.triggerFailureReason(padItem),
      );
    } else {
      AudioLoadLog.warn('Lecture impossible : $_lastPlaybackError');
    }
    _o._notify();
  }
}
