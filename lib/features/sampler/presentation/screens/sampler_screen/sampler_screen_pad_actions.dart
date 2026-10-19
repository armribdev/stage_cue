// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../sampler_screen.dart';

/// Interactions avec un pad : déclenchement, préparation, indisponibilité, sélecteur de sons.
/// Méthodes de [_SamplerScreenState] extraites via extension dans le même `part`.
extension _SamplerScreenPadActions on _SamplerScreenState {

  Future<void> _handlePadTap(BuildContext context, PadItem padItem) async {
    final resolved = _notifier.findPadItemById(padItem.pad.id) ?? padItem;

    debugPrint(
      '[TAP] pad="${resolved.pad.displayName}" id=${resolved.pad.id} '
      'isPlayable=${resolved.isPlayable} appearsReady=${resolved.appearsReady} '
      'isPlaying=${resolved.isPlaying} isDownloading=${resolved.isDownloading} '
      'unavailabilityReason=${resolved.unavailabilityReason} '
      'slots=${resolved.slots.length} readySlots=${resolved.slots.where((s) => s.isReady).length}',
    );

    if (_notifier.isLiveOfflineMode && !resolved.hasLocallyAvailableSound) {
      return;
    }

    // PRÊT (bouton GO) : lecture immédiate garantie.
    if (resolved.isPlayable) {
      unawaited(HapticFeedback.selectionClick());
      await _notifier.toggleSound(resolved);
      return;
    }

    // Fichier local validé, lecteur SoLoud pas encore chargé.
    if (resolved.appearsReady) {
      debugPrint(
        '[TAP] pad="${resolved.pad.displayName}" → appearsReady, refreshing players',
      );
      unawaited(HapticFeedback.selectionClick());
      await _notifier.refreshPadPlayback(resolved.pad.id);
      if (!mounted) return;
      final after = _notifier.findPadItemById(resolved.pad.id) ?? resolved;
      debugPrint(
        '[TAP] pad="${resolved.pad.displayName}" → after refresh: isPlayable=${after.isPlayable}',
      );
      if (after.isPlayable) {
        await _notifier.toggleSound(after);
      }
      return;
    }

    final reason = resolved.unavailabilityReason;

    if (reason == PadUnavailabilityReason.offline ||
        reason == PadUnavailabilityReason.unsupportedFormat) {
      debugPrint(
        '[TAP] pad="${resolved.pad.displayName}" → BLOQUÉ reason=$reason',
      );
      unawaited(HapticFeedback.heavyImpact());
      _showBlockedPadFeedback(resolved, reason);
      return;
    }

    if (reason == PadUnavailabilityReason.missingFile ||
        _notifier.isPadTapBlocked(resolved)) {
      debugPrint(
        '[TAP] pad="${resolved.pad.displayName}" → BLOQUÉ reason=$reason',
      );
      return;
    }

    if (!_notifier.allowsSoundDownload) return;

    debugPrint(
      '[TAP] pad="${resolved.pad.displayName}" → EN ROUTE / preparing',
    );
    // EN ROUTE (bouton DL) : on télécharge SANS jouer. Le moment de lecture
    // doit rester maîtrisé par l'opérateur → le pad devient un bouton GO une
    // fois prêt, et un second tap le déclenche immédiatement.
    if (resolved.isDownloading) return; // déjà en cours
    unawaited(HapticFeedback.selectionClick());
    await _preparePad(resolved);
  }

  /// Prépare un pad EN ROUTE : recharge depuis le cache puis télécharge si
  /// nécessaire — **sans lecture automatique**. Le pad passe en PRÊT (GO) ;
  /// l'opérateur déclenche au tap suivant. Feedback non-bloquant si bloqué.
  Future<void> _preparePad(PadItem padItem) async {
    // État non résolu : un simple rechargement depuis le cache peut suffire.
    if (padItem.unavailabilityReason == null) {
      await _notifier.refreshPadPlayback(padItem.pad.id);
      if (!mounted) return;
    }

    final resolved = _notifier.findPadItemById(padItem.pad.id) ?? padItem;
    // déjà prêt : c'est désormais un bouton GO.
    if (resolved.isPlayable) return;

    await _notifier.downloadAndLoadPad(resolved);
    if (!mounted) return;

    final after = _notifier.findPadItemById(resolved.pad.id) ?? resolved;
    if (!after.isPlayable) {
      _showBlockedPadFeedback(after, after.unavailabilityReason);
    }
    // Sinon : le pad est maintenant PRÊT (GO), sans déclenchement automatique.
  }

