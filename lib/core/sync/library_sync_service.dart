import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'drive_client.dart';
import 'drive_models.dart';
import 'snapshot_store.dart';
import 'sync_manifest.dart';

const String _stageFolderName = '.stagecue';
// Snapshot PAR DOSSIER (les sons directs du dossier).
const String _folderDbFileName = 'library.db';
const String _folderManifestFileName = 'manifest.json';
// Snapshot RACINE (les boards/pads de la bibliothèque). Noms DISTINCTS : un même
// dossier Drive peut être à la fois un nœud-dossier (sons) ET la racine d'une
// bibliothèque (boards) — cf. dossiers imbriqués liés séparément. Partager le
// nom écraserait un snapshot par l'autre.
const String _boardsDbFileName = 'boards.db';
const String _boardsManifestFileName = 'boards-manifest.json';
const String _sqliteMimeType = 'application/x-sqlite3';
const String _jsonMimeType = 'application/json';

/// Résultat d'un push de snapshot.
sealed class PushOutcome {
  const PushOutcome();
}

/// Push réussi : le snapshot et le manifest ont été poussés à [revision].
class PushSuccess extends PushOutcome {
  final int revision;
  const PushSuccess(this.revision);
}

/// Conflit : la révision distante a changé depuis la dernière synchro connue
/// (un autre appareil a poussé). À résoudre avant de réécraser (cf. étape 5).
class PushConflict extends PushOutcome {
  final SyncManifest remote;
  const PushConflict(this.remote);
}

/// Résultat d'un pull de snapshot.
sealed class PullOutcome {
  const PullOutcome();
}

/// Rien de plus récent côté distant : la base locale est déjà à jour. Un
/// snapshot distant EXISTE et sa révision a bien été comparée.
class PullUpToDate extends PullOutcome {
  const PullUpToDate();
}

/// Aucun snapshot n'est publié côté distant : pas de `.stagecue`, pas de
/// manifest, ou le snapshot que le manifest désigne est introuvable.
///
/// À ne surtout pas confondre avec [PullUpToDate] : ici la synchro n'a rien pu
/// comparer. L'annoncer comme « Synchronisé » ferait croire à une sauvegarde
/// distante là où le dossier a été vidé ou n'a jamais rien reçu.
class PullNoRemoteSnapshot extends PullOutcome {
  const PullNoRemoteSnapshot();
}

/// Un snapshot plus récent a été téléchargé et fusionné en-place dans la base.
class PullStaged extends PullOutcome {
  final int revision;
  const PullStaged(this.revision);
}

/// Orchestration push/pull du snapshot DB d'une bibliothèque, par-dessus un
/// [DriveClient] et un [SnapshotStore]. Aucune dépendance directe au SDK Google
/// ni à la base : entièrement testable avec des mocks.
class LibrarySyncService {
  final SnapshotStore _snapshotStore;
  final String? _deviceIdOverride;
  final Directory? _tempDirOverride;

  LibrarySyncService(
    this._snapshotStore, {
    String? deviceId,
    Directory? tempDir,
  })  : _deviceIdOverride = deviceId,
        _tempDirOverride = tempDir;

  /// Pousse l'état local vers Drive si aucun conflit de révision n'est détecté.
  Future<PushOutcome> push({
    required DriveClient client,
    required int libraryId,
    required String libraryFolderId,
    required int knownRevision,
    bool force = false,
  }) {
    return _pushSnapshot(
      client: client,
      remoteFolderId: libraryFolderId,
      dbFileName: _boardsDbFileName,
      manifestFileName: _boardsManifestFileName,
      knownRevision: knownRevision,
      force: force,
      exportSnapshot: (path) =>
          _snapshotStore.exportLibrarySnapshot(libraryId, path),
    );
  }

