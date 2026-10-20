// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../sound_picker_overlay.dart';

/// Actions par mode (lecture, pad, gestion) et notifications locales.
/// Méthodes de [_SoundPickerOverlayState] extraites via extension dans le même `part`.
extension _SoundPickerActions on _SoundPickerOverlayState {
  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _onSubmit() async {
    final shown = _shownResults(_results);
    if (shown.isEmpty) return;
    final index = _clampSelectedIndex(shown.length);
    final sound = shown[index];
    switch (widget.mode) {
      case QuickSearchMode():
        await widget.notifier.previewSound(sound.id);
        if (mounted) Navigator.of(context).pop();
      case MusicPickerMode(playNow: true):
        await _playMusicNow(sound);
      case MusicPickerMode():
        await _enqueueMusic(sound);
      case AmbiancePickerMode():
        await _playAmbianceNow(sound);
      case PadPickerMode():
        await _togglePadSound(sound);
      case LibraryMode():
        await _prepareAndClose(sound);
      case ManageMode():
        await _handleManageTap(sound);
      case PadVariantMode(padItem: final padItem):
        _playPadVariant(padItem, index);
    }
  }

  // QuickSearch
  Future<void> _previewSound(Sound sound) async {
    final ok = await widget.notifier.previewSound(sound.id);
    if (!mounted || ok) return;
    _showPreviewFailureSnackBar();
  }

  Future<void> _toggleLibraryPreview(Sound sound) async {
    final ok = await widget.notifier.toggleLibraryPreview(sound.id);
    if (!mounted || ok) return;
    _showPreviewFailureSnackBar();
  }

  /// Échec de pré-écoute/mise en file. Consomme d'abord l'erreur musique
  /// spécifique (format, introuvable…) si elle existe — l'overlay est la route
  /// active, donc [SamplerScreen] la laisse pour lui plutôt que de l'afficher
  /// derrière la barrière modale. À défaut, message générique distinguant token
  /// expiré et simple indisponibilité réseau.
  void _showPreviewFailureSnackBar() {
    final expired = widget.notifier.driveSessionExpired;
    final specific = widget.notifier.consumeLastMusicPlaybackError();
    final message =
        specific ??
        (expired
            ? 'Session Google expirée — touchez « Reconnecter »'
            : 'Son indisponible — vérifiez la connexion');
    _showLocalSnackBar(message, withReconnect: expired);
  }

  /// Affiche sur le messenger **local** (au-dessus du dialog) plutôt que via
  /// `.of(context)`, qui remonterait au messenger racine rendu derrière la
  /// barrière modale — d'où un snackbar qui « reste » sans se fermer. Remplace
  /// le courant plutôt que d'empiler.
  void _showLocalSnackBar(String message, {bool withReconnect = false}) {
    final onReconnect = widget.onReconnect;
    final messenger =
        _messengerKey.currentState ?? ScaffoldMessenger.of(context);
    AppSnackBar.showOn(
      messenger,
      message,
      action: (withReconnect && onReconnect != null)
          ? SnackBarAction(label: 'Reconnecter', onPressed: onReconnect)
          : null,
    );
  }

