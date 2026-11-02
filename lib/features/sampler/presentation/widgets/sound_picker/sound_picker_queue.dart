// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../sound_picker_overlay.dart';

/// File de traitement des sons « à traiter » (mode gestion) et son encart.
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
      // Plus rien dans la file (ou le son n'en faisait pas partie) : le volet
      // affiche lui-même « Tous les sons sont traités ».
      if (_unprocessedCount == 0) {
        setState(() {
          _editingSound = null;
          _editDirty = false;
        });
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

  /// Encart de la file de traitement (mode gestion), tout en bas sous la liste
  /// et sa ligne de raccourcis : propose de passer en mode « traitement des non
  /// traités ». Gabarit constant d'un état à l'autre — seuls le libellé et le
  /// bouton (« Traiter » / « Terminer ») changent, jamais la taille de
  /// l'encart. Masqué tant qu'il n'y a rien à traiter, sauf si la file est
  /// active (pour pouvoir en sortir).
  Widget _buildQueueBar(ColorScheme scheme) {
    final remaining = _unprocessedCount;
    final active = _unprocessedOnly;
    if (remaining == 0 && !active) return const SizedBox.shrink();
    final accent = scheme.primary;
    final plural = remaining > 1 ? 's' : '';
    final label = active
        ? 'Traitement · $remaining restant$plural'
        : '$remaining son$plural non traité$plural';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(top: AppElevation.border(scheme)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: active ? accent : scheme.onSurfaceVariant,
              ),
            ),
          ),
          // Visible seulement en traitement ; hors file, un vide de même
          // taille garde l'encart à gabarit constant.
          if (_isSplitLayout && !active)
            const SizedBox.square(dimension: _actionButtonSize)
          else if (_isSplitLayout)
            Tooltip(
              message: _autoPreview
                  ? "Lecture auto à l'ouverture : activée"
                  : "Lecture auto à l'ouverture : désactivée",
              child: _roundIconButton(
                scheme: scheme,
                icon: _autoPreview
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                iconColor: _autoPreview ? accent : scheme.onSurfaceVariant,
                active: _autoPreview,
                flat: true,
                // Désactiver coupe l'aperçu en cours : l'éditeur du volet le
                // fait lui-même en voyant `autoPlayEntryPoint` retomber.
                onPressed: () => setState(() => _autoPreview = !_autoPreview),
              ),
            ),
          const SizedBox(width: 4),
          ExcludeFocus(
            child: OutlinedButton(
              onPressed: _toggleUnprocessedOnly,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(88, 30),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontSize: 13),
              ),
              child: Text(active ? 'Terminer' : 'Traiter'),
            ),
          ),
        ],
      ),
    );
  }
}
