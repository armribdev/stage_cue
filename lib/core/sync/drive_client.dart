import 'drive_models.dart';

/// Abstraction d'accès à un stockage de fichiers distant.
///
/// Implémentée par [GoogleDriveClient]. Le reste de l'app dépend de cette
/// interface, ce qui permet de mocker la synchro en test et de changer de
/// fournisseur sans toucher au domaine.
abstract class DriveClient {
  /// Drives d'équipe accessibles par l'utilisateur connecté.
  Future<List<DriveSharedDrive>> listSharedDrives();

  /// Dossiers partagés individuellement avec l'utilisateur (« Partagés avec moi »).
  Future<List<DriveFile>> listSharedWithMeFolders();

  /// Liste les enfants directs d'un dossier (fichiers et sous-dossiers).
  ///
  /// [sharedDriveId] requis pour parcourir la racine d'un drive d'équipe.
  Future<List<DriveFile>> listFolder(
    String folderId, {
    String? sharedDriveId,
  });

  /// Cherche un enfant direct par nom dans un dossier. Null si absent.
  Future<DriveFile?> findInFolder({
    required String parentId,
    required String name,
    String? sharedDriveId,
  });

  /// Crée un dossier. `parentId` null = racine « My Drive ».
  Future<DriveFile> createFolder({required String name, String? parentId});

  /// Téléverse un nouveau fichier depuis un flux. Retourne le fichier créé.
  Future<DriveFile> uploadFile({
    required String name,
    required String parentId,
    required Stream<List<int>> data,
    required int length,
    String? mimeType,
  });

  /// Remplace le contenu d'un fichier existant.
  Future<DriveFile> updateFileContent({
    required String fileId,
    required Stream<List<int>> data,
    required int length,
    String? mimeType,
  });

  /// Métadonnées d'un fichier (révision, taille, md5…). Null si introuvable.
  Future<DriveFile?> getFile(
    String fileId, {
    String? sharedDriveId,
  });

  /// Télécharge le contenu complet en mémoire (réservé aux petits fichiers :
  /// manifest, snapshot DB). Pour l'audio, utiliser [downloadToFile].
  Future<List<int>> downloadBytes(String fileId);

  /// Télécharge le contenu vers un fichier local (streaming, sans tout charger
  /// en mémoire). Retourne le chemin écrit.
  Future<void> downloadToFile({
    required String fileId,
    required String destinationPath,
  });

  Future<void> deleteFile(String fileId);

  /// Libère les ressources (client HTTP authentifié).
  void dispose();
}

/// Établit une session authentifiée (OAuth) vers le stockage distant.
abstract class DriveAuthenticator {
  /// Lance le consentement interactif. Retourne null si l'utilisateur annule.
  Future<DriveClient?> connect();

  /// Tente une reconnexion silencieuse si une session existe déjà. Null sinon.
  Future<DriveClient?> connectSilently();

  Future<void> signOut();

  /// Email du compte connecté, ou null si déconnecté.
  String? get accountEmail;
}
