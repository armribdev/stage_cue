part of 'local_sound_datasource.dart';

/// Requêtes de bibliothèque et élagage (sons visibles, favoris, suppressions).
/// Méthodes de [LocalSoundDataSource] extraites via extension dans le même `part`.
extension LocalSoundLibraryQueries on LocalSoundDataSource {

  /// Ids des sons VISIBLES par une bibliothèque (VUE PARTAGÉE) : ses propres
  /// sons plus ceux des dossiers qu'elle voit via un recouvrement de liens (un
  /// son est visible si son dossier est membre de la bibliothèque). Sert à scoper
  /// le picker d'un board Drive sans se limiter à `sound.libraryId`.
  Future<Set<int>> getSoundIdsVisibleToLibrary(int libraryId) async {
    final rows = await _database.customSelect(
      '''
      SELECT s.id AS id
      FROM sounds s
      INNER JOIN folder_memberships fm ON fm.folder_id = s.folder_id
      WHERE fm.library_id = ?
      ''',
      variables: [Variable<int>(libraryId)],
    ).get();
    return {for (final row in rows) row.read<int>('id')};
  }

  /// Chemins relatifs des sons favoris d'une bibliothèque — pour épingler le
  /// cache : ces fichiers ne doivent jamais être évincés par le LRU (P3).
  Future<Set<String>> getFavoriteRelativePaths(int libraryId) async {
    final rows = await (_database.select(_database.sounds)
          ..where(
            (s) =>
                s.libraryId.equals(libraryId) &
                s.isFavorite.equals(true) &
                s.relativePath.isNotNull(),
          ))
        .get();
    return {
      for (final row in rows)
        if (row.relativePath != null) row.relativePath!,
    };
  }

  /// Chemins relatifs des sons posés sur les pads d'un plateau.
  ///
  /// Sert à épingler le plateau actif dans le cache audio : ses sons ne doivent
  /// pas être évincés par une passe de téléchargement massif qui rebat l'ordre
  /// LRU en pleine représentation.
  Future<Set<String>> getBoardRelativePaths(int boardId) async {
    final rows = await _database.customSelect(
      'SELECT DISTINCT s.relative_path AS path FROM sounds s '
      'INNER JOIN pad_sounds ps ON ps.sound_id = s.id '
      'INNER JOIN pads p ON p.id = ps.pad_id '
      'WHERE p.board_id = ?1 AND s.relative_path IS NOT NULL',
      variables: [Variable<int>(boardId)],
      readsFrom: {_database.sounds, _database.padSounds, _database.pads},
    ).get();
    return {for (final row in rows) row.read<String>('path')};
  }

  /// Supprime tous les sons d'une bibliothèque Drive.
  Future<void> deleteSoundsByLibraryId(int libraryId) async {
    await (_database.delete(
      _database.sounds,
    )..where((s) => s.libraryId.equals(libraryId))).go();
  }

  /// Élague les sons d'une bibliothèque dont le fichier a disparu de Drive :
  /// identité forte (`driveFileId`) connue mais absente du dernier scan complet.
  ///
  /// Symétrique de l'ajout côté `syncLibrarySoundFromDriveIndex`, et aligné sur
  /// l'élagage par snapshot (`LibrarySnapshotStore`). On épargne les sons sans
  /// `driveFileId` (legacy / pas encore réconciliés) pour ne pas perdre de
  /// données par erreur — ils sont réalignés par chemin, pas élagués.
  ///
  /// À n'appeler qu'après un scan Drive RÉUSSI et COMPLET : sur une liste
  /// partielle (timeout, réseau), cet élagage supprimerait des sons encore
  /// présents. Retourne les `relativePath` des sons supprimés (non nuls) — pour
  /// que l'appelant évince aussi leurs fichiers du cache local.
  Future<List<String>> pruneLibrarySoundsAbsentFromDrive({
    required int libraryId,
    required Set<String> keptDriveFileIds,
  }) async {
    return _database.transaction(() async {
      final selectQuery = _database.select(_database.sounds)
        ..where(
          (s) => s.libraryId.equals(libraryId) & s.driveFileId.isNotNull(),
        );
      if (keptDriveFileIds.isNotEmpty) {
        // `isNotIn([])` génère un SQL fragile selon les versions de Drift : on
        // n'ajoute la clause que si la liste des survivants est non vide (sinon
        // tous les fichiers ont disparu → on supprime tous les sons à identité).
        selectQuery.where((s) => s.driveFileId.isNotIn(keptDriveFileIds.toList()));
      }

      final toPrune = await selectQuery.get();
      if (toPrune.isEmpty) return const <String>[];

      final ids = toPrune.map((s) => s.id).toList();
      await (_database.delete(_database.sounds)..where((s) => s.id.isIn(ids)))
          .go();

      return [
        for (final s in toPrune)
          if (s.relativePath != null) s.relativePath!,
      ];
    });
  }

