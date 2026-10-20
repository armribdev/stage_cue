// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../sound_picker_overlay.dart';

/// File de traitement des sons « à traiter » (mode gestion) et sa barre.
/// Méthodes de [_SoundPickerOverlayState] extraites via extension dans le même `part`.
extension _SoundPickerQueue on _SoundPickerOverlayState {
  // ── File de traitement (sons « à traiter ») ───────────────────────────────

  /// Active/désactive la file. En volet scindé, l'activer ouvre tout de suite le
  /// premier son : l'utilisateur n'a plus qu'à valider ou corriger.
  void _toggleUnprocessedOnly() {
    final next = !_unprocessedOnly;
    setState(() {
      _unprocessedOnly = next;
      _selectedIndex = 0;
    });
    if (!next || !_isSplitLayout) return;
    final first = _shownResults(_results).firstOrNull;
    if (first != null) unawaited(_editInPane(first));
  }

  /// Voisin à ouvrir quand [sound] quitte la liste : le suivant, sinon le
  /// précédent. `null` si [sound] était le dernier restant.
  Sound? _neighbourOf(Sound sound) {
    final shown = _shownResults(_results);
    final i = shown.indexWhere((s) => s.id == sound.id);
    if (i < 0) return null;
    if (i + 1 < shown.length) return shown[i + 1];
    if (i > 0) return shown[i - 1];
    return null;
  }

  /// Après un enregistrement dans le volet : rafraîchit l'index puis, en file de
  /// traitement, enchaîne sur le son suivant (le validé a quitté la liste).
  Future<void> _afterPaneSave(Sound saved) async {
    final next = _unprocessedOnly ? _neighbourOf(saved) : null;
    await _adoptRefreshedSnapshot();
    if (!mounted || !_unprocessedOnly) return;
    if (next == null) {
      // Plus rien dans la file (ou le son n'en faisait pas partie).
      if (_unprocessedCount == 0) {
        setState(() {
          _editingSound = null;
          _editDirty = false;
        });
        _showLocalSnackBar('Tous les sons sont traités.');
      }
      return;
    }
    final index = _shownResults(_results).indexWhere((s) => s.id == next.id);
    setState(() {
      _editingSound = next;
      _editDirty = false;
      _selectedIndex = index < 0 ? 0 : index;
    });
    _scrollToSelected();
    _autoPreviewIfQueue(next);
  }

  void _scrollToSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _itemKey(_selectedIndex).currentContext;
      if (!mounted || ctx == null) return;
      Scrollable.ensureVisible(ctx, duration: Duration.zero);
    });
  }

  /// « Passer » : laisse le son à traiter et ouvre le suivant (en boucle).
  void _skipToNext(List<Sound> shown) {
    if (shown.length < 2) return;
    final current = _editingSound;
    final i = current == null
        ? -1
        : shown.indexWhere((s) => s.id == current.id);
    final index = (i + 1) % shown.length;
    setState(() => _selectedIndex = index);
    _scrollToSelected();
    unawaited(_editInPane(shown[index]));
  }

  /// Valide en masse les sons non traités actuellement listés (recherche et
  /// filtres compris), sans les modifier. C'est l'issue de secours pour la
  /// bibliothèque déjà organisée : la migration a mis tous les sons existants
  /// « à traiter ».
  Future<void> _markShownAsProcessed() async {
    final mode = _manageMode;
    if (mode == null) return;
    final ids = [
      for (final s in _results)
        if (!s.isProcessed) s.id,
    ];
    if (ids.isEmpty) return;
    final scope = _query.trim().isEmpty
        ? ''
        : '\n\nSeuls les sons correspondant à la recherche sont concernés.';
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Marquer comme traités',
      message:
          'Marquer ${ids.length} son${ids.length > 1 ? 's' : ''} comme '
          'traité${ids.length > 1 ? 's' : ''} sans les modifier ?$scope',
      confirmLabel: 'Tout marquer',
    );
    if (!confirmed || !mounted) return;
    try {
      await mode.repository.markSoundsProcessed(ids);
    } catch (error) {
      if (mounted) _showLocalSnackBar('Erreur : $error');
      return;
    }
    await _adoptRefreshedSnapshot();
    if (!mounted) return;
    setState(() {
      _selectedIndex = 0;
      // Le formulaire ouvert porte encore l'ancien état « à traiter » : on le
      // recrée (clé incluant isProcessed) sauf s'il a des modifications.
      final editing = _editingSound;
      if (editing != null && !_editDirty && ids.contains(editing.id)) {
        _editingSound = _all.where((s) => s.id == editing.id).firstOrNull;
      }
    });
    _showLocalSnackBar(
      '${ids.length} son${ids.length > 1 ? 's' : ''} marqué'
      '${ids.length > 1 ? 's' : ''} comme traité${ids.length > 1 ? 's' : ''}.',
    );
  }

  /// Barre de la file de traitement (mode gestion) : bascule « À traiter · N »
  /// et validation en masse. Masquée tant qu'il n'y a rien à traiter, sauf si
  /// la file est active (pour pouvoir en sortir).
  Widget _buildQueueBar(ColorScheme scheme) {
    final remaining = _unprocessedCount;
    if (remaining == 0 && !_unprocessedOnly) return const SizedBox.shrink();
    final active = _unprocessedOnly;
    final accent = scheme.primary;
    final canMarkAll = active && _results.any((s) => !s.isProcessed);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 6),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              canRequestFocus: false,
              borderRadius: AppRadius.radiusMd,
              onTap: _toggleUnprocessedOnly,
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: active ? accent.withValues(alpha: 0.12) : null,
                  borderRadius: AppRadius.radiusMd,
                  border: Border.all(
                    color: active
                        ? accent.withValues(alpha: 0.5)
                        : scheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'À traiter',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        color: active ? accent : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$remaining',
                      style: AppFonts.monoStyle(
                        TextStyle(
                          fontSize: 12,
                          color: active ? accent : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (active && _isSplitLayout)
            Tooltip(
              message: _autoPreview
                  ? 'Lecture auto à l\'ouverture : activée'
                  : 'Lecture auto à l\'ouverture : désactivée',
              child: _roundIconButton(
                scheme: scheme,
                icon: _autoPreview
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                iconColor: _autoPreview ? accent : scheme.onSurfaceVariant,
                active: _autoPreview,
                flat: true,
                onPressed: () => setState(() {
                  _autoPreview = !_autoPreview;
                  if (!_autoPreview) {
                    widget.notifier.stopLibraryPreview();
                  }
                }),
              ),
            ),
          const Spacer(),
          if (canMarkAll)
            ExcludeFocus(
              child: Tooltip(
                message:
                    'Marquer les sons listés comme traités, sans les '
                    'modifier',
                child: TextButton.icon(
                  onPressed: () => unawaited(_markShownAsProcessed()),
                  icon: const Icon(Icons.done_all_rounded, size: 16),
                  label: const Text('Tout marquer traité'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    textStyle: const TextStyle(fontSize: 12),
                    foregroundColor: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
