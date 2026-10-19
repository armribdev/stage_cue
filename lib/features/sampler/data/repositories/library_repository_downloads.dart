part of 'library_repository.dart';

/// Téléchargements de masse d'une bibliothèque (progression, annulation, préchargement).
/// Méthodes de [LibraryRepository] extraites via extension dans le même `part`.
extension LibraryRepositoryDownloads on LibraryRepository {

  /// Compte les sons de la bibliothèque déjà disponibles hors ligne (fichier
  /// présent dans le cache local) sur le total. Sert d'indicateur d'état dans
  /// les paramètres — même critère de présence que [downloadAllLibraryAudio].
  Future<({int available, int total})> countDownloadedSounds(
    Library library,
  ) async {
    final sounds = await _soundDataSource.getSoundsForLibrary(library.id);
    var available = 0;
    for (final sound in sounds) {
      final relativePath = sound.relativePath;
      if (relativePath == null) continue;
      final localPath = _cacheManager.localPathFor(library, relativePath);
      if (await File(localPath).exists()) available++;
    }
    return (available: available, total: sounds.length);
  }

  /// Télécharge tous les fichiers audio non encore présents dans le cache local.
  ///
  /// La progression est publiée via [notifyListeners] ([libraryDownloadProgress])
  /// et aussi relayée à [onProgress] si fourni. L'annulation passe par
  /// [cancelLibraryDownload] (ou le [isCancelled] optionnel).
  ///
  /// Une seule passe tourne à la fois par bibliothèque : un appel concurrent (p.
  /// ex. bouton manuel pendant un pré-téléchargement auto) est un no-op — la passe
  /// en cours prendra les fichiers manquants.
  Future<int> downloadAllLibraryAudio({
    required Library library,
    void Function(IndexingProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!_downloadingLibraries.add(library.id)) return 0;
    _cancelledDownloads.remove(library.id);

    void report(IndexingProgress progress) {
      _publishDownloadProgress(library.id, progress);
      onProgress?.call(progress);
    }

    bool cancelled() =>
        isCancelled?.call() == true || _cancelledDownloads.contains(library.id);

    try {
      // Le contrat [DriveClient] suffit ici (seul `ensureCached` est appelé) :
      // pas de raison d'exiger l'implémentation Google concrète.
      //
      // Résolu à chaque fichier, JAMAIS capturé pour toute la passe : une passe
      // dure des minutes, pendant lesquelles `reconnectSilently` ou un
      // renouvellement de token remplace le client et `dispose()` l'ancien —
      // fermant son `http.Client`. Toutes les requêtes suivantes levaient alors
      // `ClientException: Client is already closed`, que `_describe` traduit en
      // « Pas de connexion » : des centaines d'échecs en rafale, annonçant une
      // panne réseau qui n'existait pas.
      if (await _ensureAnyDriveClient() == null) {
        throw StateError('Bibliothèque non connectée à Drive');
      }

      final sounds = await _soundDataSource.getSoundsForLibrary(library.id);
      final total = sounds.length;

      report(
        IndexingProgress(
          path: library.name,
          current: 0,
          total: total,
          isComplete: false,
        ),
      );

      var downloaded = 0;
      var failed = 0;
      var authExpired = false;
      var sessionLost = false;
      var processed = 0;

      // Téléchargements en parallèle borné. Un par un, une bibliothèque de
      // milliers de sons enchaînait autant d'allers-retours Drive, chacun
      // laissant la bande passante inoccupée pendant sa latence.
      //
      // Chaque tâche capture SES erreurs : `mapBounded` est « complet ou rien »,
      // et ici on veut au contraire qu'un fichier illisible n'emporte pas toute
      // la passe (c'est l'inverse de l'indexation, où un trou fait supprimer des
      // sons — ici il ne fait que laisser un son non téléchargé).
      await mapBounded(
        sounds,
        (sound) async {
          // Annulation et expiration de session : les tâches déjà en file se
          // vident sans rien faire plutôt que d'être interrompues en vol (un
          // téléchargement à moitié écrit serait un `.part` de plus à nettoyer).
          if (cancelled() || authExpired || sessionLost) return;

          final relativePath = sound.relativePath;
          try {
            if (relativePath == null) {
              throw StateError('Aucun chemin Drive associé');
            }
            final localPath = _cacheManager.localPathFor(library, relativePath);
            if (!await File(localPath).exists()) {
              // Client relu ICI, pas capturé plus haut : celui du début de passe
              // a pu être disposé entre-temps (cf. commentaire ci-dessus).
              final client = await _ensureAnyDriveClient();
              if (client == null) {
                // Session réellement perdue : inutile de faire échouer les
                // centaines de fichiers restants un par un.
                sessionLost = true;
                return;
              }
              final resolvedLocalPath = await _cacheManager.ensureCached(
                client: client,
                library: library,
                relativePath: relativePath,
                driveFileId: sound.driveFileId,
              );
              unawaited(
                _soundDataSource.syncLibrarySoundLocalPath(
                  sound.id,
                  resolvedLocalPath,
                ),
              );
              unawaited(
                _materializeSoundFileMetadataIfNeeded(
                  sound,
                  File(resolvedLocalPath),
                ),
              );
              downloaded++;
            }
          } on DriveAuthException {
            // Token révoqué/expiré : les fichiers suivants échoueraient de la
            // même façon. On lève le drapeau — les tâches restantes le voient et
            // renoncent — plutôt que de les marquer une par une en échec.
            if (!authExpired) {
              authExpired = true;
              // Gardé : `mapBounded` est « complet ou rien », donc la moindre
              // erreur qui s'échappe d'ici emporterait la passe entière et
              // sauterait le rapport final — laissant la barre de progression
              // figée alors que tout est terminé.
              try {
                await invalidateAuthSession();
              } catch (e) {
                SyncLog.warn('Invalidation de session échouée — $e');
              }
            }
          } catch (e) {
            failed++;
            SyncLog.downloadFailed(title: sound.title, error: e);
          }

          // Compteur de tâches ACHEVÉES : en parallèle, l'indice dans la liste
          // ne dit plus où en est la passe. Dart étant mono-isolate, cet
          // incrément n'a pas besoin de verrou.
          processed++;
          report(
            IndexingProgress(
              path: library.name,
              current: processed,
              total: total,
              isComplete: false,
            ),
          );
        },
        concurrency: _bulkDownloadConcurrency,
      );

      report(
        IndexingProgress(
          path: library.name,
          current: total,
          total: total,
          isComplete: true,
          error: switch ((authExpired, sessionLost, failed)) {
            (true, _, _) => 'Session Google expirée — reconnexion requise.',
            // Distinct d'une expiration : la session a été fermée sous nos
            // pieds, pas refusée par Google. Un simple relancement suffit.
            (_, true, _) => 'Connexion Drive interrompue — relancez le '
                'téléchargement.',
            (_, _, final n) when n > 0 => '$n fichier(s) ignoré(s)',
            _ => null,
          },
        ),
      );

      return downloaded;
    } finally {
      _downloadingLibraries.remove(library.id);
      _cancelledDownloads.remove(library.id);
    }
  }

  /// Pré-télécharge en arrière-plan les fichiers audio manquants d'une
  /// bibliothèque en téléchargement auto, après une indexation métadonnées-only.
  /// Best-effort : découplé de l'indexation (jamais inline), il ne doit ni la
  /// bloquer ni la faire échouer. Idempotent — [downloadAllLibraryAudio] saute
  /// les fichiers déjà présents et garantit une seule passe par bibliothèque.
  Future<void> _prefetchLibraryAudioInBackground(Library library) async {
    try {
      await downloadAllLibraryAudio(library: library);
    } catch (e) {
      SyncLog.warn(
        'Pré-téléchargement en arrière-plan échoué (${library.name}) — $e',
      );
    }
  }
}
