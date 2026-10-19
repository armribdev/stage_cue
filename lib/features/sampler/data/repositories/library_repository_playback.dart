part of 'library_repository.dart';

/// Résolution du chemin jouable d'un son, sondes de cache et de présence distante.
/// Méthodes de [LibraryRepository] extraites via extension dans le même `part`.
extension LibraryRepositoryPlayback on LibraryRepository {

  /// Efface les marqueurs de blocage local pour un son de bibliothèque (retry).
  Future<void> clearPlaybackBlockForSound(Sound sound) async {
    final libraryId = sound.libraryId;
    final rawRelativePath = sound.relativePath;
    if (libraryId == null ||
        rawRelativePath == null ||
        rawRelativePath.isEmpty) {
      return;
    }
    final relativePath =
        LibrarySoundPaths.normalizeRelativePath(rawRelativePath);
    final library = await _dataSource.getLibraryById(libraryId);
    if (library == null) return;

    final localPath = _cacheManager.localPathFor(library, relativePath);
    clearUnloadablePath(localPath);
    try {
      final stalePath =
          await PathUnicode.canonicalizeLocalPath(localPath) ?? localPath;
      final stale = File(stalePath);
      if (await stale.exists() && !await isPlausibleAudioFile(stale)) {
        await stale.delete();
      }
    } catch (e) {
      SyncLog.trace('purge du cache périmé impossible ($localPath) — $e');
    }
  }

  /// Sonde disque rapide — sans SoLoud, sans réseau, sans modifier le cache.
  Future<LocalSoundProbeResult> probeLocalCache(Sound sound) async {
    final libraryId = sound.libraryId;
    final rawRelativePath = sound.relativePath;
    if (libraryId == null ||
        rawRelativePath == null ||
        rawRelativePath.isEmpty) {
      return LocalSoundProbeResult.needsDownload;
    }

    final relativePath =
        LibrarySoundPaths.normalizeRelativePath(rawRelativePath);
    final library = await _dataSource.getLibraryById(libraryId);
    if (library == null) {
      return LocalSoundProbeResult.needsDownload;
    }

    final localPath = _cacheManager.localPathFor(library, relativePath);
    if (isKnownUnloadablePath(localPath)) {
      // Cache corrompu ou échec précédent : autoriser un nouveau téléchargement
      // si Drive est joignable plutôt que de bloquer définitivement le pad.
      final client = await _ensureDriveClient();
      if (client != null) {
        clearUnloadablePath(localPath);
        try {
          final stalePath =
              await PathUnicode.canonicalizeLocalPath(localPath) ?? localPath;
          final stale = File(stalePath);
          if (await stale.exists()) await stale.delete();
        } catch (e) {
          SyncLog.trace('purge avant re-téléchargement impossible — $e');
        }
        return LocalSoundProbeResult.needsDownload;
      }
      return LocalSoundProbeResult.missingFile;
    }

    final cachedPath =
        await PathUnicode.canonicalizeLocalPath(localPath) ?? localPath;
    final localFile = File(cachedPath);
    if (await isPlausibleAudioFile(localFile)) {
      return LocalSoundProbeResult.cached;
    }
    if (await localFile.exists()) {
      return LocalSoundProbeResult.needsDownload;
    }

    final client = await _ensureDriveClient();
    if (client == null) {
      return LocalSoundProbeResult.offline;
    }
    return LocalSoundProbeResult.needsDownload;
  }

