part of 'local_sound_datasource.dart';

/// Indexation des fichiers audio (local, SAF, Drive) vers la base.
/// Méthodes de [LocalSoundDataSource] extraites via extension dans le même `part`.
extension LocalSoundIndexing on LocalSoundDataSource {
  /// Indexe un fichier audio
  Future<void> indexAudioFile(File file) async {
    try {
      // Vérifier si le fichier existe déjà dans la base de données
      final existingSounds = await (_database.select(
        _database.sounds,
      )..where((s) => s.filePath.equals(file.path))).get();

      if (existingSounds.isNotEmpty) {
        // Le fichier est déjà indexé
        return;
      }

      // Extraire le nom du fichier sans extension pour le titre
      final title = p.basenameWithoutExtension(file.path);
      final metadata = await _resolveMetadataForFile(file);

      // Ajouter le fichier à la base de données
      await _database
          .into(_database.sounds)
          .insert(
            db.SoundsCompanion.insert(
              title: title,
              displayName: title,
              filePath: file.path,
              type: Value(metadata.type),
              contentHash: Value(metadata.contentHash),
              waveform: Value(metadata.waveform),
              waveformProbeGeneration: Value(metadata.waveformProbeGeneration),
            ),
          );
    } catch (e) {
      rethrow;
    }
  }

  /// Indexe un fichier audio déjà matérialisé dans le cache d'une bibliothèque.
  ///
  /// [file] est le fichier local (dans le cache de la bibliothèque), [libraryId]
  /// la bibliothèque d'appartenance et [relativePath] le chemin portable. Le son
  /// devient ainsi synchronisable entre appareils. Retourne true si un nouveau
  /// son a été créé (false si déjà présent).
  Future<bool> indexLibraryAudioFile(
    File file, {
    required int libraryId,
    required String relativePath,
  }) async {
    // Déduplication par (bibliothèque, chemin relatif).
    final existing =
        await (_database.select(_database.sounds)..where(
              (s) =>
                  s.libraryId.equals(libraryId) &
                  s.relativePath.equals(relativePath),
            ))
            .get();
    if (existing.isNotEmpty) return false;

    final title = p.basenameWithoutExtension(file.path);
    final metadata = await _resolveMetadataForFile(file);

    await _database
        .into(_database.sounds)
        .insert(
          db.SoundsCompanion.insert(
            title: title,
            displayName: title,
            filePath: file.path,
            type: Value(metadata.type),
            libraryId: Value(libraryId),
            relativePath: Value(relativePath),
            contentHash: Value(metadata.contentHash),
            waveform: Value(metadata.waveform),
          ),
        );
    return true;
  }

  /// Persiste hash et/ou type si le fichier vient d'être matérialisé.
  /// Ne modifie jamais un type déjà connu (`type != null`).
  Future<void> materializeSoundFileMetadata({
    required int soundId,
    required File file,
  }) async {
    final existing = await (_database.select(
      _database.sounds,
    )..where((s) => s.id.equals(soundId))).getSingleOrNull();
    if (existing == null) return;
    if (!await isPlausibleAudioFile(file)) return;

    if (existing.type == null) {
      final probeType = await _probeSoundTypeFromDuration(file);
      final contentHash = probeType != null
          ? await computeQuickHash(file)
          : existing.contentHash;
      final probe = probeType != null ? await extractWaveform(file.path) : null;
      await (_database.update(
        _database.sounds,
      )..where((s) => s.id.equals(soundId))).write(
        db.SoundsCompanion(
          type: Value(probeType),
          contentHash: Value(contentHash),
          waveform: Value(probe?.waveformValue),
          waveformProbeGeneration: Value(probe?.generationValue),
        ),
      );
      return;
    }

    // Type déjà connu : compléter le hash et/ou la waveform s'ils manquent.
    // La waveform n'est re-sondée que si la génération d'échec est dépassée.
    final needsHash = existing.contentHash == null;
    final needsWaveform =
        existing.waveform == null &&
        waveformNeedsProbe(existing.waveformProbeGeneration);
    if (!needsHash && !needsWaveform) return;

    final probe = needsWaveform ? await extractWaveform(file.path) : null;
    // Un échec transitoire (moteur non prêt) ne doit rien écrire : on retentera.
    final persistProbe =
        probe != null && probe.status != WaveformProbeStatus.transient;
    await (_database.update(
      _database.sounds,
    )..where((s) => s.id.equals(soundId))).write(
      db.SoundsCompanion(
        contentHash: needsHash
            ? Value(await computeQuickHash(file))
            : const Value.absent(),
        waveform: persistProbe
            ? Value(probe.waveformValue)
            : const Value.absent(),
        waveformProbeGeneration: persistProbe
            ? Value(probe.generationValue)
            : const Value.absent(),
      ),
    );
  }