  /// Variante par-dossier : pousse le snapshot du nœud [folderId] dans le
  /// `.stagecue` co-localisé au dossier Drive [folderDriveId]. Chaque dossier a
  /// sa propre révision → emplacement de BDD déterministe et partagé.
  Future<PushOutcome> pushFolder({
    required DriveClient client,
    required int folderId,
    required String folderDriveId,
    required int knownRevision,
    bool force = false,
  }) {
    return _pushSnapshot(
      client: client,
      remoteFolderId: folderDriveId,
      dbFileName: _folderDbFileName,
      manifestFileName: _folderManifestFileName,
      knownRevision: knownRevision,
      force: force,
      exportSnapshot: (path) =>
          _snapshotStore.exportFolderSnapshot(folderId, path),
    );
  }

  Future<PushOutcome> _pushSnapshot({
    required DriveClient client,
    required String remoteFolderId,
    required String dbFileName,
    required String manifestFileName,
    required int knownRevision,
    required Future<int> Function(String path) exportSnapshot,
    bool force = false,
  }) async {
    final stageId = await _ensureStageFolder(client, remoteFolderId);

    final remoteManifest = await _readManifest(client, stageId, manifestFileName);
    // `force` (résolution de conflit « garder le local ») : on adopte la
    // révision distante pour l'écraser au lieu de signaler un conflit.
    if (!force &&
        remoteManifest != null &&
        remoteManifest.revision != knownRevision) {
      return PushConflict(remoteManifest);
    }

    final tempDir = await _resolveTempDir();
    final snapshotPath = _uniqueTempPath(tempDir, 'library-push');
    final length = await exportSnapshot(snapshotPath);

    // Nom UNIQUE : cet upload ne peut écraser le snapshot d'aucun autre
    // appareil. Tant que le manifest ne le désigne pas, ce blob n'est vu par
    // personne — la publication reste donc une bascule en un seul point.
    final snapshotName = _uniqueSnapshotName(dbFileName);

    try {
      await _putFile(
        client: client,
        parentId: stageId,
        name: snapshotName,
        data: File(snapshotPath).openRead(),
        length: length,
        mimeType: _sqliteMimeType,
      );

      // Re-lecture juste avant publication. L'export puis l'upload durent
      // plusieurs secondes : le manifest lu AVANT ne dit plus rien de l'état
      // courant. Drive n'expose aucune écriture conditionnelle (pas d'ETag sur
      // `files.update`), donc la séquence ne peut pas être rendue atomique. On
      // réduit la fenêtre de course à un aller-retour API, et surtout le
      // perdant abandonne SANS avoir détruit le snapshot du gagnant.
      final current = await _readManifest(client, stageId, manifestFileName);
      if (!force &&
          current != null &&
          current.revision != remoteManifest?.revision) {
        await _deleteFileIfExists(client, stageId, snapshotName);
        return PushConflict(current);
      }

      // On se base sur la révision RELUE : en mode `force` (« garder le
      // local »), cela garantit de superséder ce qui est réellement distant au
      // lieu de republier une révision déjà prise.
      final baseRevision =
          current?.revision ?? remoteManifest?.revision ?? knownRevision;
      final newRevision = baseRevision + 1;
      final manifest = SyncManifest(
        revision: newRevision,
        deviceId: await _resolveDeviceId(),
        updatedAt: DateTime.now().toUtc(),
        schemaVersion: _snapshotStore.schemaVersion,
        dbFileName: snapshotName,
      );
      await _writeManifest(client, stageId, manifestFileName, manifest);

      // Le snapshot précédent n'est plus référencé : on le retire pour que
      // `.stagecue` ne grossisse pas à chaque push. Best-effort — un résidu ne
      // compromet rien.
      final previous = current?.dbFileName ?? remoteManifest?.dbFileName;
      if (previous != null && previous != snapshotName) {
        await _deleteFileIfExists(client, stageId, previous);
      }
      return PushSuccess(newRevision);
    } finally {
      await _safeDelete(snapshotPath);
    }
  }

