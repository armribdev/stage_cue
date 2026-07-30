/// Entité métier représentant une bibliothèque portable (synchronisable Drive).
///
/// Une bibliothèque est un dossier distant (Drive) qui regroupe des fichiers
/// audio + leurs métadonnées. [localRootPath] est la matérialisation/cache
/// locale ; les sons stockent leur chemin relatif à cette racine.
class Library {
  final int id;
  final String name;
  final String localRootPath;

  /// Identifiant du dossier Drive, ou null tant que la connexion n'est pas faite.
  final String? driveFolderId;

  /// Chemin relatif dans Drive (affichage : propriétaire/chemin).
  final String? drivePath;

  /// E-mail du propriétaire du dossier Drive.
  final String? ownerEmail;

  /// Drive d'équipe parent (null = Mon Drive ou dossier partagé individuellement).
  final String? sharedDriveId;

  /// Dernière révision de snapshot DB connue localement (cf. étape sync).
  final int lastSyncedRevision;
  final DateTime? lastSyncedAt;
  final DateTime createdAt;

  /// Si true, les nouveaux fichiers indexés sont téléchargés automatiquement.
  final bool autoDownload;

  /// Jeton de reprise du parcours des changements Drive. `null` = le prochain
  /// lancement repart d'un scan complet.
  final String? driveChangeToken;

  /// Date du dernier scan COMPLET de l'arborescence Drive (horloge locale).
  final DateTime? lastFullScanAt;

  Library({
    required this.id,
    required this.name,
    required this.localRootPath,
    this.driveFolderId,
    this.drivePath,
    this.ownerEmail,
    this.sharedDriveId,
    this.lastSyncedRevision = 0,
    this.lastSyncedAt,
    required this.createdAt,
    this.autoDownload = false,
    this.driveChangeToken,
    this.lastFullScanAt,
  });

  bool get isConnectedToDrive => driveFolderId != null;
}
