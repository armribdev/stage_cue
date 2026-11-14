part of 'sampler_provider.dart';

/// Scènes (boards) : sélection, création, renommage, suppression, duplication.
/// Méthodes de [SamplerNotifier] extraites via extension dans le même `part`.

extension SamplerBoards on SamplerNotifier {
  void setActiveBoard(int? boardId) {
    _activeBoardId = boardId;
  }

  // ── Boards ────────────────────────────────────────────────────────────────

  Future<void> loadBoards({int? selectBoardId}) async {
    _state = _state.copyWith(isBoardsLoading: true, boardsError: null);
    _notify();

    try {
      var boards = await _repository.getSoundBoards();
      if (boards.isEmpty) {
        // Plateau vide : ne pas créer de « Scène 1 » par défaut tant que le pull
        // de lancement peut encore fusionner des boards distants. Sinon une
        // lecture transitoirement vide (race avec la synchro de démarrage) crée
        // une scène fantôme qui pollue les vrais boards. On laisse le skeleton
        // affiché (isBoardsLoading reste true) : la fin du pull relance
        // `loadBoards` (via onInitialPullSettled/onLibraryMerged). Exception :
        // aucune bibliothèque connectée → usage local, rien à attendre.
        final settled = _libraryRepository?.initialSyncSettled ?? true;
        if (!settled && (await getConnectedLibraries()).isNotEmpty) {
          return; // en attente de la fin du pull, skeleton conservé
        }
        final libraryId = await _libraryRepository?.singleConnectedLibraryId();
        final newBoardId = await _repository.createSoundBoard(
          'Scène 1',
          libraryId: libraryId,
        );
        boards = await _repository.getSoundBoards();
        selectBoardId = newBoardId;
      }

      final targetId =
          selectBoardId ?? _state.selectedBoard?.id ?? boards.first.id;
      final selected = boards.firstWhere(
        (board) => board.id == targetId,
        orElse: () => boards.first,
      );

      _state = _state.copyWith(
        boards: boards,
        selectedBoard: selected,
        isBoardsLoading: false,
        boardsError: null,
      );
      _activeBoardId = selected.id;
      _notify();

      await loadSounds();
    } catch (e) {
      _state = _state.copyWith(
        isBoardsLoading: false,
        boardsError: e.toString(),
      );
      _notify();
    }
  }

  Future<void> selectBoard(SoundBoard board) async {
    if (_state.selectedBoard?.id == board.id) return;

    // Tapis sonore : la musique en cours survit au changement de scène et reste
    // pilotable depuis la régie. On ne coupe que les bruitages (SFX) et les
    // pré-écoutes ; le pad musique qui joue est détaché hors-scène pour ne pas
    // être disposé par le rechargement du plateau.
    await stopAllNonMusicSounds();
    stopLibraryPreview(notify: false);
    _music._detachPlayingMusicToOffStage();
    _ambiance._detachPlayingToOffStage();
    // Annule les téléchargements encore EN FILE des pads qui quittent la scène
    // (bande passante Drive inutile pour un plateau qu'on abandonne). Les tâches
    // déjà démarrées finissent en cache ; le pad musique détaché hors-scène
    // (tapis sonore) est exclu pour poursuivre son éventuel téléchargement.
    final leavingPadIds = _state.pads
        .map((item) => item.pad.id)
        .where((id) => !_isKeptOffStage(id))
        .toSet();
    _downloadQueue.cancelQueued((key, _) => leavingPadIds.contains(key));
    _lastRemovedPad = null;
    _music.cleanupOffStagePads();
    _ambiance.cleanupOffStagePads();
    _state = _state.copyWith(selectedBoard: board);
    _activeBoardId = board.id;
    _notify();
    await loadSounds();
  }

  /// Bibliothèques Drive connectées, proposables comme destination d'un board.
  /// Vide si aucune session Drive n'est configurée (le board sera local).
  Future<List<Library>> getConnectedLibraries() async {
    final repository = _libraryRepository;
    if (repository == null) return const [];
    final libraries = await repository.getLibraries();
    return libraries.where((library) => library.isConnectedToDrive).toList();
  }

  /// Crée un board. [libraryId] null = board local ; sinon board rattaché à la
  /// bibliothèque Drive choisie (il ne proposera que les sons de cette biblio).
  Future<SoundBoard?> createBoard(
    String name, {
    int? color,
    int? libraryId,
  }) async {
    try {
      final newBoardId = await _repository.createSoundBoard(
        name,
        color: color,
        libraryId: libraryId,
      );
      final newBoard = SoundBoard(
        id: newBoardId,
        name: name,
        color: color,
        libraryId: libraryId,
        createdAt: DateTime.now(),
      );

      _state = _state.copyWith(
        boards: [..._state.boards, newBoard],
        selectedBoard: newBoard,
        isBoardsLoading: false,
        boardsError: null,
      );
      _activeBoardId = newBoardId;
      _notify();
      await loadSounds();
      return newBoard;
    } catch (e) {
      _state = _state.copyWith(boardsError: e.toString());
      _notify();
      return null;
    }
  }

  Future<bool> renameBoard(SoundBoard board, String name) async {
    try {
      await _repository.renameSoundBoard(board.id, name);
      final updatedBoards = _state.boards
          .map((b) => b.id == board.id ? b.copyWith(name: name) : b)
          .toList();
      final selected = _state.selectedBoard?.id == board.id
          ? board.copyWith(name: name)
          : _state.selectedBoard;

      _state = _state.copyWith(boards: updatedBoards, selectedBoard: selected);
      _notify();
      return true;
    } catch (e) {
      _state = _state.copyWith(boardsError: e.toString());
      _notify();
      return false;
    }
  }

  Future<bool> deleteBoard(SoundBoard board) async {
    try {
      await _repository.deleteSoundBoard(board.id);
      final updatedBoards = _state.boards
          .where((b) => b.id != board.id)
          .toList();
      SoundBoard? nextSelected = _state.selectedBoard;
      if (_state.selectedBoard?.id == board.id) {
        nextSelected = updatedBoards.isNotEmpty ? updatedBoards.first : null;
      }

      _state = _state.copyWith(
        boards: updatedBoards,
        selectedBoard: nextSelected,
      );
      _activeBoardId = nextSelected?.id;
      _notify();
      await loadSounds();
      return true;
    } catch (e) {
      _state = _state.copyWith(boardsError: e.toString());
      _notify();
      return false;
    }
  }

  Future<SoundBoard?> duplicateBoard(
    SoundBoard sourceBoard,
    String newName,
  ) async {
    try {
      final newBoardId = await _repository.createSoundBoard(
        newName,
        color: sourceBoard.color,
        libraryId: sourceBoard.libraryId,
      );
      await _repository.duplicatePads(sourceBoard.id, newBoardId);

      final newBoard = SoundBoard(
        id: newBoardId,
        name: newName,
        color: sourceBoard.color,
        libraryId: sourceBoard.libraryId,
        createdAt: DateTime.now(),
      );
      _state = _state.copyWith(
        boards: [..._state.boards, newBoard],
        selectedBoard: newBoard,
        isBoardsLoading: false,
        boardsError: null,
      );
      _activeBoardId = newBoardId;
      _notify();
      await loadSounds(boardId: newBoardId);
      return newBoard;
    } catch (e) {
      _state = _state.copyWith(boardsError: e.toString());
      _notify();
      return null;
    }
  }
}
