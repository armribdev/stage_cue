// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../sound_picker_overlay.dart';

/// Actions par mode (lecture, pad, gestion) et notifications locales.
/// Méthodes de [_SoundPickerOverlayState] extraites via extension dans le même `part`.
extension _SoundPickerActions on _SoundPickerOverlayState {
  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _onSubmit() async {
    final multipads = _multipadResults;
    final shown = _shownResults(_results);
    final rowCount = multipads.length + shown.length;
    if (rowCount == 0) return;
    final row = _clampSelectedIndex(rowCount);
    if (row < multipads.length) {
      await _activateSavedMultipad(multipads[row]);
      return;
    }
    // Les modèles n'existent que dans les modes qui posent un pad et en
    // gestion : pour les autres, `index` est l'indice du son, comme avant.
    final index = row - multipads.length;
    final sound = shown[index];
    switch (widget.mode) {
      case QuickSearchMode():
        await _playQuickSearchSound(sound);
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
  /// Clic / Entrée : joue le son pour de vrai puis ferme. Échec : on reste
  /// ouvert pour que le message soit lu, au lieu de fermer l'overlay sur un
  /// « rien ne s'est passé ». L'aperçu, lui, passe par son bouton de ligne.
  Future<void> _playQuickSearchSound(Sound sound) async {
    final ok = await widget.notifier.playSoundFromQuickSearch(sound.id);
    if (!mounted) return;
    if (!ok) {
      _showPreviewFailureToast();
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _toggleLibraryPreview(Sound sound) async {
    final ok = await widget.notifier.toggleLibraryPreview(sound.id);
    if (!mounted || ok) return;
    _showPreviewFailureToast();
  }

  /// Échec de pré-écoute/mise en file. Consomme d'abord l'erreur musique
  /// spécifique (format, introuvable…) si elle existe — l'overlay est la route
  /// active, donc [SamplerScreen] la laisse pour lui plutôt que de l'afficher
  /// derrière la barrière modale. À défaut, message générique distinguant token
  /// expiré et simple indisponibilité réseau.
  void _showPreviewFailureToast() {
    final expired = widget.notifier.driveSessionExpired;
    final specific =
        widget.notifier.consumeLastMusicPlaybackError() ??
        widget.notifier.consumeLastPreviewError();
    final message =
        specific ??
        (expired
            ? 'Session Google expirée — touchez « Reconnecter »'
            : 'Son indisponible — vérifiez la connexion');
    _showLocalToast(message, withReconnect: expired);
  }

  /// Affiche le toast global — rendu au-dessus de la barrière modale par
  /// l'`AppToastHost`. Remplace le courant plutôt que d'empiler.
  void _showLocalToast(String message, {bool withReconnect = false}) {
    final onReconnect = widget.onReconnect;
    AppSnackBar.show(
      context,
      message,
      action: (withReconnect && onReconnect != null)
          ? AppToastAction(label: 'Reconnecter', onPressed: onReconnect)
          : null,
    );
  }

  Future<void> _prepareAndClose(Sound sound) async {
    final result = await widget.notifier.prepareSoundFromQuickSearch(sound.id);
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> _prepareSelectedAndClose() async {
    final multipads = _multipadResults;
    final shown = _shownResults(_results);
    final rowCount = multipads.length + shown.length;
    if (rowCount == 0) return;
    final row = _clampSelectedIndex(rowCount);
    if (row < multipads.length) {
      await _activateSavedMultipad(multipads[row]);
      return;
    }
    await _prepareAndClose(shown[row - multipads.length]);
  }

  /// Clic / Entrée sur un multipad enregistré : en gestion on le modifie, sinon
  /// on en pose une copie sur le plateau.
  Future<void> _activateSavedMultipad(SavedMultipad saved) =>
      _isManage ? _editSavedMultipad(saved) : _placeSavedMultipad(saved);

  /// Pose une copie du multipad enregistré sur le plateau (décision 0051) et
  /// ferme : même résultat qu'un son préparé, le pad créé est mis en évidence.
  Future<void> _placeSavedMultipad(SavedMultipad saved) async {
    final result = await widget.notifier.placeSavedMultipadOnBoard(saved);
    if (mounted) Navigator.of(context).pop(result);
  }

  /// Gestion : large écran, le modèle s'édite dans le volet de droite comme un
  /// son. Étroit : page d'édition poussée par-dessus la liste. Le nom, le type
  /// commun ou la liste des sons ont pu changer : on relit l'index.
  Future<void> _editSavedMultipad(SavedMultipad saved) async {
    if (_isSplitLayout) {
      await _editMultipadInPane(saved);
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            SavedMultipadDetailsScreen(notifier: widget.notifier, saved: saved),
      ),
    );
    if (mounted) await _adoptRefreshedSnapshot();
  }

  Future<void> _editMultipadInPane(SavedMultipad saved) async {
    if (_editingMultipad?.id == saved.id) return;
    if (_editDirty && !await _confirmDiscardEdits()) return;
    if (!mounted) return;
    setState(() {
      _editingMultipad = saved;
      _editingSound = null;
      _editDirty = false;
    });
  }

  /// Après l'enregistrement du multipad ouvert dans le volet : l'index porte son
  /// nouveau nom et ses nouveaux sons.
  Future<void> _afterMultipadSave() => _adoptRefreshedSnapshot();

  /// Après la suppression du multipad ouvert dans le volet : le formulaire n'a
  /// plus d'objet, on le vide et on borne la sélection à la liste raccourcie.
  Future<void> _afterMultipadDelete() async {
    setState(() {
      _editingMultipad = null;
      _editDirty = false;
    });
    await _adoptRefreshedSnapshot(refresh: false);
    if (!mounted) return;
    final count = _rowCount(_shownResults(_results));
    if (_selectedIndex >= count) {
      setState(() => _selectedIndex = count == 0 ? 0 : count - 1);
    }
  }

  // Music picker
  Future<void> _enqueueMusic(Sound sound) async {
    final padItem = await widget.notifier.enqueueMusicBySoundId(sound.id);
    if (!mounted || padItem != null) return;
    // Échec : surfacer le message ici (route active) plutôt que de le laisser à
    // [SamplerScreen], qui le dessinerait derrière l'overlay sans le fermer.
    _showPreviewFailureToast();
  }

  Future<void> _playAmbianceNow(Sound sound) async {
    final padItem = await widget.notifier.playAmbianceBySoundId(sound.id);
    if (!mounted) return;
    if (padItem == null) {
      _showPreviewFailureToast();
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
      _showPreviewFailureToast();
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
      await _commitSelection(mode, draftIds);
      if (!mounted) return;
      setState(_syncPadSoundIds);
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

  /// Répercute la liste d'ids modifiée : sur le rappel de l'appelant pour une
  /// sélection libre, sinon sur le pad brouillon du plateau.
  Future<void> _commitSelection(PadPickerMode mode, List<int> ids) async {
    final onChanged = mode.onSelectionChanged;
    if (onChanged != null) {
      onChanged();
      return;
    }
    await widget.notifier.updateDraftPadSounds(mode.draftPadId!, ids);
  }

  Future<void> _removePadSound(Sound sound, PadPickerMode mode) async {
    if (!_padSoundIds.contains(sound.id)) return;
    final draftIds = mode.draftSelectedIds;
    if (draftIds != null) {
      draftIds.remove(sound.id);
      await _commitSelection(mode, draftIds);
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
      _editingMultipad = null;
      _editDirty = false;
    });
  }

  Future<bool> _confirmDiscardEdits() => AppConfirmDialog.show(
    context,
    title: 'Abandonner les modifications',
    message: _editingMultipad != null
        ? 'Les modifications de ce multipad ne sont pas enregistrées.'
        : 'Les modifications de ce son ne sont pas enregistrées.',
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