  /// true si un son `(libraryId, relativePath)` existe déjà en base.
  Future<bool> hasLibrarySound({
    required int libraryId,
    required String relativePath,
  }) async {
    final existing =
        await (_database.select(_database.sounds)..where(
              (s) =>
                  s.libraryId.equals(libraryId) &
                  s.relativePath.equals(relativePath),
            ))
            .get();
    return existing.isNotEmpty;
  }

  /// Corrige le chemin relatif portable d'un son (déplacement/renommage Drive).
  Future<void> updateSoundRelativePath({
    required int soundId,
    required String relativePath,
    required String localPath,
  }) async {
    await (_database.update(
      _database.sounds,
    )..where((s) => s.id.equals(soundId))).write(
      db.SoundsCompanion(
        relativePath: Value(relativePath),
        filePath: Value(localPath),
      ),
    );
  }

  /// Met à jour le chemin local cache d'un son de bibliothèque si nécessaire.
  Future<void> syncLibrarySoundLocalPath(int soundId, String localPath) async {
    final row = await (_database.select(
      _database.sounds,
    )..where((s) => s.id.equals(soundId))).getSingleOrNull();
    if (row == null || row.filePath == localPath) return;

    await (_database.update(_database.sounds)
          ..where((s) => s.id.equals(soundId)))
        .write(db.SoundsCompanion(filePath: Value(localPath)));
  }

  /// Synchronise un son de bibliothèque avec l'index Drive.
  ///
  /// Identité forte GLOBALE : l'`driveFileId` (immuable au renommage/déplacement,
  /// unique en base toutes bibliothèques confondues) est la clé de
  /// déduplication. Ordre de résolution :
  /// 1. match `driveFileId` (global) → même fichier physique :
  ///    - s'il appartient à CETTE bibliothèque : corrige le chemin relatif/local
  ///      et le dossier s'il a bougé ;
  ///    - s'il appartient à une AUTRE bibliothèque (dossiers imbriqués liés
  ///      séparément) : on ne duplique pas et on ne réécrit pas son chemin (il
  ///      est relatif à la racine du propriétaire) ;
  /// 2. sinon match `(libraryId, relativePath)` legacy → adopte l'`driveFileId`
  ///    (backfill des sons indexés avant l'identité forte) ;
  /// 3. sinon nouveau son.
  ///
  /// Retourne `created` (un nouveau son a été inséré) et `contentChanged` (le
  /// fichier a été écrasé « en place » sur Drive — même `driveFileId`, marque de
  /// révision [driveMd5] différente). Sur `contentChanged`, la waveform et le
  /// contentHash sont réinitialisés ici (recalcul paresseux) ; l'appelant doit
  /// évincer le fichier de cache local devenu périmé. Le `type` reste inchangé
  /// (cf. audio.md : jamais recalculé hors `updateSoundType`).
  ///
  /// **Réservée aux appels ponctuels.** Ce n'est qu'une façade à une entrée sur
  /// [syncLibrarySoundsFromDriveIndex] : elle en paie donc le préchargement
  /// complet à chaque appel. L'appeler en boucle sur un scan serait quadratique
  /// — c'est la variante en masse qu'il faut. La façade existe pour qu'il n'y
  /// ait qu'UNE implémentation de ces règles de rapprochement : les faire vivre
  /// en double, c'est se garantir qu'elles divergeront.
  Future<({bool created, bool contentChanged})> syncLibrarySoundFromDriveIndex({
    required int libraryId,
    required String relativePath,
    required String localPath,
    String? driveFileId,
    String? driveMd5,
    int? folderId,
  }) async {
    final result = await syncLibrarySoundsFromDriveIndex(
      libraryId: libraryId,
      entries: [
        DriveIndexEntry(
          relativePath: relativePath,
          localPath: localPath,
          driveFileId: driveFileId,
          driveMd5: driveMd5,
          folderId: folderId,
        ),
      ],
    );
    return (
      created: result.createdCount == 1,
      contentChanged: result.contentChangedPaths.isNotEmpty,
    );
  }