  /// `boards.db` → `boards-<uuid>.db`.
  String _uniqueSnapshotName(String dbFileName) {
    final base = p.basenameWithoutExtension(dbFileName);
    final ext = p.extension(dbFileName);
    return '$base-${const Uuid().v4()}$ext';
  }

  Future<void> _deleteFileIfExists(
    DriveClient client,
    String parentId,
    String name,
  ) async {
    try {
      final file = await client.findInFolder(parentId: parentId, name: name);
      if (file != null) await client.deleteFile(file.id);
    } catch (_) {
      // Ménage best-effort : un blob résiduel ne compromet pas la synchro.
    }
  }

  /// Indique si un snapshot BDD existe déjà dans le `.stagecue` du dossier — que
  /// ce soit un snapshot de sons (`library.db`) ou de boards (`boards.db`).
  Future<bool> hasRemoteSnapshot({
    required DriveClient client,
    required String libraryFolderId,
  }) async {
    final stage = await _findInFolder(client, libraryFolderId, _stageFolderName);
    if (stage == null) return false;
    // Les snapshots portant désormais un nom unique, c'est la présence d'un
    // MANIFEST qui atteste qu'un snapshot a été publié. Les noms historiques
    // restent testés pour les dossiers poussés par une version antérieure.
    for (final name in const [
      _folderManifestFileName,
      _boardsManifestFileName,
      _folderDbFileName,
      _boardsDbFileName,
    ]) {
      final found = await client.findInFolder(parentId: stage.id, name: name);
      if (found != null) return true;
    }
    return false;
  }

  /// Télécharge le snapshot distant s'il est plus récent et le fusionne
  /// immédiatement dans la base locale (périmètre : [libraryId]).
  Future<PullOutcome> pull({
    required DriveClient client,
    required int libraryId,
    required String libraryFolderId,
    required int knownRevision,
  }) {
    return _pullSnapshot(
      client: client,
      remoteFolderId: libraryFolderId,
      dbFileName: _boardsDbFileName,
      manifestFileName: _boardsManifestFileName,
      knownRevision: knownRevision,
      mergeSnapshot: (path) => _snapshotStore.mergeLibrarySnapshot(
        libraryId,
        path,
        driveFolderId: libraryFolderId,
      ),
    );
  }

  /// Variante par-dossier : tire le snapshot du `.stagecue` co-localisé au
  /// dossier Drive [folderDriveId] et le fusionne dans le nœud [folderId].
  Future<PullOutcome> pullFolder({
    required DriveClient client,
    required int folderId,
    required String folderDriveId,
    required int knownRevision,
  }) {
    return _pullSnapshot(
      client: client,
      remoteFolderId: folderDriveId,
      dbFileName: _folderDbFileName,
      manifestFileName: _folderManifestFileName,
      knownRevision: knownRevision,
      mergeSnapshot: (path) =>
          _snapshotStore.mergeFolderSnapshot(folderId, path),
    );
  }

