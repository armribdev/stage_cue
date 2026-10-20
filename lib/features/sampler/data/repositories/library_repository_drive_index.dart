part of 'library_repository.dart';

/// Indexation complète de l'arborescence Drive (métadonnées seules, ADR 0005, 0019).
/// Méthodes de [LibraryRepository] extraites via extension dans le même `part`.
extension LibraryRepositoryDriveIndex on LibraryRepository {
  Future<DriveIndexResult> _indexDriveFolder({
    required DriveClient client,
    required Library library,
    required String folderId,
    void Function(IndexingProgress)? onProgress,
  }) async {
    try {
      onProgress?.call(
        IndexingProgress(
          path: library.name,
          current: 0,
          total: 0,
          isComplete: false,
        ),
      );

      // Jeton de reprise capturé AVANT le parcours, jamais après : un fichier
      // modifié pendant le scan doit apparaître dans le PROCHAIN delta. Pris
      // après, ce changement serait absent du scan (déjà passé sur ce dossier)
      // ET du delta (antérieur au jeton) — donc perdu jusqu'au rescan
      // périodique. Best-effort : sans jeton, on reste en scan complet.
      String? startPageToken;
      try {
        startPageToken = await client.getStartPageToken(
          sharedDriveId: library.sharedDriveId,
        );
      } catch (e) {
        SyncLog.startTokenUnavailable(library: library.name, error: e);
      }

      final audioFiles = await _collectDriveAudioFiles(
        client,
        folderId,
        '',
        sharedDriveId: library.sharedDriveId,
      );
      onProgress?.call(
        IndexingProgress(
          path: library.name,
          current: 0,
          total: audioFiles.length,
          isComplete: false,
        ),
      );

      var processedCount = 0;
      var indexedCount = 0;

      // Réaligne d'abord les chemins des sons legacy (sans driveFileId) dont le
      // fichier a bougé sur Drive : ainsi la boucle les réidentifie par chemin
      // et leur adopte l'ID Drive, au lieu de créer un doublon. L'identité forte
      // (driveFileId) prend ensuite le relais pour tous les scans suivants.
      await _reconcileOrphanedSoundPaths(
        library: library,
        driveRelativePaths: audioFiles.map((e) => e.relativePath).toList(),
      );

      // Nœuds dossier propriétaires (leurs fichiers directs) : unité
      // d'appartenance et de snapshot par-dossier. Résolus en UNE fois pour tout
      // le scan — ils se comptent en dizaines quand les fichiers se comptent en
      // milliers.
      final folderIds = await _dataSource.ensureFolders(
        libraryId: library.id,
        folders: [
          for (final audio in audioFiles)
            (
              driveFolderId: audio.folderDriveId,
              relativePath: audio.folderRelativePath,
            ),
        ],
      );

      // VUE PARTAGÉE : rattache CETTE bibliothèque aux nœuds, qu'elle en soit
      // propriétaire ou simplement « invitée » (son lien recouvre un dossier
      // possédé par une autre bibliothèque). Elle voit alors les sons partagés
      // sans les dupliquer.
      await _dataSource.ensureMemberships(
        libraryId: library.id,
        folderIds: folderIds.values,
      );

      // Indexation = MÉTADONNÉES uniquement. On ne télécharge JAMAIS le fichier
      // ici : sinon un gros dossier Drive (des milliers de sons) plafonne sur le
      // timeout de lancement (cf. AutoSyncCoordinator) et seuls les premiers
      // fichiers sont indexés. Le son est inséré avec `type = null` tant que le
      // fichier n'est pas local ; le téléchargement (et le backfill du type via
      // materializeSoundFileMetadata) est découplé, lancé en arrière-plan après
      // la boucle pour les bibliothèques en téléchargement auto.
      //
      // Écriture par LOTS : un lot = une transaction. Le tout-en-un serait plus
      // rapide encore, mais laisserait la progression figée sur une grosse
      // bibliothèque, et le mode d'échec reste celui d'avant (un scan
      // interrompu laisse un index partiel, que `AutoSyncCoordinator` traite
      // déjà en sautant le pull — cf. décision 0005).
      for (var start = 0; start < audioFiles.length; start += _indexBatchSize) {
        final end = math.min(start + _indexBatchSize, audioFiles.length);
        final chunk = audioFiles.sublist(start, end);

        final result = await _soundDataSource.syncLibrarySoundsFromDriveIndex(
          libraryId: library.id,
          entries: [
            for (final audio in chunk)
              DriveIndexEntry(
                relativePath: audio.relativePath,
                localPath: _cacheManager.localPathFor(
                  library,
                  audio.relativePath,
                ),
                driveFileId: audio.driveFileId,
                driveMd5: audio.driveMd5,
                folderId: folderIds[audio.folderDriveId],
              ),
          ],
        );
        indexedCount += result.createdCount;

        // Édition « en place » sur Drive (contenu écrasé à ID constant) : le
        // fichier de cache local est périmé. La waveform et le contentHash ont
        // déjà été réinitialisés en base ; on évince le fichier pour forcer un
        // re-téléchargement. Celui-ci est découplé : il aura lieu en arrière-plan
        // (téléchargement auto ci-dessous, le fichier n'existant plus) ou à la
        // demande — jamais inline, pour ne pas plafonner l'indexation.
        for (final relativePath in result.contentChangedPaths) {
          await _cacheManager.evictCachedFile(library, relativePath);
        }

        processedCount = end;
        onProgress?.call(
          IndexingProgress(
            path: library.name,
            current: processedCount,
            total: audioFiles.length,
            isComplete: false,
          ),
        );
      }

      // Élagage symétrique de l'ajout : le scan ci-dessus est complet (listFolder
      // pagine intégralement) et n'a pu être atteint qu'après un parcours sans
      // erreur — sûr donc pour supprimer les sons dont le fichier a été retiré
      // directement sur Drive (identité forte absente du scan). Les sons legacy
      // sans driveFileId sont épargnés (réalignés par chemin, jamais élagués).
      final seenDriveIds = audioFiles.map((e) => e.driveFileId).toSet();
      final prunedCount = await pruneSoundsAbsentFromDrive(
        library: library,
        presentDriveFileIds: seenDriveIds,
      );

      SyncLog.indexFinished(
        library: library.name,
        folderCount: folderIds.length,
        fileCount: audioFiles.length,
        createdCount: indexedCount,
        prunedCount: prunedCount,
      );

      // Le scan a réussi et il est COMPLET : c'est le seul moment où l'on peut
      // affirmer que la base reflète Drive. On arme donc le parcours incrémental
      // et on réarme l'horloge du rescan périodique.
      await _dataSource.updateDriveChangeToken(
        id: library.id,
        driveChangeToken: startPageToken,
        lastFullScanAt: DateTime.now(),
      );

      onProgress?.call(
        IndexingProgress(
          path: library.name,
          current: processedCount,
          total: audioFiles.length,
          isComplete: true,
          error: null,
        ),
      );

      // Métadonnées de TOUS les fichiers désormais en base (les sons sont visibles
      // immédiatement). Si la bibliothèque est en téléchargement auto, on
      // matérialise les fichiers en ARRIÈRE-PLAN — sans bloquer ni plafonner
      // l'indexation. Le type de chaque son est renseigné à la volée par
      // materializeSoundFileMetadata au fil des téléchargements.
      if (library.autoDownload) {
        unawaited(_prefetchLibraryAudioInBackground(library));
      }

      return DriveIndexResult(
        newFileCount: indexedCount,
        presentDriveFileIds: seenDriveIds,
      );
    } catch (e) {
      // Une erreur d'auth est gérée par [_withDriveClient] (renouvellement +
      // réessai) : ne pas afficher d'état d'erreur qui clignoterait avant le
      // réessai réussi.
      if (e is! DriveAuthException) {
        onProgress?.call(
          IndexingProgress(
            path: library.name,
            current: 0,
            total: 0,
            isComplete: true,
            error: e.toString(),
          ),
        );
      }
      rethrow;
    }
  }