  /// Variante en masse de [syncLibrarySoundFromDriveIndex] : reflète tout un lot
  /// du scan Drive en DEUX requêtes de lecture + un batch d'écriture, au lieu de
  /// 2 à 3 allers-retours par fichier.
  ///
  /// Comportement identique à la version unitaire, cas par cas — c'est la seule
  /// chose qui compte ici, la régression serait silencieuse et destructrice
  /// (l'indexation élague ensuite d'après ce qu'elle a vu). Les métadonnées des
  /// nouveaux sons sont résolues AVANT le batch : elles font des I/O fichier
  /// (probe SoLoud) qui n'ont pas leur place dans une transaction.
  Future<({int createdCount, List<String> contentChangedPaths})>
  syncLibrarySoundsFromDriveIndex({
    required int libraryId,
    required List<DriveIndexEntry> entries,
  }) async {
    if (entries.isEmpty) {
      return (createdCount: 0, contentChangedPaths: const <String>[]);
    }

    // 1. Préchargement.
    //    Identité forte : lookup GLOBAL (l'index d'unicité l'est), pour repérer
    //    un fichier possédé par une AUTRE bibliothèque — à ne ni dupliquer ni
    //    réécrire.
    final withDriveId = await (_database.select(
      _database.sounds,
    )..where((s) => s.driveFileId.isNotNull())).get();
    final byDriveFileId = {
      for (final row in withDriveId) row.driveFileId!: row,
    };
    //    Repli par chemin : limité à CETTE bibliothèque, comme l'étape 2 de la
    //    version unitaire. `putIfAbsent` reproduit son `.first` sur doublons.
    final ofLibrary = await (_database.select(
      _database.sounds,
    )..where((s) => s.libraryId.equals(libraryId))).get();
    final byRelativePath = <String, db.Sound>{};
    for (final row in ofLibrary) {
      final path = row.relativePath;
      if (path != null) byRelativePath.putIfAbsent(path, () => row);
    }

    // 2. Classement en mémoire. Aucune interférence intra-lot possible : deux
    //    fichiers d'un même scan ne peuvent partager ni un `driveFileId` (unique
    //    chez Drive) ni un `relativePath` (unique dans un dossier).
    final updates = <({int id, db.SoundsCompanion values})>[];
    final adoptions = <({int id, db.SoundsCompanion values})>[];
    final creations = <DriveIndexEntry>[];
    final contentChangedPaths = <String>[];

    for (final entry in entries) {
      final driveFileId = entry.driveFileId;
      final row = driveFileId != null ? byDriveFileId[driveFileId] : null;

      if (row != null) {
        // Fichier possédé par une autre bibliothèque (lien imbriqué).
        if (row.libraryId != libraryId) continue;

        // Édition en place : contenu écrasé à ID constant. Affirmé seulement si
        // une marque était DÉJÀ connue (sinon simple backfill) et qu'elle
        // diffère de la marque distante.
        final contentChanged =
            entry.driveMd5 != null &&
            row.driveMd5 != null &&
            row.driveMd5 != entry.driveMd5;
        if (contentChanged) contentChangedPaths.add(entry.relativePath);

        final needsWrite =
            row.relativePath != entry.relativePath ||
            row.filePath != entry.localPath ||
            row.folderId != entry.folderId ||
            row.driveMd5 != entry.driveMd5;
        if (needsWrite) {
          updates.add((
            id: row.id,
            values: db.SoundsCompanion(
              relativePath: Value(entry.relativePath),
              filePath: Value(entry.localPath),
              folderId: Value(entry.folderId),
              // Ne jamais effacer une marque connue si Drive ne la renvoie pas.
              driveMd5: entry.driveMd5 != null
                  ? Value(entry.driveMd5)
                  : const Value.absent(),
              waveform: contentChanged
                  ? const Value(null)
                  : const Value.absent(),
              // Contenu écrasé : re-sonder le nouveau contenu depuis zéro.
              waveformProbeGeneration: contentChanged
                  ? const Value(null)
                  : const Value.absent(),
              contentHash: contentChanged
                  ? const Value(null)
                  : const Value.absent(),
            ),
          ));
        }
        continue;
      }

      // Legacy : son déjà indexé par chemin, sans identité forte → adoption.
      final legacy = byRelativePath[entry.relativePath];
      if (legacy != null && legacy.driveFileId == null) {
        adoptions.add((
          id: legacy.id,
          values: db.SoundsCompanion(
            filePath: Value(entry.localPath),
            driveFileId: driveFileId != null
                ? Value(driveFileId)
                : const Value.absent(),
            driveMd5: entry.driveMd5 != null
                ? Value(entry.driveMd5)
                : const Value.absent(),
            folderId: Value(entry.folderId),
          ),
        ));
        continue;
      }

      creations.add(entry);
    }

    // 3. Métadonnées des nouveaux sons, hors transaction. Court-circuit rapide
    //    quand le fichier n'est pas encore en cache (cas normal : l'indexation
    //    est métadonnées-only), donc pas de probe SoLoud dans ce cas.
    final creationMetadata =
        <
          ({
            db_sounds.SoundType? type,
            String? contentHash,
            Uint8List? waveform,
            int? waveformProbeGeneration,
          })
        >[];
    for (final entry in creations) {
      creationMetadata.add(
        await _resolveMetadataForFile(File(entry.localPath)),
      );
    }

    // 4. Écriture : un seul batch, donc une seule transaction.
    await _database.batch((batch) {
      for (final update in [...updates, ...adoptions]) {
        batch.update(
          _database.sounds,
          update.values,
          where: (s) => s.id.equals(update.id),
        );
      }
      for (var i = 0; i < creations.length; i++) {
        final entry = creations[i];
        final metadata = creationMetadata[i];
        final title = p.basenameWithoutExtension(entry.relativePath);
        batch.insert(
          _database.sounds,
          db.SoundsCompanion.insert(
            title: title,
            displayName: title,
            filePath: entry.localPath,
            type: Value(metadata.type),
            libraryId: Value(libraryId),
            relativePath: Value(entry.relativePath),
            contentHash: Value(metadata.contentHash),
            waveform: Value(metadata.waveform),
            driveFileId: Value(entry.driveFileId),
            driveMd5: Value(entry.driveMd5),
            folderId: Value(entry.folderId),
          ),
        );
      }
    });

    return (
      createdCount: creations.length,
      contentChangedPaths: contentChangedPaths,
    );
  }

