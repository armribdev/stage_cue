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

  Future<Set<int>> getLocallyAvailableSoundIds() async {
    final snapshot = await _searchIndex.ensureLoaded();
    return snapshot.locallyAvailableSoundIds;
  }

  // ── Index de recherche ────────────────────────────────────────────────────

  /// Instantané de la bibliothèque disponible SANS attente — `null` avant le
  /// premier chargement. Le sélecteur de sons s'en sert pour s'ouvrir sans
  /// écran de chargement, puis appelle [refreshSearchIndex].
  SoundSearchSnapshot? get searchSnapshot => _searchIndex.current;

  /// Nombre de sons encore « à traiter » — pour le badge des menus. Réactif :
  /// se met à jour à chaque reconstruction de l'index, sans rebuild de l'écran.
  ValueListenable<int> get unprocessedSoundCount =>
      _searchIndex.unprocessedCount;

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

  // ── Tags ──────────────────────────────────────────────────────────────────

  Future<List<TagCategoryWithTags>> loadTagCatalog() async {
    return await _repository.getTagCatalog();
  }

  Future<List<TagItem>> getTagsForSound(int soundId) async {
    return await _repository.getTagsForSound(soundId);
  }

  Future<void> updateSoundTags(int soundId, Set<int> tagIds) async {
    await _repository.setTagsForSound(soundId, tagIds.toList());
    // Les tags sont indexés en bloc : pas de patch ponctuel possible, on
    // reconstruit (rare, jamais sur le chemin live).
    unawaited(refreshSearchIndex());
  }
}