  Future<void> _prepareAndClose(Sound sound) async {
    final result = await widget.notifier.prepareSoundFromQuickSearch(sound.id);
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> _prepareSelectedAndClose() async {
    final shown = _shownResults(_results);
    if (shown.isEmpty) return;
    await _prepareAndClose(shown[_clampSelectedIndex(shown.length)]);
  }

  // Music picker
  Future<void> _enqueueMusic(Sound sound) async {
    final padItem = await widget.notifier.enqueueMusicBySoundId(sound.id);
    if (!mounted || padItem != null) return;
    // Échec : surfacer le message ici (route active) plutôt que de le laisser à
    // [SamplerScreen], qui le dessinerait derrière l'overlay sans le fermer.
    _showPreviewFailureSnackBar();
  }

  Future<void> _playAmbianceNow(Sound sound) async {
    final padItem = await widget.notifier.playAmbianceBySoundId(sound.id);
    if (!mounted) return;
    if (padItem == null) {
      _showPreviewFailureSnackBar();
      return;
    }
    Navigator.of(context).pop();
  }

  bool _isAmbianceOnAir(Sound sound) {
    final current = widget.notifier.state.currentAmbiancePad;
    if (current == null || !current.isPlaying) return false;
    final sounds = current.pad.sounds;
    return sounds.length == 1 && sounds.first.id == sound.id;
  }

  Future<void> _playMusicNow(Sound sound) async {
    final padItem = await widget.notifier.playMusicBySoundId(sound.id);
    if (!mounted) return;
    if (padItem == null) {
      _showPreviewFailureSnackBar();
      return;
    }
    Navigator.of(context).pop();
  }

  bool _isMusicOnAir(Sound sound) {
    final padItem = widget.notifier.findMusicPadForSound(sound.id);
    if (padItem == null) return false;
    final current = widget.notifier.state.currentMusicPad;
    return current?.pad.id == padItem.pad.id && (current?.isPlaying ?? false);
  }

  bool _isMusicQueued(Sound sound) {
    final padItem = widget.notifier.findMusicPadForSound(sound.id);
    if (padItem == null) return false;
    return widget.notifier.state.musicQueuePadIds.contains(padItem.pad.id);
  }

  bool _isMusicOnBoard(Sound sound) => widget.notifier.state.pads.any(
    (p) => p.pad.sounds.any((s) => s.id == sound.id),
  );

  // Pad picker
  Future<void> _togglePadSound(Sound sound) async {
    final mode = _padMode!;
    if (_addingSoundIds.contains(sound.id) ||
        _removingSoundIds.contains(sound.id)) {
      return;
    }
    if (_padSoundIds.contains(sound.id)) {
      await _removePadSound(sound, mode);
    } else {
      await _addPadSound(sound, mode);
    }
  }

  Future<void> _addPadSound(Sound sound, PadPickerMode mode) async {
    if (_padSoundIds.contains(sound.id)) return;
    final draftIds = mode.draftSelectedIds;
    if (draftIds != null) {
      draftIds.add(sound.id);
      await widget.notifier.updateDraftPadSounds(mode.draftPadId!, draftIds);
      if (!mounted) return;
      setState(_syncPadSoundIds);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() => _addingSoundIds.add(sound.id));
    await widget.notifier.addSoundToPad(mode.padId!, sound.id);
    if (!mounted) return;
    setState(() {
      _addingSoundIds.remove(sound.id);
      _syncPadSoundIds();
    });
    mode.onPadUpdated?.call();
  }

  Future<void> _removePadSound(Sound sound, PadPickerMode mode) async {
    if (!_padSoundIds.contains(sound.id)) return;
    final draftIds = mode.draftSelectedIds;
    if (draftIds != null) {
      draftIds.remove(sound.id);
      await widget.notifier.updateDraftPadSounds(mode.draftPadId!, draftIds);
      if (!mounted) return;
      setState(_syncPadSoundIds);
      return;
    }
    if (_padSoundIds.length <= 1) return;
    setState(() => _removingSoundIds.add(sound.id));
    await widget.notifier.removeSoundFromPad(mode.padId!, sound.id);
    if (!mounted) return;
    setState(() {
      _removingSoundIds.remove(sound.id);
      _syncPadSoundIds();
    });
    mode.onPadUpdated?.call();
  }

  // Pad variant picker
  void _playPadVariant(PadItem padItem, int index) {
    Navigator.of(context).pop();
    unawaited(widget.notifier.playPadSoundAtIndex(padItem, index));
  }

  // Manage
  /// Large écran : le son s'édite dans le volet de droite. Étroit : page
  /// d'édition poussée par-dessus la liste.
  Future<void> _handleManageTap(Sound sound) async {
    final mode = _manageMode;
    if (mode == null) return;
    if (_isSplitLayout) {
      await _editInPane(sound);
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SoundDetailsScreen(
          sound: sound,
          tagCatalog: _tagCatalog,
          repository: mode.repository,
          notifier: widget.notifier,
        ),
      ),
    );
    if (!mounted) return;
    // L'édition a pu changer le nom, le type ou les tags : on reconstruit
    // l'index plutôt que de recharger la seule liste des sons.
    await _adoptRefreshedSnapshot();
  }

  Future<void> _editInPane(Sound sound) async {
    if (_editingSound?.id == sound.id) return;
    if (_editDirty && !await _confirmDiscardEdits()) return;
    if (!mounted) return;
    setState(() {
      _editingSound = sound;
      _editDirty = false;
    });
    _autoPreviewIfQueue(sound);
  }

  /// Lance l'aperçu du son qu'on vient d'ouvrir, en file de traitement
  /// seulement. Échec silencieux : un son pas encore téléchargé ne doit pas
  /// noyer la file sous les messages — le ▶ manuel signale l'erreur.
  void _autoPreviewIfQueue(Sound sound) {
    if (!_unprocessedOnly || !_autoPreview || !_isSplitLayout) return;
    unawaited(widget.notifier.toggleLibraryPreview(sound.id));
  }

  Future<bool> _confirmDiscardEdits() => AppConfirmDialog.show(
    context,
    title: 'Abandonner les modifications',
    message: 'Les modifications de ce son ne sont pas enregistrées.',
    confirmLabel: 'Abandonner',
    isDestructive: true,
  );

  /// Fermeture de l'écran avec des modifications en cours (retour, Échap).
  Future<void> _confirmDiscardAndClose() async {
    if (!await _confirmDiscardEdits() || !mounted) return;
    setState(() => _editDirty = false);
    Navigator.of(context).pop();
  }
}
