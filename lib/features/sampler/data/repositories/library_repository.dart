import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/sync/drive_client.dart';
import '../../../../core/sync/drive_models.dart';
import '../../domain/entities/library.dart';
import '../datasources/local_library_datasource.dart';

/// Orchestration des bibliothèques portables : relie l'authentification Drive
/// (infra `core/sync`) à la persistance locale (table Libraries).
///
/// Conserve la session Drive active ([activeClient]) pour les opérations de
/// synchronisation ultérieures (snapshot DB, cache audio).
class LibraryRepository {
  final LocalLibraryDataSource _dataSource;
  final DriveAuthenticator _authenticator;

  DriveClient? _activeClient;

  LibraryRepository(this._dataSource, this._authenticator);

  DriveClient? get activeClient => _activeClient;
  String? get connectedAccountEmail => _authenticator.accountEmail;
  bool get isConnected => _activeClient != null;

  Future<List<Library>> getLibraries() => _dataSource.getAllLibraries();

  /// Lance le consentement OAuth puis crée une bibliothèque : dossier Drive
  /// (réutilisé s'il existe déjà) + dossier de cache local + ligne en base.
  /// Retourne null si l'utilisateur annule la connexion.
  Future<Library?> connectAndCreateLibrary({required String name}) async {
    final client = await _authenticator.connect();
    if (client == null) return null;
    _activeClient = client;

    // Réutilise un dossier homonyme créé précédemment par l'app, sinon crée-le.
    var folder = await client.findInFolder(parentId: 'root', name: name);
    folder ??= await client.createFolder(name: name);

    final localRoot = await _createLocalRoot();
    return _dataSource.insertLibrary(
      name: name,
      localRootPath: localRoot,
      driveFolderId: folder.id,
    );
  }

  /// Reconnexion silencieuse au démarrage (réutilise une session existante).
  /// Retourne true si une session a pu être rétablie.
  Future<bool> reconnectSilently() async {
    final client = await _authenticator.connectSilently();
    if (client == null) return false;
    _activeClient = client;
    return true;
  }

  /// Liste le contenu distant d'une bibliothèque connectée à Drive.
  Future<List<DriveFile>> listLibraryContents(Library library) async {
    final client = _activeClient;
    final folderId = library.driveFolderId;
    if (client == null || folderId == null) {
      throw StateError('Bibliothèque non connectée à Drive');
    }
    return client.listFolder(folderId);
  }

  /// Ferme la session Drive et révoque la connexion du compte.
  Future<void> disconnect() async {
    _activeClient?.dispose();
    _activeClient = null;
    await _authenticator.signOut();
  }

  Future<String> _createLocalRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'libraries', const Uuid().v4()));
    await dir.create(recursive: true);
    return dir.path;
  }
}