  Future<PullOutcome> _pullSnapshot({
    required DriveClient client,
    required String remoteFolderId,
    required String dbFileName,
    required String manifestFileName,
    required int knownRevision,
    required Future<void> Function(String path) mergeSnapshot,
  }) async {
    final stage = await _findInFolder(client, remoteFolderId, _stageFolderName);
    if (stage == null) return const PullNoRemoteSnapshot();

    final remoteManifest = await _readManifest(client, stage.id, manifestFileName);
    if (remoteManifest == null) return const PullNoRemoteSnapshot();
    if (remoteManifest.revision <= knownRevision) {
      return const PullUpToDate();
    }

    // Le manifest désigne son snapshot par son nom unique. À défaut (manifest
    // écrit par une version antérieure), on retombe sur le nom historique.
    final dbFile = await client.findInFolder(
      parentId: stage.id,
      name: remoteManifest.dbFileName ?? dbFileName,
    );
    // Le manifest annonce une révision mais son snapshot est absent : distant
    // incohérent, surtout pas « à jour ».
    if (dbFile == null) return const PullNoRemoteSnapshot();

    final tempDir = await _resolveTempDir();
    final downloadPath = _uniqueTempPath(tempDir, 'library-pull');
    try {
      await client.downloadToFile(
        fileId: dbFile.id,
        destinationPath: downloadPath,
      );
      await mergeSnapshot(downloadPath);
      return PullStaged(remoteManifest.revision);
    } finally {
      await _safeDelete(downloadPath);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<String> _ensureStageFolder(
    DriveClient client,
    String libraryFolderId,
  ) async {
    final existing = await _findInFolder(
      client,
      libraryFolderId,
      _stageFolderName,
    );
    if (existing != null) return existing.id;
    final created = await client.createFolder(
      name: _stageFolderName,
      parentId: libraryFolderId,
    );
    return created.id;
  }

  Future<DriveFile?> _findInFolder(
    DriveClient client,
    String parentId,
    String name,
  ) =>
      client.findInFolder(parentId: parentId, name: name);

  Future<SyncManifest?> _readManifest(
    DriveClient client,
    String stageId,
    String manifestFileName,
  ) async {
    final file = await client.findInFolder(
      parentId: stageId,
      name: manifestFileName,
    );
    if (file == null) return null;
    final bytes = await client.downloadBytes(file.id);
    return SyncManifest.decode(utf8.decode(bytes));
  }

  Future<void> _writeManifest(
    DriveClient client,
    String stageId,
    String manifestFileName,
    SyncManifest manifest,
  ) async {
    final bytes = utf8.encode(manifest.encode());
    await _putFile(
      client: client,
      parentId: stageId,
      name: manifestFileName,
      data: Stream.value(bytes),
      length: bytes.length,
      mimeType: _jsonMimeType,
    );
  }

  /// Crée le fichier ou remplace son contenu s'il existe déjà.
  Future<void> _putFile({
    required DriveClient client,
    required String parentId,
    required String name,
    required Stream<List<int>> data,
    required int length,
    required String mimeType,
  }) async {
    final existing = await client.findInFolder(parentId: parentId, name: name);
    if (existing != null) {
      await client.updateFileContent(
        fileId: existing.id,
        data: data,
        length: length,
        mimeType: mimeType,
      );
    } else {
      await client.uploadFile(
        name: name,
        parentId: parentId,
        data: data,
        length: length,
        mimeType: mimeType,
      );
    }
  }

  /// Chemin temporaire UNIQUE par opération de synchro.
  ///
  /// Un nom fixe serait partagé par deux synchros concurrentes : le coordinateur
  /// planifie un push PAR bibliothèque connectée, et leurs anti-rebonds arrivent
  /// à échéance au même instant. La seconde écrasait alors le snapshot exporté
  /// par la première, qui téléversait le contenu de l'autre bibliothèque — et le
  /// nettoyage `finally` de l'une supprimait le fichier de l'autre en plein
  /// téléversement.
  String _uniqueTempPath(Directory dir, String prefix) =>
      p.join(dir.path, '$prefix-${const Uuid().v4()}.db');

  Future<Directory> _resolveTempDir() async {
    if (_tempDirOverride != null) return _tempDirOverride;
    return getTemporaryDirectory();
  }

  /// Identifiant d'appareil stable, persisté dans un fichier sous documents.
  Future<String> _resolveDeviceId() async {
    if (_deviceIdOverride != null) return _deviceIdOverride;
    final docs = await getApplicationSupportDirectory();
    final file = File(p.join(docs.path, 'device_id.txt'));
    if (await file.exists()) {
      final value = (await file.readAsString()).trim();
      if (value.isNotEmpty) return value;
    }
    final id = const Uuid().v4();
    await file.writeAsString(id);
    return id;
  }

  Future<void> _safeDelete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Nettoyage best-effort : un fichier temporaire résiduel n'est pas grave.
    }
  }
}