  /// Parcourt l'arborescence Drive et retourne tous les fichiers audio.
  ///
  /// Parcours en LARGEUR, un niveau à la fois, avec au plus [_driveListingConcurrency]
  /// listings en vol. La version antérieure descendait en profondeur d'abord et
  /// attendait chaque dossier avant de passer au suivant : sur une bibliothèque
  /// à quelques dizaines de dossiers, c'était autant d'allers-retours Drive mis
  /// bout à bout, soit l'essentiel du budget de lancement passé à attendre le
  /// réseau.
  ///
  /// **Complet ou rien.** Toute erreur de listing remonte et fait échouer le
  /// scan entier — propriété dont dépend l'élagage : `_indexDriveFolder` déduit
  /// « ce fichier n'existe plus sur Drive » de son absence du résultat, puis
  /// supprime le son ET son fichier de cache. Un parcours qui avalerait l'échec
  /// d'un dossier ne rendrait pas moins de sons : il en ferait supprimer. C'est
  /// aussi ce qui permet à `AutoSyncCoordinator` de sauter le pull d'une
  /// bibliothèque mal indexée (cf. décision 0005).
  Future<
    List<
      ({
        String relativePath,
        String driveFileId,
        String? driveMd5,
        String folderDriveId,
        String folderRelativePath,
      })
    >
  >
  _collectDriveAudioFiles(
    DriveClient client,
    String rootFolderId,
    String rootPrefix, {
    String? sharedDriveId,
  }) async {
    final results =
        <
          ({
            String relativePath,
            String driveFileId,
            String? driveMd5,
            String folderDriveId,
            String folderRelativePath,
          })
        >[];

    var level = <({String id, String prefix})>[
      (id: rootFolderId, prefix: rootPrefix),
    ];

    while (level.isNotEmpty) {
      // Un listing par dossier du niveau, en parallèle borné. `listFolder` est
      // idempotent : son réessai sur erreur transitoire est déjà assuré par
      // `_guardRetry` côté client Drive (cf. décision 0012).
      final listings = await mapBounded(
        level,
        (folder) => client.listFolder(folder.id, sharedDriveId: sharedDriveId),
        concurrency: _driveListingConcurrency,
      );

      final next = <({String id, String prefix})>[];
      for (var i = 0; i < level.length; i++) {
        final folder = level[i];
        for (final child in listings[i]) {
          // Normalise le nom en NFC dès la source : Drive peut renvoyer du NFD
          // (fichiers créés sous macOS). On stocke toujours en NFC (titre,
          // relative_path, dossier, chemin local restent cohérents — cf.
          // LibrarySoundPaths).
          final childName = PathUnicode.toNfc(child.name);
          final childPath = folder.prefix.isEmpty
              ? childName
              : '${folder.prefix}/$childName';

          if (child.isFolder) {
            if (childName == '.stagecue') continue;
            next.add((id: child.id, prefix: childPath));
          } else if (isAudioFile(childName)) {
            // On conserve l'ID Drive du fichier (identité forte) ET celui de son
            // dossier parent direct (nœud propriétaire du modèle par-dossier).
            results.add((
              relativePath: childPath,
              driveFileId: child.id,
              driveMd5: child.md5Checksum,
              folderDriveId: folder.id,
              folderRelativePath: folder.prefix,
            ));
          }
        }
      }
      level = next;
    }

    return results;
  }
}
