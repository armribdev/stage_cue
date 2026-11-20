part of 'sampler_provider.dart';

/// Requêtes bibliothèque, index de recherche et tags.
/// Méthodes de [SamplerNotifier] extraites via extension dans le même `part`.

extension SamplerLibraryQueries on SamplerNotifier {
  Future<List<Sound>> getAllSounds() async {
    return await _repository.getAllSounds();
  }

  Future<Set<int>> findSoundIdsByTagQuery(String query) {
    return _repository.findSoundIdsByTagQuery(query);
  }

  /// Ids des sons visibles par une bibliothèque (VUE PARTAGÉE) — scope du picker
  /// d'un board Drive : ses dossiers, recouvrements de liens compris.
  Future<Set<int>> getSoundIdsVisibleToLibrary(int libraryId) {
    return _repository.getSoundIdsVisibleToLibrary(libraryId);
  }

  // ── Index de recherche ────────────────────────────────────────────────────

  /// Instantané de la bibliothèque disponible SANS attente — `null` avant le
  /// premier chargement. Le sélecteur de sons s'en sert pour s'ouvrir sans
  /// écran de chargement, puis appelle [refreshSearchIndex].
  SoundSearchSnapshot? get searchSnapshot => _searchIndex.current;

  /// Charge l'index s'il ne l'est pas encore, sinon rend l'instantané courant.
  Future<SoundSearchSnapshot> ensureSearchIndex() =>
      _searchIndex.ensureLoaded();

  /// Reconstruit l'index (base + tags + disponibilité locale).
  Future<SoundSearchSnapshot> refreshSearchIndex() => _searchIndex.refresh();

  /// Jette l'instantané : à appeler quand la bibliothèque a changé en masse
  /// (fusion d'un pull Drive, indexation d'un dossier). Le sélecteur repartira
  /// de la base au lieu d'afficher brièvement l'ancienne liste.
  void invalidateSearchIndex() => _searchIndex.invalidate();

  /// Précharge l'index en tâche de fond pour que la toute première recherche
  /// soit déjà instantanée. Les échecs sont avalés : c'est un confort, pas une
  /// dépendance du chargement du plateau.
  Future<void> _prewarmSearchIndex() async {
    try {
      await _searchIndex.ensureLoaded();
    } catch (e, stack) {
      AudioLoadLog.severe(
        'Préchargement de l\'index de recherche échoué',
        error: e,
        stackTrace: stack,
      );
    }
  }

  // ── Suppression d'un son ──────────────────────────────────────────────────

  /// Raison pour laquelle [soundId] ne peut pas être supprimé maintenant, ou
  /// `null` s'il le peut. La suppression est définitive côté plateau (le fichier
  /// n'est récupérable que dans la corbeille Drive) : jamais en pleine
  /// représentation, ni sous un pad qui joue ce son.
  String? soundDeletionBlockedReason(int soundId) {
    if (_libraryRepository == null) {
      return 'Aucune bibliothèque Drive connectée.';
    }
    if (_isLiveSessionActive) {
      return 'Suppression impossible en Mode Spectacle.';
    }
    final onAir = <PadItem>[
      ..._state.pads,
      ?_state.currentMusicPad,
      ?_state.currentAmbiancePad,
    ];
    final playing = onAir.any(
      (item) =>
          (item.isPlaying || item.playbackTickets.isNotEmpty) &&
          item.pad.sounds.any((s) => s.id == soundId),
    );
    return playing
        ? 'Ce son est en cours de lecture — arrêtez-le avant de le supprimer.'
        : null;
  }

  /// Supprime le son de la bibliothèque (corbeille Drive + base + cache, voir
  /// [LibraryRepositorySoundDeletion.deleteLibrarySound]) puis recharge le
  /// plateau, comme après une fusion de synchro qui retire des sons : les pads
  /// qui l'utilisaient sont reconstruits, leurs lecteurs libérés.
  ///
  /// Les échecs Drive remontent tels quels, sans rien avoir changé en local.
  Future<void> deleteLibrarySound(int soundId) async {
    final blocked = soundDeletionBlockedReason(soundId);
    if (blocked != null) throw StateError(blocked);
    final repository = _libraryRepository;
    if (repository == null) throw StateError('Aucune bibliothèque connectée');
    if (_libraryPreviewSoundId == soundId) stopLibraryPreview(notify: false);
    await repository.deleteLibrarySound(soundId);
    invalidateSearchIndex();
    await loadBoards();
  }

  // ── Multipads enregistrés (décision 0051) ─────────────────────────────────

  Future<List<SavedMultipad>> loadSavedMultipads() =>
      _repository.getSavedMultipads();

  /// Enregistre une copie du multipad [pad] dans la bibliothèque. Le pad du
  /// plateau n'est pas lié au modèle créé : les deux évoluent séparément.
  Future<void> saveMultipadToLibrary(Pad pad, {required String name}) async {
    await _repository.saveMultipad(pad, name: name);
    invalidateSearchIndex();
    AppLog.info(
      'Multipad enregistré dans la bibliothèque (${pad.sounds.length} sons).',
    );
  }

  Future<void> updateSavedMultipad(
    int id, {
    String? name,
    int? colorValue,
    bool clearColor = false,
    PadPlayMode? playMode,
    List<int>? soundIds,
  }) async {
    await _repository.updateSavedMultipad(
      id,
      name: name,
      colorValue: colorValue,
      clearColor: clearColor,
      playMode: playMode,
      soundIds: soundIds,
    );
    invalidateSearchIndex();
  }

  /// Supprime le modèle. Les pads déjà posés sur un plateau restent : ce sont
  /// des copies.
  Future<void> deleteSavedMultipad(int id) async {
    await _repository.deleteSavedMultipad(id);
    invalidateSearchIndex();
    AppLog.info('Multipad enregistré supprimé de la bibliothèque.');
  }

  // ── Tags ──────────────────────────────────────────────────────────────────

  Future<List<TagCategoryWithTags>> loadTagCatalog() async {
    return await _repository.getTagCatalog();
  }

  Future<List<TagItem>> getTagsForSound(int soundId) async {
    return await _repository.getTagsForSound(soundId);
  }

  /// Noms et alias des tags, pour en déduire des tags d'un titre (décision 0041).
  Future<List<TagVocabularyEntry>> getTagVocabulary() {
    return _repository.getTagVocabulary();
  }

  /// Ajoute en masse des tags déduits des titres, que l'utilisateur vient de
  /// confirmer. N'atteint que des sons non traités (revérifié à l'écriture) et
  /// ne les marque pas traités. Invalide l'index de recherche : les tags des
  /// sons ont changé en masse (décision 0017).
  Future<({int sounds, int tags})> addTitleTagsToSounds(
    Map<int, Set<int>> tagIdsBySound,
  ) async {
    final result = await _repository.addTagsToUnprocessedSounds(tagIdsBySound);
    invalidateSearchIndex();
    AppLog.info(
      'Tags déduits des titres : ${result.tags} ajouté(s) sur '
      '${result.sounds} son(s) '
      '(${tagIdsBySound.length} son(s) confirmé(s)).',
    );
    return result;
  }
}
