part of 'library_repository.dart';

/// Corps de la poussée et du tirage des snapshots (ordre imposé : ADR 0003, 0008, 0020).
/// Méthodes de [LibraryRepository] extraites via extension dans le même `part`.
extension LibraryRepositoryPushPull on LibraryRepository {
  Future<PushOutcome> _pushLibrary({
    required DriveClient client,
    required Library library,
    required String rootFolderId,
    int? overrideKnownRevision,
  }) async {
    final force = overrideKnownRevision != null;
    {
      // 1. Chaque nœud dossier pousse ses sons dans SON `.stagecue` co-localisé.
      final folders = await _dataSource.getFoldersForLibrary(library.id);
      for (final folder in folders) {
        final outcome = await _syncService.pushFolder(
          client: client,
          folderId: folder.id,
          folderDriveId: folder.driveFolderId,
          knownRevision: folder.lastSyncedRevision,
          force: force,
        );
        if (outcome is PushSuccess) {
          await _dataSource.updateFolderSyncState(
            id: folder.id,
            lastSyncedRevision: outcome.revision,
            lastSyncedAt: DateTime.now(),
          );
        } else if (outcome is PushConflict) {
          return outcome; // conflit remonté au niveau bibliothèque
        }
      }

      // 2. Snapshot racine (boards + pads référençant les sons par driveFileId).
      final rootOutcome = await _syncService.push(
        client: client,
        libraryId: library.id,
        libraryFolderId: rootFolderId,
        knownRevision: overrideKnownRevision ?? library.lastSyncedRevision,
        force: force,
      );
      if (rootOutcome is PushSuccess) {
        await _dataSource.updateSyncState(
          id: library.id,
          lastSyncedRevision: rootOutcome.revision,
          lastSyncedAt: DateTime.now(),
        );
      }
      return rootOutcome;
    }
  }

  Future<PullOutcome> _pullLibrary({
    required DriveClient client,
    required Library library,
    required String rootFolderId,
  }) async {
    {
      var staged = false;
      // Révision réellement atteinte par le pull (et non celle d'avant), pour
      // que l'appelant ne reçoive pas une valeur périmée.
      var stagedRevision = library.lastSyncedRevision;

      // 1. Nœuds dossier (sons). Les nœuds locaux proviennent de l'indexation ;
      //    un appareil vierge les crée via indexDriveFolder avant que ceci ne
      //    remonte des métadonnées synchronisées.
      final folders = await _dataSource.getFoldersForLibrary(library.id);
      // Passe GROUPÉE : les sondes `.stagecue` et manifest de tous les nœuds
      // sont rassemblées, au lieu de deux allers-retours par dossier avant même
      // de savoir s'il y a quelque chose à tirer.
      final results = await _syncService.pullFolders(
        client: client,
        folders: [
          for (final folder in folders)
            FolderPullTarget(
              folderId: folder.id,
              folderDriveId: folder.driveFolderId,
              knownRevision: folder.lastSyncedRevision,
              knownProbeToken: folder.manifestProbeToken,
            ),
        ],
      );
      var skippedByProbe = 0;
      var mergedCount = 0;
      var noRemoteCount = 0;
      for (final folder in folders) {
        final result = results[folder.id];
        if (result == null) continue;

        if (result.skippedByProbe) skippedByProbe++;
        final outcome = result.outcome;
        if (outcome is PullNoRemoteSnapshot) noRemoteCount++;
        if (outcome is PullStaged) {
          mergedCount++;
          staged = true;
          stagedRevision = outcome.revision;
          await _dataSource.updateFolderSyncState(
            id: folder.id,
            lastSyncedRevision: outcome.revision,
            lastSyncedAt: DateTime.now(),
          );
        }
        // Rafraîchit la sonde APRÈS la fusion : une passe interrompue avant ce
        // point laisse le cache tel quel, donc le prochain pull resondera au
        // lieu de croire à tort que le nœud est à jour.
        await _dataSource.updateFolderManifestProbe(
          id: folder.id,
          probeToken: result.probeToken,
        );
      }

      SyncLog.pullFinished(
        library: library.name,
        probed: folders.length,
        skippedByProbe: skippedByProbe,
        merged: mergedCount,
        noRemote: noRemoteCount,
      );

      // 2. Snapshot racine (boards → recâblage par driveFileId).
      final rootOutcome = await _syncService.pull(
        client: client,
        libraryId: library.id,
        libraryFolderId: rootFolderId,
        knownRevision: library.lastSyncedRevision,
      );
      if (rootOutcome is PullStaged) {
        staged = true;
        stagedRevision = rootOutcome.revision;
        await _dataSource.updateSyncState(
          id: library.id,
          lastSyncedRevision: rootOutcome.revision,
          lastSyncedAt: DateTime.now(),
        );
      }

      if (staged) return PullStaged(stagedRevision);
      // Rien n'a été fusionné : c'est le snapshot RACINE (les boards) qui fait
      // foi pour dire si le distant est à jour ou simplement vide. Les nœuds
      // dossier, eux, peuvent légitimement n'avoir jamais été poussés.
      return rootOutcome is PullNoRemoteSnapshot
          ? const PullNoRemoteSnapshot()
          : const PullUpToDate();
    }
  }
}
