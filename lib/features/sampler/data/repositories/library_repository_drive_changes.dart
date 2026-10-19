part of 'library_repository.dart';

/// Synchronisation incrémentale par changes.list (ADR 0021).
/// Méthodes de [LibraryRepository] extraites via extension dans le même `part`.
extension LibraryRepositoryDriveChanges on LibraryRepository {

  Future<DriveSyncOutcome> _applyDriveChanges({
    required DriveClient client,
    required Library library,
  }) async {
    final token = library.driveChangeToken;
    if (token == null) {
      return const DriveSyncNeedsFullScan('aucun jeton de reprise');
    }
    final lastFullScan = library.lastFullScanAt;
    if (lastFullScan == null ||
        DateTime.now().difference(lastFullScan) > _fullScanInterval) {
      return const DriveSyncNeedsFullScan('rescan périodique');
    }

    // 1. Collecte de TOUTES les pages avant d'appliquer quoi que ce soit : un
    //    delta à moitié appliqué serait pire que pas de delta du tout, et on ne
    //    veut poser le nouveau jeton qu'après un succès complet.
    final changes = <DriveChange>[];
    String? newToken;
    var pageToken = token;
    try {
      while (true) {
        final page = await client.listChanges(
          pageToken: pageToken,
          sharedDriveId: library.sharedDriveId,
        );
        changes.addAll(page.changes);
        final next = page.nextPageToken;
        if (next == null) {
          newToken = page.newStartPageToken;
          break;
        }
        pageToken = next;
      }
    } on DriveChangeTokenExpiredException {
      return const DriveSyncNeedsFullScan('jeton expiré');
    }

    if (newToken == null) {
      // Drive n'a pas fourni de jeton de reprise : impossible de garantir la
      // continuité du prochain delta.
      return const DriveSyncNeedsFullScan('aucun jeton de reprise renvoyé');
    }

    // 2. Cadre de chemins : les nœuds dossier connus de CETTE bibliothèque.
    final folders = await _dataSource.getFoldersForLibrary(library.id);
    final folderByDriveId = {
      for (final f in folders) f.driveFolderId: f,
    };
    // Chemins relatifs connus, pour greffer un dossier neuf sous un parent
    // local (y compris la racine de la bibliothèque, qui n'a pas toujours de
    // nœud si aucun audio n'y a jamais été indexé).
    final folderRelativeByDriveId = <String, String>{
      for (final f in folders) f.driveFolderId: f.relativePath,
      if (library.driveFolderId != null)
        library.driveFolderId!: '',
    };
    final knownSoundIds = await _soundDataSource.getDriveFileIdsForLibrary(
      library.id,
    );

    // 3. Changements de DOSSIER.
    //    - Création d'un dossier dont le parent est dans notre cadre : on greffe
    //      le sous-arbre (listing ciblé), sans rescanner toute la bibliothèque.
    //      C'est le cas « pack ajouté sur Drive pendant la session » : la veille
    //      doit le voir, pas attendre un Actualiser / relance.
    //    - Renommage, déplacement, suppression d'un dossier déjà connu : le
    //      delta ne porte pas la descendance → scan complet (chemins faux sinon).
    final folderChanges = changes.where((c) => c.isFolder).toList();
    final newFoldersToGraft = <({String driveFolderId, String relativePath})>[];
    if (folderChanges.isNotEmpty) {
      final pendingNew = <String, ({String? parentId, String name})>{};
      for (final change in folderChanges) {
        if (change.removed) {
          if (folderRelativeByDriveId.containsKey(change.fileId) &&
              change.fileId != library.driveFolderId) {
            return const DriveSyncNeedsFullScan('changement de structure');
          }
          // Dossier hors périmètre (autre bibliothèque) : ignoré.
          continue;
        }
        if (change.fileId == library.driveFolderId) {
          // Métadonnées de la racine : hors périmètre de greffe.
          continue;
        }
        if (folderRelativeByDriveId.containsKey(change.fileId)) {
          // Dossier déjà connu qui bouge (renommage / déplacement / touch).
          return const DriveSyncNeedsFullScan('changement de structure');
        }
        final file = change.file;
        if (file == null) {
          return const DriveSyncNeedsFullScan('changement de structure');
        }
        final name = PathUnicode.toNfc(file.name);
        if (name == '.stagecue') continue;
        pendingNew[change.fileId] = (parentId: change.parentId, name: name);
      }

      // Ordonner pour greffer un parent neuf avant ses enfants (même delta).
      final resolvedNew = <String, String>{};
      var progress = true;
      while (pendingNew.isNotEmpty && progress) {
        progress = false;
        final remaining = Map<String, ({String? parentId, String name})>.of(
          pendingNew,
        );
        for (final entry in remaining.entries) {
          final parentId = entry.value.parentId;
          if (parentId == null ||
              !folderRelativeByDriveId.containsKey(parentId)) {
            continue;
          }
          final parentRel = folderRelativeByDriveId[parentId]!;
          final relativePath = parentRel.isEmpty
              ? entry.value.name
              : '$parentRel/${entry.value.name}';
          resolvedNew[entry.key] = relativePath;
          folderRelativeByDriveId[entry.key] = relativePath;
          pendingNew.remove(entry.key);
          progress = true;
        }
      }
      if (pendingNew.isNotEmpty) {
        // Parent hors cadre : indiscernable d'un dossier d'une autre
        // bibliothèque sans remonter la chaîne → scan complet.
        return const DriveSyncNeedsFullScan('changement de structure');
      }
      newFoldersToGraft.addAll([
        for (final e in resolvedNew.entries)
          (driveFolderId: e.key, relativePath: e.value),
      ]);
    }

    // Greffe : listing ciblé de chaque nouveau sous-arbre. Pas d'élagage —
    // on ne connaît toujours que ce sous-ensemble, pas la bibliothèque entière.
    final entries = <DriveIndexEntry>[];
    final seenEntryIds = <String>{};
    if (newFoldersToGraft.isNotEmpty) {
      final rootId = library.driveFolderId!;
      for (final graft in newFoldersToGraft) {
        final audioFiles = await _collectDriveAudioFiles(
          client,
          graft.driveFolderId,
          graft.relativePath,
          sharedDriveId: library.sharedDriveId,
        );
        // Inclure le dossier greffé même s'il est encore vide : le prochain
        // delta qui y dépose un fichier doit le trouver dans le cadre.
        final folderSpecs = <({String driveFolderId, String relativePath})>[
          graft,
          for (final audio in audioFiles)
            (
              driveFolderId: audio.folderDriveId,
              relativePath: audio.folderRelativePath,
            ),
        ];
        final folderIds = await _dataSource.ensureFolders(
          libraryId: library.id,
          folders: folderSpecs,
        );
        await _dataSource.ensureMemberships(
          libraryId: library.id,
          folderIds: folderIds.values,
        );
        // Recharger les nœuds pour disposer des ids locaux (cadre fichier).
        final refreshed = await _dataSource.getFoldersForLibrary(library.id);
        for (final f in refreshed) {
          folderByDriveId[f.driveFolderId] = f;
          folderRelativeByDriveId[f.driveFolderId] = f.relativePath;
        }
        // La racine reste ancrée même sans nœud local.
        folderRelativeByDriveId[rootId] = '';

        for (final audio in audioFiles) {
          if (!seenEntryIds.add(audio.driveFileId)) continue;
          final folderId = folderIds[audio.folderDriveId];
          if (folderId == null) continue;
          entries.add(DriveIndexEntry(
            relativePath: audio.relativePath,
            localPath: _cacheManager.localPathFor(library, audio.relativePath),
            driveFileId: audio.driveFileId,
            driveMd5: audio.driveMd5,
            folderId: folderId,
          ));
        }
      }
      SyncLog.trace(
        '${library.name} : greffe de ${newFoldersToGraft.length} '
        'nouveau(x) dossier(s) (${entries.length} fichier(s) listés).',
      );
    }

    // 4. Fichiers audio du delta (hors ceux déjà ramassés par la greffe).
    final removedIds = <String>{};

    for (final change in changes) {
      if (change.isFolder) continue;
      if (change.removed) {
        // Ne retenir que ce qui nous appartient : le flux de changements couvre
        // tout ce que l'app peut voir, pas seulement cette bibliothèque.
        if (knownSoundIds.contains(change.fileId)) {
          removedIds.add(change.fileId);
        }
        continue;
      }

      final file = change.file;
      if (file == null) continue;
      final name = PathUnicode.toNfc(file.name);
      if (!isAudioFile(name)) continue;
      if (seenEntryIds.contains(change.fileId)) continue;

      final parentId = change.parentId;
      // Parent = racine de la bibliothèque : pas toujours de nœud local.
      if (parentId != null &&
          parentId == library.driveFolderId &&
          !folderByDriveId.containsKey(parentId)) {
        final rootFolderIds = await _dataSource.ensureFolders(
          libraryId: library.id,
          folders: [(driveFolderId: parentId, relativePath: '')],
        );
        await _dataSource.ensureMemberships(
          libraryId: library.id,
          folderIds: rootFolderIds.values,
        );
        final refreshed = await _dataSource.getFoldersForLibrary(library.id);
        for (final f in refreshed) {
          folderByDriveId[f.driveFolderId] = f;
          folderRelativeByDriveId[f.driveFolderId] = f.relativePath;
        }
      }

      final folder = parentId != null ? folderByDriveId[parentId] : null;
      if (folder == null) {
        // Fichier audio qu'on ne sait pas situer : soit un fichier connu déplacé
        // ailleurs, soit un fichier neuf dans un dossier dont on n'a pas de
        // nœud et qui n'était pas dans ce delta, soit un fichier d'une autre
        // bibliothèque. Seul un scan complet tranche.
        //
        // Le sauter silencieusement serait pire que de rescanner : un son
        // ajouté sur Drive resterait invisible jusqu'au rescan périodique,
        // c'est-à-dire potentiellement une semaine.
        return const DriveSyncNeedsFullScan('fichier hors du cadre connu');
      }

      final relativePath = folder.relativePath.isEmpty
          ? name
          : '${folder.relativePath}/$name';
      entries.add(DriveIndexEntry(
        relativePath: relativePath,
        localPath: _cacheManager.localPathFor(library, relativePath),
        driveFileId: change.fileId,
        driveMd5: file.md5Checksum,
        folderId: folder.id,
      ));
    }

    // 5. Application. Les ajouts/modifications passent par les MÊMES règles de
    //    rapprochement que l'indexation complète (identité forte, adoption par
    //    chemin, invalidation des dérivés sur md5 changé). Pas d'élagage par
    //    différence : on ne connaît toujours que le delta (+ greffes ciblées).
    var upserted = 0;
    if (entries.isNotEmpty) {
      final result = await _soundDataSource.syncLibrarySoundsFromDriveIndex(
        libraryId: library.id,
        entries: entries,
      );
      upserted = entries.length;
      for (final relativePath in result.contentChangedPaths) {
        await _cacheManager.evictCachedFile(library, relativePath);
      }
    }

    if (removedIds.isNotEmpty) {
      final prunedPaths =
          await _soundDataSource.deleteLibrarySoundsByDriveFileIds(
        libraryId: library.id,
        driveFileIds: removedIds,
      );
      for (final relativePath in prunedPaths) {
        await _cacheManager.evictCachedFile(library, relativePath);
      }
    }

    // 6. Jeton posé en DERNIER : une interruption avant ce point fait rejouer le
    //    même delta au prochain lancement, ce qui est sans effet (les règles de
    //    rapprochement sont idempotentes). L'inverse perdrait des changements.
    await _dataSource.updateDriveChangeToken(
      id: library.id,
      driveChangeToken: newToken,
    );

    return DriveSyncApplied(upserted: upserted, removed: removedIds.length);
  }
}
