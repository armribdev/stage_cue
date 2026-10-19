// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../sound_picker_overlay.dart';

/// Navigation clavier dans la liste de résultats.
/// Méthodes de [_SoundPickerOverlayState] extraites via extension dans le même `part`.
extension _SoundPickerNavigation on _SoundPickerOverlayState {

  // ── Navigation clavier ────────────────────────────────────────────────────

  int _clampSelectedIndex(int count) =>
      count == 0 ? 0 : _selectedIndex.clamp(0, count - 1);

  void _moveSelection(int delta) {
    final shown = _shownResults(_results);
    if (shown.isEmpty) return;
    final next = (_selectedIndex + delta).clamp(0, shown.length - 1);
    if (next == _selectedIndex) return;

    final policy = delta < 0
        ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
        : ScrollPositionAlignmentPolicy.keepVisibleAtEnd;
    final ctx = _itemKey(next).currentContext;

    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: Duration.zero, alignmentPolicy: policy);
      setState(() => _selectedIndex = next);
      return;
    }

    _preScrollToIndex(next, delta);
    setState(() => _selectedIndex = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final lateCtx = _itemKey(next).currentContext;
      if (lateCtx == null) return;
      Scrollable.ensureVisible(lateCtx, duration: Duration.zero, alignmentPolicy: policy);
    });
  }

  GlobalKey _itemKey(int index) =>
      _itemKeys.putIfAbsent(index, GlobalKey.new);

  void _preScrollToIndex(int index, int delta) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final viewport = position.viewportDimension;
    final current = position.pixels;
    final max = position.maxScrollExtent;
    final itemTop = index * _itemExtent;
    final itemBottom = itemTop + _itemExtent;
    if (delta > 0 && itemBottom > current + viewport) {
      _scrollController.jumpTo((itemBottom - viewport).clamp(0.0, max));
    } else if (delta < 0 && itemTop < current) {
      _scrollController.jumpTo(itemTop.clamp(0.0, max));
    }
  }

  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    // Les flèches acceptent la répétition (touche maintenue = défilement
    // continu) ; Entrée reste sur l'appui initial pour ne jamais rejouer.
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final isRepeat = event is KeyRepeatEvent;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1);
      return KeyEventResult.handled;
    }
    // Pas de champ de recherche pour intercepter Entrée dans ce mode.
    if (_isPadVariant &&
        !isRepeat &&
        event.logicalKey == LogicalKeyboardKey.enter) {
      unawaited(_onSubmit());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
