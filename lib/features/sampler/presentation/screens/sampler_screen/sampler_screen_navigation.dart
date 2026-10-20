// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../sampler_screen.dart';

/// Ouverture des écrans (bibliothèque, réglages, recherche), raccourcis et reconnexion Drive.
/// Méthodes de [_SamplerScreenState] extraites via extension dans le même `part`.
extension _SamplerScreenNavigation on _SamplerScreenState {
  /// Ouvre la bibliothèque sans fermer de drawer (base method).
  Future<void> _openLibrary() async {
    await SoundLibraryManageScreen.open(
      context,
      notifier: _notifier,
      database: _database,
      onReconnect: () => unawaited(_reconnectDriveInline()),
    );
    if (!mounted) return;
    await _notifier.loadSounds();
  }

  /// Ouvre les paramètres sans fermer de drawer (base method).
  Future<void> _openSettings({bool scrollToDriveSection = false}) async {
    if (!mounted) return;
    await SettingsScreen.open(
      context,
      database: _database,
      libraryRepository: widget.services.libraryRepository,
      syncController: widget.services.syncController,
      autoSyncCoordinator: widget.services.autoSyncCoordinator,
      appPreferences: widget.services.appPreferences,
      scrollToDriveSection: scrollToDriveSection,
    );
    if (!mounted) return;
    await _notifier.loadSounds();
  }

  /// Action « Reconnecter » pour les snackbars d'échec dus à une session Google
  /// expirée — relance l'OAuth interactif **en place** (sans ouvrir les
  /// réglages). Renvoie `null` si la session est valide (l'échec a une autre
  /// cause).
  SnackBarAction? _reconnectSnackBarAction() {
    if (!_notifier.driveSessionExpired) return null;
    return SnackBarAction(
      label: 'Reconnecter',
      onPressed: () => unawaited(_reconnectDriveInline()),
    );
  }

  /// Reconnexion Drive déclenchée depuis un snackbar, sans quitter l'écran.
  ///
  /// Le refresh silencieux du token a déjà été tenté (et a échoué) avant que
  /// « Session Google expirée » ne s'affiche — inutile de le rejouer ici :
  /// [ensureDriveConnected] enchaîne directement sur l'OAuth interactif quand
  /// [requiresInteractiveReconnect] est levé. Au succès, on efface la bannière
  /// hors-ligne et on recharge les sons pour lever les indisponibilités.
  Future<void> _reconnectDriveInline() async {
    if (_driveReconnectInFlight) return;
    final repo = widget.services.libraryRepository;
    final sync = widget.services.syncController;
    if (!await ensureGoogleOAuthConfigured(context)) return;
    if (!mounted) return;

    setState(() => _driveReconnectInFlight = true);
    try {
      final connected = await repo.ensureDriveConnected();
      if (!mounted) return;
      if (!connected) return; // l'utilisateur a annulé le sélecteur de compte
      sync.clearAuthOfflineState();
      await repo.refreshConnectedAccountProfile();
      await _notifier.loadSounds();
      if (mounted) AppSnackBar.show(context, 'Session Google renouvelée');
    } on GoogleOAuthNotConfiguredException catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          e.message,
          duration: const Duration(seconds: 8),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          'Reconnexion impossible — réessayez depuis les réglages.',
          action: SnackBarAction(
            label: 'Réglages',
            onPressed: () =>
                unawaited(_openSettings(scrollToDriveSection: true)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _driveReconnectInFlight = false);
    }
  }

  /// Ouvre la recherche-éclair (overlay) ; met en évidence le pad dédié préparé.
  /// [typeFilter] pré-filtre sur un type de son (Ctrl+G/H/J).
  Future<void> _openQuickSearch({SoundType? typeFilter}) async {
    final result = await QuickSearchOverlay.show(
      context,
      notifier: _notifier,
      initialTypeFilter: typeFilter,
      onReconnect: () => unawaited(_reconnectDriveInline()),
    );
    if (!mounted) return;
    // Les pré-écoutes (bruitages/ambiances) jouent jusqu'à la fin et se libèrent
    // seules ; les musiques jouent dans la régie. Rien à couper à la fermeture.
    final padId = result?.highlightPadId;
    if (padId == null) return;
    _emphasizePad(padId);
  }

  Future<void> _handleAddPadShortcut() async {
    if (!isNativeDesktopPlatform() || !mounted) return;
    final board = _notifier.state.selectedBoard;
    if (board == null) return;
    final pads = _notifier.state.pads;
    final lastRowIndex = pads.isEmpty
        ? 0
        : pads.map((p) => p.pad.rowIndex).reduce(max);
    await _openAddPadFlow(board, rowIndex: lastRowIndex);
  }

  Future<void> _handleUndoShortcut() async {
    if (!isNativeDesktopPlatform() || !mounted) return;
    final restoredSoundId = await _notifier.undoLastRemoval();
    if (!mounted || restoredSoundId == null) return;
    setState(() {
      _recentlyRestoredSoundId = restoredSoundId;
    });
    _scrollPadIntoView(restoredSoundId);
    unawaited(
      Future<void>.delayed(_padEmphasisDuration, () {
        if (!mounted || _recentlyRestoredSoundId != restoredSoundId) return;
        setState(() {
          _recentlyRestoredSoundId = null;
        });
      }),
    );
  }

  Future<void> _openAddPadFlow(SoundBoard board, {int rowIndex = 0}) async {
    final draftPadId = _notifier.beginDraftPad(rowIndex: rowIndex);
    if (draftPadId == null) return;

    final padItem = await _notifier.commitDraftPad(
      draftPadId: draftPadId,
      soundIds: [],
    );
    if (!mounted || padItem == null) return;

    await PadDetailsScreen.open(
      context,
      padItem: padItem,
      notifier: _notifier,
      appPreferences: widget.services.appPreferences,
      openPickerOnStart: true,
    );

    if (!mounted) return;
    final current = _notifier.findPadItemById(padItem.pad.id);
    if (current != null && current.pad.sounds.isEmpty) {
      await _notifier.removeSound(current);
    }
  }

  /// Déclenche un pad depuis une touche assignée (voir
  /// `PadDetailsScreen`/`AppPreferences.setPadHotkey`) — un `HardwareKeyboard`
  /// global plutôt que le `Shortcuts`/`Actions` plus bas : ce dernier gère des
  /// combinaisons avec modificateur, alors qu'ici il faut explicitement
  /// vérifier l'absence de modificateur ET l'absence de focus texte (une
  /// touche seule assignée ne doit jamais voler une frappe de saisie).
  bool _handlePadHotkeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    // Inactif tant que la grille des pads n'est pas la route au sommet de la
    // pile (détails de pad, réglages, bibliothèque, menu contextuel, recherche-
    // éclair… toute modale/écran ouvert par-dessus doit couper le raccourci).
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isShiftPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return false;
    }
    final focused = FocusManager.instance.primaryFocus;
    if (focused?.context?.widget is EditableText) return false;

    final keyId = event.logicalKey.keyId;
    for (final item in _notifier.state.pads) {
      if (widget.services.appPreferences.hotkeyForPad(item.pad.id) == keyId) {
        unawaited(_handlePadTap(context, item));
        return true;
      }
    }
    return false;
  }

  // ---------- build ----------
}