  /// Vérifie la présence distante d'un son de bibliothèque.
  ///
  /// - `true` : fichier trouvé sur Drive ;
  /// - `false` : Drive joignable mais fichier absent ;
  /// - `null` : son hors bibliothèque ou Drive inaccessible.
  Future<bool?> probeRemotePresence(Sound sound) async {
    final libraryId = sound.libraryId;
    final rawRelativePath = sound.relativePath;
    if (libraryId == null ||
        rawRelativePath == null ||
        rawRelativePath.isEmpty) {
      return null;
    }

    // Renouvelle le token si besoin — évite un client périmé en cache mémoire.
    if (!await ensureDriveConnected()) return null;

    final client = await _ensureDriveClient();
    if (client == null) return null;

    final library = await _dataSource.getLibraryById(libraryId);
    if (library == null) return null;

    final relativePath =
        LibrarySoundPaths.normalizeRelativePath(rawRelativePath);
    try {
      return await _cacheManager
          .existsOnDrive(
            client: client,
            library: library,
            relativePath: relativePath,
            driveFileId: sound.driveFileId,
          )
          .timeout(const Duration(seconds: 10));
    } on DriveAuthException {
      await invalidateAuthSession();
      return null;
    } catch (e, stack) {
      AudioLoadLog.severe(
        'Sonde Drive échouée pour ${sound.displayName}',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// Résout le chemin local jouable d'un son.
  ///
  /// - Son legacy (hors bibliothèque) : renvoie directement [Sound.filePath].
  /// - Son de bibliothèque en cache : renvoie le chemin local.
  /// - Son de bibliothèque non encore téléchargé avec [downloadIfNeeded] false :
  ///   lève [SoundNotAvailableLocallyException].
  /// - Son de bibliothèque non encore téléchargé avec [downloadIfNeeded] true :
  ///   télécharge depuis Drive et renvoie le chemin local.
  Future<String> resolvePlayablePath(
    Sound sound, {
    bool downloadIfNeeded = true,
  }) async {
    final libraryId = sound.libraryId;
    final rawRelativePath = sound.relativePath;

    if (libraryId != null) {
      if (rawRelativePath == null || rawRelativePath.isEmpty) {
        throw SoundNotAvailableLocallyException(isOffline: false);
      }

      final relativePath =
          LibrarySoundPaths.normalizeRelativePath(rawRelativePath);
      if (relativePath != rawRelativePath) {
        final libraryForUpdate = await _dataSource.getLibraryById(libraryId);
        if (libraryForUpdate != null) {
          await _soundDataSource.updateSoundRelativePath(
            soundId: sound.id,
            relativePath: relativePath,
            localPath: _cacheManager.localPathFor(libraryForUpdate, relativePath),
          );
        }
      }

      final library = await _dataSource.getLibraryById(libraryId);
      if (library == null) {
        throw SoundNotAvailableLocallyException(isOffline: false);
      }

      final localPath = _cacheManager.localPathFor(library, relativePath);
      final cachedPath =
          await PathUnicode.canonicalizeLocalPath(localPath) ?? localPath;
      final localFile = File(cachedPath);

      if (await localFile.exists()) {
        if (await isPlausibleAudioFile(localFile)) {
          final resolvedPath = p.normalize(localFile.absolute.path);
          await _soundDataSource.syncLibrarySoundLocalPath(sound.id, resolvedPath);
          // Fire-and-forget : le backfill (hash/waveform) est un best-effort qui
          // ne doit jamais bloquer la résolution du chemin — une simple sonde de
          // disponibilité (recherche) ne doit pas attendre un décodage natif lent
          // ou en échec sur potentiellement des centaines de sons.
          unawaited(_materializeSoundFileMetadataIfNeeded(sound, localFile));
          clearUnloadablePath(localPath);
          return resolvedPath;
        }

        final corruptSize = await localFile.length();
        AudioLoadLog.corruptCacheFile(path: localPath, bytes: corruptSize);
        try {
          await localFile.delete();
        } catch (e) {
          // Corrompu ET non supprimable : le re-téléchargement ne partira pas
          // (le fichier existe toujours), donc le pad reste cassé tant que le
          // verrou dure. Distinct d'une simple corruption, déjà journalisée.
          SyncLog.warn(
            'Cache corrompu impossible à supprimer ($localPath) — le son '
            'restera indisponible : $e',
          );
        }
        markPathUnloadable(localPath);
        if (!downloadIfNeeded) {
          throw SoundNotAvailableLocallyException(isOffline: false);
        }
      }

      // Fichier absent du cache.
      var client = await _ensureDriveClient();
      if (client == null && downloadIfNeeded) {
        if (!await ensureDriveConnected()) {
          throw SoundNotAvailableLocallyException(isOffline: true);
        }
        client = await _ensureDriveClient();
      }
      if (client == null) {
        throw SoundNotAvailableLocallyException(isOffline: true);
      }
      if (!downloadIfNeeded) {
        throw SoundNotAvailableLocallyException(isOffline: false);
      }

      // Identité forte : si l'ID Drive est connu, on télécharge directement par
      // ID (robuste aux accents/renommages) sans réconciliation par nom.
      final driveFileId = sound.driveFileId;
      try {
        final reconciledPath = driveFileId != null
            ? relativePath
            : await _reconcileSoundRelativePathFromDrive(
                client: client,
                library: library,
                sound: sound,
                relativePath: relativePath,
              );

        final resolvedLocalPath = await _cacheManager.ensureCached(
          client: client,
          library: library,
          relativePath: reconciledPath,
          driveFileId: driveFileId,
        );
        final downloaded = File(resolvedLocalPath);
        if (!await downloaded.exists() ||
            !await isPlausibleAudioFile(downloaded)) {
          throw SoundNotAvailableLocallyException(isOffline: false);
        }
        final effectiveRelative = p
            .relative(
              p.normalize(resolvedLocalPath),
              from: p.normalize(library.localRootPath),
            )
            .replaceAll('\\', '/');
        if (effectiveRelative != relativePath) {
          await _soundDataSource.updateSoundRelativePath(
            soundId: sound.id,
            relativePath: effectiveRelative,
            localPath: resolvedLocalPath,
          );
        } else {
          await _soundDataSource.syncLibrarySoundLocalPath(
            sound.id,
            resolvedLocalPath,
          );
        }
        await _materializeSoundFileMetadataIfNeeded(sound, downloaded);
        clearUnloadablePath(resolvedLocalPath);
        return p.normalize(downloaded.absolute.path);
      } on DriveAuthException {
        // Token révoqué/expiré : libère la session (force un OAuth interactif au
        // prochain accès) et signale une indisponibilité, jamais un `missingFile`
        // — ce dernier passerait par `_blockSoundDriveRetry` côté sampler et
        // bloquerait le son *définitivement*, même après reconnexion.
        await invalidateAuthSession();
        throw SoundNotAvailableLocallyException(isOffline: true);
      }
    }

    final legacyPath =
        await PathUnicode.canonicalizeLocalPath(sound.filePath) ?? sound.filePath;
    final legacyFile = File(legacyPath);
    if (!await legacyFile.exists()) {
      throw SoundNotAvailableLocallyException(isOffline: false);
    }
    final length = await legacyFile.length();
    if (length <= 0) {
      throw SoundNotAvailableLocallyException(isOffline: false);
    }
    return p.normalize(legacyFile.absolute.path);
  }

  Future<void> _materializeSoundFileMetadataIfNeeded(
    Sound sound,
    File file,
  ) async {
    try {
      await _soundDataSource.materializeSoundFileMetadata(
        soundId: sound.id,
        file: file,
      );
    } catch (e) {
      debugPrint('Échec matérialisation métadonnées ${sound.title}: $e');
    }
  }

  /// Importe un fichier audio local dans une bibliothèque (upload Drive + cache)
  /// et renvoie son emplacement relatif + l'id Drive.
  Future<ImportedAudio> importAudioToLibrary({
    required Library library,
    required File source,
    required String relativePath,
  }) async {
    final client = _activeClient;
    if (client == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }
    return _cacheManager.importFile(
      client: client,
      library: library,
      source: source,
      relativePath: relativePath,
    );
  }
}