  /// Identités fortes (`driveFileId`) des sons d'une bibliothèque.
  ///
  /// Sert au parcours incrémental à distinguer ce qui le concerne : le flux de
  /// changements Drive couvre tout ce que l'app peut voir, pas seulement cette
  /// bibliothèque.
  Future<Set<String>> getDriveFileIdsForLibrary(int libraryId) async {
    final rows = await (_database.selectOnly(_database.sounds)
          ..addColumns([_database.sounds.driveFileId])
          ..where(
            _database.sounds.libraryId.equals(libraryId) &
                _database.sounds.driveFileId.isNotNull(),
          ))
        .get();
    return {
      for (final row in rows) ?row.read(_database.sounds.driveFileId),
    };
  }

  /// Supprime les sons d'une bibliothèque dont l'identité forte figure dans
  /// [driveFileIds]. Retourne leurs `relativePath` (non nuls) pour que
  /// l'appelant évince aussi leurs fichiers du cache local.
  ///
  /// Suppression CIBLÉE, par opposition à [pruneLibrarySoundsAbsentFromDrive]
  /// qui procède par différence d'ensembles. C'est la seule forme admissible sur
  /// le chemin incrémental : ce dernier ne connaît que les disparitions que
  /// Drive lui a explicitement signalées, jamais l'ensemble de ce qui existe.
  Future<List<String>> deleteLibrarySoundsByDriveFileIds({
    required int libraryId,
    required Set<String> driveFileIds,
  }) async {
    if (driveFileIds.isEmpty) return const [];
    return _database.transaction(() async {
      final toDelete = await (_database.select(_database.sounds)
            ..where(
              (s) =>
                  s.libraryId.equals(libraryId) &
                  s.driveFileId.isIn(driveFileIds.toList()),
            ))
          .get();
      if (toDelete.isEmpty) return const <String>[];

      await (_database.delete(_database.sounds)
            ..where((s) => s.id.isIn(toDelete.map((s) => s.id).toList())))
          .go();

      return [
        for (final s in toDelete)
          if (s.relativePath != null) s.relativePath!,
      ];
    });
  }

  /// Supprime les sons associés à un chemin surveillé.
  Future<void> deleteSoundsForWatchedPath({
    required String path,
    required int watchedPathId,
    required bool isDirectory,
  }) async {
    if (!isDirectory) {
      await (_database.delete(
        _database.sounds,
      )..where((s) => s.filePath.equals(path))).go();
      return;
    }

    if (SafDirectoryBridge.isSafTreeUri(path)) {
      final marker = '/saf_watch/$watchedPathId/';
      final allSounds = await _database.select(_database.sounds).get();
      final soundsToDelete = allSounds.where((sound) {
        final soundPath = sound.filePath.replaceAll('\\', '/');
        return soundPath.contains(marker);
      }).toList();

      for (final sound in soundsToDelete) {
        await (_database.delete(
          _database.sounds,
        )..where((s) => s.id.equals(sound.id))).go();
      }

      final docs = await getApplicationSupportDirectory();
      final cacheDir = Directory(
        SafDirectoryBridge.cacheRootForWatchedPath(watchedPathId, docs.path),
      );
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
      return;
    }

    final directoryPath = Directory(path).path.replaceAll('\\', '/');
    final allSounds = await _database.select(_database.sounds).get();
    final soundsToDelete = allSounds.where((sound) {
      final soundPath = sound.filePath.replaceAll('\\', '/');
      return soundPath.startsWith(directoryPath);
    }).toList();

    for (final sound in soundsToDelete) {
      await (_database.delete(
        _database.sounds,
      )..where((s) => s.id.equals(sound.id))).go();
    }
  }
}
