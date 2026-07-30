import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../utils/bounded_concurrency.dart';
import 'drive_client.dart';
import 'drive_models.dart';
import 'snapshot_store.dart';
import 'sync_log.dart';
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

/// Manifests lus simultanément lors d'un pull groupé. Même prudence que pour le
/// listing d'indexation : ce sont de petits GET, mais inutile de s'approcher des
/// quotas Drive pour un gain marginal.
const int _pullConcurrency = 5;

/// Nœud dossier à tirer, tel que le demande [LibrarySyncService.pullFolders].
class FolderPullTarget {
  /// Id LOCAL du nœud dossier (clé des résultats retournés).
  final int folderId;

  /// Id du dossier Drive qui héberge le `.stagecue`.
  final String folderDriveId;

  /// Révision de snapshot déjà connue localement pour ce nœud.
  final int knownRevision;

  /// Jeton de sonde du manifest au dernier pull concluant, s'il est connu (cf.
  /// [manifestProbeTokenOf]). Si le manifest distant porte toujours ce jeton, il
  /// n'a pas changé : son téléchargement est sauté.
  final String? knownProbeToken;

  const FolderPullTarget({
    required this.folderId,
    required this.folderDriveId,
    required this.knownRevision,
    this.knownProbeToken,
  });
}

/// Jeton de sonde d'un manifest distant : son `modifiedTime` sérialisé en
/// ISO-8601 UTC, ou `null` si Drive ne l'a pas renvoyé.
///
/// Passer par cette fonction des DEUX côtés (ce qu'on mémorise et ce qu'on
/// compare) : c'est ce qui garantit que la comparaison porte sur des formes
/// identiques, sans dépendre d'un fuseau ni d'une précision de stockage.
String? manifestProbeTokenOf(DriveFile manifestFile) =>
    manifestFile.modifiedTime?.toUtc().toIso8601String();

/// Issue d'un pull par-dossier, accompagnée de quoi rafraîchir le cache de
/// sonde de l'appelant.
class FolderPullResult {
  final PullOutcome outcome;

  /// Jeton de sonde observé pendant cette passe. À mémoriser tel quel quand
  /// l'issue est concluante ([PullStaged] ou [PullUpToDate]) ; `null` quand il
  /// n'y a rien de fiable à mémoriser (pas de manifest distant, fusion ratée, ou
  /// Drive n'a pas renvoyé la date).
  final String? probeToken;

  /// Vrai si le manifest n'a même pas été téléchargé, son jeton de sonde étant
  /// inchangé. C'est la mesure directe de l'efficacité de la sonde : si ce
  /// drapeau ne se lève jamais, le pull retélécharge tous les manifests à chaque
  /// lancement et l'optimisation ne sert à rien.
  final bool skippedByProbe;