  /// SnackBar non-bloquante expliquant pourquoi un pad ne joue pas, avec une
  /// action « Détails » pour la vue de téléchargement (sans la pousser de force).
  void _showBlockedPadFeedback(
    PadItem padItem,
    PadUnavailabilityReason? reason,
  ) {
    if (!mounted) return;
    final text = switch (reason) {
      PadUnavailabilityReason.offline when _notifier.driveSessionExpired =>
        'Session Google expirée — touchez « Reconnecter »',
      PadUnavailabilityReason.offline =>
        '« ${padItem.displayName} » indisponible hors-ligne',
      PadUnavailabilityReason.missingFile =>
        'Fichier introuvable pour « ${padItem.displayName} »',
      PadUnavailabilityReason.unsupportedFormat =>
        'Format audio non supporté pour « ${padItem.displayName} »',
      _ => '« ${padItem.displayName} » non téléchargé',
    };
    // Session expirée : proposer la reconnexion plutôt que le détail du pad,
    // qui ne dirait rien de la vraie cause.
    final action = _reconnectSnackBarAction() ??
        SnackBarAction(
          label: 'Détails',
          onPressed: () => _showPadUnavailableSheet(context, padItem),
        );
    AppSnackBar.show(context, text, action: action);
  }

  void _showPadUnavailableSheet(BuildContext context, PadItem padItem) {
    final reason = padItem.unavailabilityReason;
    if (reason == null) return;

    if (reason == PadUnavailabilityReason.needsDownload ||
        padItem.totalSoundCount > 1) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) =>
            PadDownloadSheet(padItem: padItem, notifier: _notifier),
      );
      return;
    }

    final (title, body) = switch (reason) {
      PadUnavailabilityReason.needsDownload => (
        'Son non téléchargé',
        'Ce pad n\'est pas disponible localement. Synchronisez la bibliothèque pour télécharger les fichiers audio.',
      ),
      PadUnavailabilityReason.offline => (
        'Hors-ligne',
        'Ce pad n\'est pas disponible sans connexion. Reconnectez-vous pour accéder aux fichiers audio.',
      ),
      PadUnavailabilityReason.missingFile => (
        'Fichier introuvable',
        _notifier.isPadRetryableFromDrive(padItem)
            ? 'Le fichier audio n\'a pas pu être chargé. Touchez le pad pour '
                  'retenter le téléchargement depuis Drive, ou resynchronisez la '
                  'bibliothèque dans les paramètres.'
            : 'Le fichier audio n\'a pas pu être chargé. Resynchronisez la '
                  'bibliothèque dans les paramètres.',
      ),
      PadUnavailabilityReason.unsupportedFormat => (
        'Format non supporté',
        'Ce format audio n\'est pas pris en charge sur cette plateforme. '
            'Convertissez le fichier en MP3 ou WAV pour l\'utiliser.',
      ),
    };

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(body, style: Theme.of(ctx).textTheme.bodyMedium),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPadWidget(
    BuildContext context,
    SamplerState state,
    PadItem padItem,
  ) {
    final editable = _isEditable;
    // Croix (suppression) et crayon (détails) ne concernent que les pads
    // confirmés en mode classique — jamais un brouillon en cours de création
    // ni le Mode Spectacle (verrouillé).
    final showEditAffordances = editable && !padItem.isDraft;
    return PadCard(
      key: ValueKey<int>(padItem.pad.id),
      padItem: padItem,
      isEditable: editable,
      isTapBlocked: _notifier.isPadTapBlocked,
      animateOnRestore: _recentlyRestoredSoundId == padItem.pad.id,
      isHighlighted: _highlightedPadId == padItem.pad.id,
      onTap: () => unawaited(_handlePadTap(context, padItem)),
      onEdit: showEditAffordances
          ? () {
              final live =
                  _notifier.findPadItemById(padItem.pad.id) ?? padItem;
              PadDetailsScreen.open(
                context,
                padItem: live,
                notifier: _notifier,
                appPreferences: widget.services.appPreferences,
              );
            }
          : null,
      onRemove: showEditAffordances
          ? () async {
              final removed = await _notifier.removeSound(padItem);
              if (!mounted || !removed) return;
            }
          : null,
      onShowSounds: padItem.totalSoundCount > 1
          ? () => _showPadSoundPicker(context, padItem)
          : null,
    );
  }

  /// Overlay listant les sons d'un multipad — permet de déclencher une
  /// variante précise plutôt que de laisser le pad piocher automatiquement.
  void _showPadSoundPicker(BuildContext context, PadItem padItem) {
    unawaited(SoundPickerOverlay.showForPadVariant(
      context,
      notifier: _notifier,
      padItem: padItem,
    ));
  }
}