  /// Indexe tous les fichiers audio d'un dossier
  Future<int> indexDirectory(
    Directory directory, {
    void Function(IndexingProgress)? onProgress,
  }) async {
    try {
      // Vérifier que le dossier existe
      if (!await directory.exists()) {
        onProgress?.call(
          IndexingProgress(
            path: directory.path,
            current: 0,
            total: 0,
            isComplete: true,
            error: 'Le dossier n\'existe pas',
          ),
        );
        return 0;
      }

      // Notifier le début du scan
      onProgress?.call(
        IndexingProgress(
          path: directory.path,
          current: 0,
          total: 0,
          isComplete: false,
        ),
      );

      final audioFiles = await scanDirectoryForAudioFiles(directory);

      // Notifier le nombre total de fichiers trouvés
      onProgress?.call(
        IndexingProgress(
          path: directory.path,
          current: 0,
          total: audioFiles.length,
          isComplete: false,
        ),
      );

      int indexedCount = 0;
      int processedCount = 0;

      for (final file in audioFiles) {
        processedCount++;
        try {
          // Vérifier si le fichier existe déjà dans la base de données
          final existingSounds = await (_database.select(
            _database.sounds,
          )..where((s) => s.filePath.equals(file.path))).get();

          if (existingSounds.isNotEmpty) {
            // Le fichier est déjà indexé
            onProgress?.call(
              IndexingProgress(
                path: directory.path,
                current: processedCount,
                total: audioFiles.length,
                isComplete: false,
              ),
            );
            continue;
          }

          // Extraire le nom du fichier sans extension pour le titre
          final title = p.basenameWithoutExtension(file.path);
          final metadata = await _resolveMetadataForFile(file);

          // Ajouter le fichier à la base de données
          await _database
              .into(_database.sounds)
              .insert(
                db.SoundsCompanion.insert(
                  title: title,
                  displayName: title,
                  filePath: file.path,
                  type: Value(metadata.type),
                  contentHash: Value(metadata.contentHash),
                  waveform: Value(metadata.waveform),
                  waveformProbeGeneration: Value(
                    metadata.waveformProbeGeneration,
                  ),
                ),
              );
          indexedCount++;

          // Notifier la progression
          onProgress?.call(
            IndexingProgress(
              path: directory.path,
              current: processedCount,
              total: audioFiles.length,
              isComplete: false,
            ),
          );
        } catch (e) {
          // Continuer avec les autres fichiers même en cas d'erreur
          onProgress?.call(
            IndexingProgress(
              path: directory.path,
              current: processedCount,
              total: audioFiles.length,
              isComplete: false,
            ),
          );
        }
      }

      // Notifier la fin de l'indexation
      onProgress?.call(
        IndexingProgress(
          path: directory.path,
          current: processedCount,
          total: audioFiles.length,
          isComplete: true,
        ),
      );

      return indexedCount;
    } catch (e) {
      debugPrint(
        'Erreur lors de l\'indexation du dossier ${directory.path}: $e',
      );
      // Notifier l'erreur
      onProgress?.call(
        IndexingProgress(
          path: directory.path,
          current: 0,
          total: 0,
          isComplete: true,
          error: e.toString(),
        ),
      );
      rethrow;
    }
  }