  const FolderPullResult(
    this.outcome, {
    this.probeToken,
    this.skippedByProbe = false,
  });
}

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
      // Création directe, sans chercher un homonyme au préalable : le nom porte
      // un UUID fraîchement tiré, donc la recherche ne pourrait par construction
      // rien trouver. C'était un aller-retour Drive garanti inutile à chaque
      // sauvegarde.
      await client.uploadFile(
        name: snapshotName,
        parentId: stageId,
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
      //
      // Cette lecture reste une VRAIE recherche : c'est elle qui doit voir un
      // manifest apparu entre-temps, y compris publié par un appareil qui n'en
      // avait posé aucun. L'optimiser en relisant un id mémorisé plus haut
      // ferait manquer exactement le cas qu'elle existe pour détecter.
      final currentEntry =
          await _readManifestEntry(client, stageId, manifestFileName);
      final current = currentEntry?.manifest;
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
      // La relecture ci-dessus vient de donner l'id du manifest : on écrit
      // dessus directement au lieu de le rechercher à nouveau.
      await _writeManifest(
        client,
        stageId,
        manifestFileName,
        manifest,
        knownFile: currentEntry?.file,
      );

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
    } catch (e) {
      SyncLog.cleanupFailed(what: 'blob distant $name', error: e);
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
  ///
  /// Façade à une entrée sur [pullFolders] — une seule implémentation des règles
  /// de pull par-dossier.
  Future<PullOutcome> pullFolder({
    required DriveClient client,
    required int folderId,
    required String folderDriveId,
    required int knownRevision,
  }) async {
    final outcomes = await pullFolders(
      client: client,
      folders: [
        FolderPullTarget(
          folderId: folderId,
          folderDriveId: folderDriveId,
          knownRevision: knownRevision,
        ),
      ],
    );
    return outcomes[folderId]?.outcome ?? const PullNoRemoteSnapshot();
  }

  /// Tire les snapshots de PLUSIEURS nœuds dossier en une passe.
  ///
  /// Le pull unitaire sondait `.stagecue` puis le manifest dossier par dossier :
  /// deux allers-retours chacun avant même de savoir s'il y avait quelque chose
  /// à tirer, soit une bibliothèque de 80 dossiers qui coûtait ~240 requêtes en
  /// série à chaque lancement pour, le plus souvent, conclure « rien de neuf ».
  /// Ici, les deux sondes sont groupées et les manifests téléchargés en
  /// parallèle borné.
  ///
  /// Les FUSIONS restent strictement séquentielles : elles encadrent la
  /// transaction Drift d'un `ATTACH`/`DETACH` sur la base partagée, que deux
  /// fusions concurrentes feraient entrer en collision (cf. décision 0004).
  Future<Map<int, FolderPullResult>> pullFolders({
    required DriveClient client,
    required List<FolderPullTarget> folders,
  }) async {
    final outcomes = <int, FolderPullResult>{};
    if (folders.isEmpty) return outcomes;

    // 1. Tous les `.stagecue` d'un coup.
    final stages = await client.findInFolders(
      parentIds: folders.map((f) => f.folderDriveId),
      name: _stageFolderName,
    );

    final staged = <({FolderPullTarget target, String stageId})>[];
    for (final folder in folders) {
      final stage = stages[folder.folderDriveId];
      if (stage == null) {
        // Pas de `.stagecue` : rien à comparer. On n'a rien de fiable à
        // mémoriser, et le cache éventuel doit être oublié.
        outcomes[folder.folderId] = const FolderPullResult(
          PullNoRemoteSnapshot(),
        );
        continue;
      }
      staged.add((target: folder, stageId: stage.id));
    }
    if (staged.isEmpty) return outcomes;

    // 2. Tous les manifests d'un coup. Le listing ramène leur `modifiedTime` au
    //    passage : c'est ce qui permet l'étape 3.
    final manifestFiles = await client.findInFolders(
      parentIds: staged.map((e) => e.stageId),
      name: _folderManifestFileName,
    );

    final readable = <({
      FolderPullTarget target,
      String stageId,
      String fileId,
      String? probeToken,
    })>[];
    for (final entry in staged) {
      final manifestFile = manifestFiles[entry.stageId];
      if (manifestFile == null) {
        outcomes[entry.target.folderId] = const FolderPullResult(
          PullNoRemoteSnapshot(),
        );
        continue;
      }

      // 3. Manifest inchangé depuis le dernier pull concluant → on ne le
      //    télécharge même pas. Les deux jetons comparés sortent de
      //    `manifestProbeTokenOf`, donc de la même horloge (celle de Drive) et
      //    de la même sérialisation : aucune dérive d'horloge locale ni perte de
      //    précision au stockage ne peut faire sauter une synchro légitime. Le
      //    manifest étant l'unique source de vérité sur le snapshot courant (cf.
      //    décision 0007), un manifest identique garantit un blob identique.
      final probeToken = manifestProbeTokenOf(manifestFile);
      final known = entry.target.knownProbeToken;
      if (probeToken != null && known != null && probeToken == known) {
        outcomes[entry.target.folderId] = FolderPullResult(
          const PullUpToDate(),
          probeToken: probeToken,
          skippedByProbe: true,
        );
        continue;
      }

      readable.add((
        target: entry.target,
        stageId: entry.stageId,
        fileId: manifestFile.id,
        probeToken: probeToken,
      ));
    }
    if (readable.isEmpty) return outcomes;

    // 4. Lecture des manifests restants en parallèle (idempotent, sans effet
    //    de bord).
    final manifests = await mapBounded(
      readable,
      (entry) async {
        final bytes = await client.downloadBytes(entry.fileId);
        return SyncManifest.decode(utf8.decode(bytes));
      },
      concurrency: _pullConcurrency,
    );

    // 5. Fusion, une par une.
    for (var i = 0; i < readable.length; i++) {
      final entry = readable[i];
      final manifest = manifests[i];

      if (manifest.revision <= entry.target.knownRevision) {
        outcomes[entry.target.folderId] = FolderPullResult(
          const PullUpToDate(),
          probeToken: entry.probeToken,
        );
        continue;
      }

      final outcome = await _mergeRemoteSnapshot(
        client: client,
        stageId: entry.stageId,
        manifest: manifest,
        fallbackDbFileName: _folderDbFileName,
        mergeSnapshot: (path) =>
            _snapshotStore.mergeFolderSnapshot(entry.target.folderId, path),
      );
      outcomes[entry.target.folderId] = FolderPullResult(
        outcome,
        // Une fusion ratée ou un blob introuvable ne doit RIEN mémoriser :
        // sinon le prochain pull sauterait la sonde et croirait à tort être à
        // jour, figeant le nœud sur une révision jamais fusionnée.
        probeToken: outcome is PullStaged ? entry.probeToken : null,
      );
    }

    return outcomes;
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

    return _mergeRemoteSnapshot(
      client: client,
      stageId: stage.id,
      manifest: remoteManifest,
      fallbackDbFileName: dbFileName,
      mergeSnapshot: mergeSnapshot,
    );
  }

  /// Tire le blob désigné par [manifest] et le fusionne. Appelé une fois la
  /// décision prise (révision distante strictement plus récente) — partagé par
  /// le pull unitaire et le pull groupé, pour que la résolution du blob et le
  /// nettoyage du fichier temporaire n'existent qu'en un exemplaire.
  Future<PullOutcome> _mergeRemoteSnapshot({
    required DriveClient client,
    required String stageId,
    required SyncManifest manifest,
    required String fallbackDbFileName,
    required Future<void> Function(String path) mergeSnapshot,
  }) async {
    // Le manifest désigne son snapshot par son nom unique. À défaut (manifest
    // écrit par une version antérieure), on retombe sur le nom historique.
    final dbFile = await client.findInFolder(
      parentId: stageId,
      name: manifest.dbFileName ?? fallbackDbFileName,
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
      return PullStaged(manifest.revision);
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

  /// Comme [_readManifest], mais rend aussi le FICHIER lu.
  ///
  /// Le push relit le manifest juste avant de publier (fenêtre de conflit) : cet
  /// aller-retour lui donne déjà l'id du fichier. Le renvoyer évite au
  /// [_writeManifest] qui suit de le rechercher une seconde fois pour écrire
  /// dessus, à un instant où il vient tout juste de le voir.
  Future<({DriveFile file, SyncManifest manifest})?> _readManifestEntry(
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
    return (file: file, manifest: SyncManifest.decode(utf8.decode(bytes)));
  }

  /// Écrit le manifest. [knownFile] court-circuite la recherche quand
  /// l'appelant vient de le lire — l'id d'un manifest est stable, `_putFile`
  /// le met à jour en place et ne le recrée jamais.
  Future<void> _writeManifest(
    DriveClient client,
    String stageId,
    String manifestFileName,
    SyncManifest manifest, {
    DriveFile? knownFile,
  }) async {
    final bytes = utf8.encode(manifest.encode());
    if (knownFile != null) {
      await client.updateFileContent(
        fileId: knownFile.id,
        data: Stream.value(bytes),
        length: bytes.length,
        mimeType: _jsonMimeType,
      );
      return;
    }
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
    } catch (e) {
      SyncLog.cleanupFailed(what: 'fichier temporaire $path', error: e);
      // Nettoyage best-effort : un fichier temporaire résiduel n'est pas grave.
    }
  }
}
