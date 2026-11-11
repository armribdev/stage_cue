part of 'library_repository.dart';

/// Suppression d'un son de bibliothèque Drive (décision 0035).
/// Méthodes de [LibraryRepository] extraites via extension dans le même `part`.
extension LibraryRepositorySoundDeletion on LibraryRepository {
  /// Retire le son [soundId] de la bibliothèque : fichier mis à la **corbeille**
  /// Drive (récupérable ~30 jours), puis ligne locale et fichier du cache.
  ///
  /// L'ordre est la garantie : Drive d'abord, base ensuite. Supprimer la ligne
  /// d'abord, puis échouer sur Drive (hors-ligne, dossier partagé en lecture
  /// seule), ferait revenir le son à la synchro suivante, qui ré-indexe tout ce
  /// que Drive contient. Sur échec Drive l'exception remonte et rien n'est
  /// touché en local.
  ///
  /// Les autres appareils n'ont rien à recevoir : le fichier à la corbeille leur
  /// est signalé par `listChanges` (`trashed`) ou écarté au scan complet, et
  /// leurs pads se vident par les déclencheurs de cascade (décision 0032). Ce
  /// chemin ne passe donc ni par l'élagage par différence d'ensembles ni par une
  /// publication de snapshot.
  ///
  /// Lève [ArgumentError] pour un son sans identité Drive (local/legacy : la
  /// corbeille n'a pas de sens, et un rescan le ré-indexerait) et
  /// [DriveRequestException] / [DriveAuthException] sur échec de session ou
  /// d'API.
  Future<void> deleteLibrarySound(int soundId) async {
    final sound = await _soundDataSource.getSoundById(soundId);
    if (sound == null) return; // déjà supprimé (autre passe de synchro)

    final driveFileId = sound.driveFileId;
    final libraryId = sound.libraryId;
    if (driveFileId == null || libraryId == null) {
      throw ArgumentError.value(
        soundId,
        'soundId',
        'pas un son de bibliothèque Drive',
      );
    }

    final client = await _ensureAnyDriveClient();
    if (client == null) {
      throw const DriveRequestException(
        'Connexion à Google Drive requise pour supprimer un son — '
        'reconnectez-vous depuis les paramètres.',
      );
    }
    await _withDriveClient((c) => c.trashFile(driveFileId));
    SyncLog.info('Son mis à la corbeille Drive : ${sound.title}');

    await _soundDataSource.deleteSound(soundId);

    // La ligne a disparu : le fichier téléchargé ne doit pas subsister.
    final relativePath = sound.relativePath;
    if (relativePath == null) return;
    final library = await _dataSource.getLibraryById(libraryId);
    if (library != null) {
      await _cacheManager.evictCachedFile(library, relativePath);
    }
  }
}