  /// Indexe les fichiers audio d'un dossier via SAF (Android : Drive, stockage…).
  Future<int> indexContentTree(
    String treeUri, {
    required int watchedPathId,
    void Function(IndexingProgress)? onProgress,
  }) async {
    try {
      onProgress?.call(
        IndexingProgress(
          path: treeUri,
          current: 0,
          total: 0,
          isComplete: false,
        ),
      );

      final entries = await SafDirectoryBridge.listAudioFiles(treeUri);
      onProgress?.call(
        IndexingProgress(
          path: treeUri,
          current: 0,
          total: entries.length,
          isComplete: false,
        ),
      );

      final docs = await getApplicationSupportDirectory();
      final cacheRoot = SafDirectoryBridge.cacheRootForWatchedPath(
        watchedPathId,
        docs.path,
      );

      var indexedCount = 0;
      var processedCount = 0;

      for (final entry in entries) {
        processedCount++;
        try {
          final localPath = p.join(cacheRoot, entry.relativePath);
          final localFile = File(localPath);
          final existingSounds = await (_database.select(
            _database.sounds,
          )..where((s) => s.filePath.equals(localPath))).get();
          if (existingSounds.isNotEmpty) {
            continue;
          }

          await SafDirectoryBridge.copyToFile(
            documentUri: entry.uri,
            destinationPath: localPath,
          );
          await indexAudioFile(localFile);
          indexedCount++;
        } catch (e) {
          debugPrint(
            'Erreur lors de l\'indexation SAF de ${entry.relativePath}: $e',
          );
        }

        onProgress?.call(
          IndexingProgress(
            path: treeUri,
            current: processedCount,
            total: entries.length,
            isComplete: false,
          ),
        );
      }

      onProgress?.call(
        IndexingProgress(
          path: treeUri,
          current: processedCount,
          total: entries.length,
          isComplete: true,
        ),
      );

      return indexedCount;
    } catch (e) {
      onProgress?.call(
        IndexingProgress(
          path: treeUri,
          current: 0,
          total: 0,
          isComplete: true,
          error: e.toString(),
        ),
      );
      rethrow;
    }
  }

  /// Retourne tous les sons appartenant à une bibliothèque Drive (relativePath non nul).
  Future<List<domain.Sound>> getSoundsForLibrary(int libraryId) async {
    final rows =
        await (_database.select(_database.sounds)..where(
              (s) => s.libraryId.equals(libraryId) & s.relativePath.isNotNull(),
            ))
            .get();
    // Mapper de référence, et surtout PAS une recopie champ par champ : celle
    // qui vivait ici omettait `driveFileId`, si bien que le téléchargement de
    // masse repassait sur la résolution par NOM (fragile aux accents, doublons
    // et renommages) au lieu de l'identité forte — l'inverse de la décision
    // 0002 — en payant au passage un aller-retour Drive par segment de chemin.
    // Elle laissait aussi tomber isFavorite, lastPlayedAt,
    // waveformProbeGeneration et startOffsetMs.
    return rows.map(SoundModel.toEntity).toList();
  }
}
