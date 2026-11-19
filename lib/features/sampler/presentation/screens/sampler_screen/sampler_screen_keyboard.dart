// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../sampler_screen.dart';

/// Vue « clavier » du board et bascule entre les vues. Méthodes de
/// [_SamplerScreenState] extraites via extension dans le même `part`.
extension _SamplerScreenKeyboard on _SamplerScreenState {
  /// Vue réellement affichée. Les raccourcis clavier n'existent que sur poste
  /// desktop natif (voir `initState`) : ailleurs, la vue clavier n'aurait que
  /// des touches mortes, on reste en grille quoi qu'ait choisi l'utilisateur.
  BoardView get _boardView => isNativeDesktopPlatform()
      ? widget.services.appPreferences.boardView
      : BoardView.grid;

  void _toggleBoardView() {
    final next = _boardView == BoardView.grid
        ? BoardView.keyboard
        : BoardView.grid;
    // `setBoardView` met à jour la valeur en mémoire avant son premier `await`.
    unawaited(widget.services.appPreferences.setBoardView(next));
    setState(() {
      // Un glisser en cours ne survit pas au démontage de la grille.
      _draggingPadId = null;
      _dropTarget = null;
      _editDragUiReady = false;
    });
  }

  Widget _buildKeyboardView(BuildContext context, SamplerState state) {
    final preferences = widget.services.appPreferences;
    // Les touches se réassignent dans les détails d'un pad : sans cette
    // écoute, la vue garderait l'ancienne attribution au retour.
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => KeyboardPadsView(
        pads: [
          for (final pad in state.pads)
            if (!pad.isDraft && _shouldShowPadOnGrid(pad)) pad,
        ],
        hotkeyForPad: preferences.hotkeyForPad,
        onTap: (padItem) => unawaited(_handlePadTap(context, padItem)),
        // Mode Spectacle : assignation et édition verrouillées, comme sur la
        // grille (déclencher reste permis).
        onAssign: _isEditable ? preferences.setPadHotkeys : null,
        onEdit: _isEditable
            ? (padItem) => PadDetailsScreen.open(
                context,
                padItem: _notifier.findPadItemById(padItem.pad.id) ?? padItem,
                notifier: _notifier,
                appPreferences: preferences,
              )
            : null,
        highlightedPadId: _highlightedPadId,
        padding: _padsGridScrollPadding(context),
      ),
    );
  }
}
