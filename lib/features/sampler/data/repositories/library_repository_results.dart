part of 'library_repository.dart';

/// Levée quand un son de bibliothèque n'est pas accessible localement sans
/// déclencher un téléchargement (utilisé pendant le chargement des pads).
class SoundNotAvailableLocallyException implements Exception {
  /// true = appareil hors-ligne, false = fichier non encore téléchargé.
  final bool isOffline;
  const SoundNotAvailableLocallyException({required this.isOffline});

  @override
  String toString() =>
      isOffline ? 'Son indisponible hors-ligne' : 'Son non téléchargé';
}

/// Résultat de l'initialisation d'un dossier Drive nouvellement lié.
class DriveFolderLinkInitResult {
  final bool hadRemoteSnapshot;
  final int indexedNewFiles;

  const DriveFolderLinkInitResult({
    required this.hadRemoteSnapshot,
    required this.indexedNewFiles,
  });

  /// Upload si la BDD distante n'existait pas ou si de nouveaux fichiers ont été indexés.
  bool get shouldUpload => !hadRemoteSnapshot || indexedNewFiles > 0;
}

/// Résultat d'un scan complet d'un dossier Drive.
class DriveIndexResult {
  /// Nombre de nouveaux fichiers indexés (lignes `sounds` créées).
  final int newFileCount;

  /// IDs Drive de TOUS les fichiers audio vus lors de ce scan complet. Source
  /// de vérité pour l'existence : sert à élaguer les sons disparus, y compris
  /// après un pull de snapshot périmé qui aurait pu en réinsérer un (cf.
  /// [LibraryRepository.pruneSoundsAbsentFromDrive]).
  final Set<String> presentDriveFileIds;

  const DriveIndexResult({
    required this.newFileCount,
    required this.presentDriveFileIds,
  });
}
