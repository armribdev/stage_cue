import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/disk_space.dart' as disk_space;
import '../utils/path_unicode.dart';
import 'library_sound_paths.dart';
import '../../features/sampler/domain/entities/library.dart';
import 'drive_client.dart';
import 'drive_models.dart';
import 'sync_log.dart';

/// Résultat d'un import de fichier audio dans une bibliothèque.
class ImportedAudio {
  final String relativePath;
  final String driveFileId;
  const ImportedAudio({required this.relativePath, required this.driveFileId});
}

/// Gère le cache local des fichiers audio d'une bibliothèque portable :
/// - matérialise les sons distants à la demande ([ensureCached]) ;
/// - téléverse les fichiers ajoutés ([importFile]) ;
/// - applique une éviction LRU si l'espace disque disponible passe sous
///   [minFreeDiskBytes]. Pas de plafond de taille arbitraire : le cache est
///   un mirroir complet de la bibliothèque tant que le disque le permet — voir
///   [0016](../../../docs/decisions/0016-cache-sans-plafond-garde-fou-disque.md).
///
/// Indépendant du SDK Google (passe par [DriveClient]) et de la base : repose
/// uniquement sur le système de fichiers, donc testable avec des mocks.
class AudioCacheManager {
  final int minFreeDiskBytes;
  final int Function() _clock;

  /// Mesure l'espace disque disponible sur le volume contenant un chemin
  /// donné ; `null` = mesure indisponible (jamais interprété comme disque
  /// plein). Injectable pour les tests ; par défaut, [disk_space.availableDiskBytes]
  /// (Win32 `GetDiskFreeSpaceEx` / `df` POSIX selon la plateforme).
  final Future<int?> Function(String rootPath) _availableDiskBytes;

  /// Fournit les chemins relatifs « épinglés » d'une bibliothèque : ces fichiers
  /// (favoris) ne sont jamais évincés par le LRU, même rarement lus. La scène
  /// active est, elle, protégée implicitement par la récence (sons fraîchement
  /// mis en cache). Optionnel : null = aucun épinglage (refonte UX P3).
  final Future<Set<String>> Function(Library library)? _pinnedPaths;

  /// Index LRU chargé paresseusement, indexé par racine de cache.
  final Map<String, _AccessIndex> _indices = {};

  /// Dernière sauvegarde d'index en vol, par racine de cache (cf. [_saveIndex]).
  final Map<String, Future<void>> _saveChains = {};

  static const String _accessIndexFileName = '.cache_access.json';

  AudioCacheManager({
    this.minFreeDiskBytes = 2 * 1024 * 1024 * 1024, // garde-fou : 2 Go libres
    int Function()? clock,
    Future<Set<String>> Function(Library library)? pinnedPaths,
    Future<int?> Function(String rootPath)? availableDiskBytes,
  })  : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _pinnedPaths = pinnedPaths,
        _availableDiskBytes =
            availableDiskBytes ?? disk_space.availableDiskBytes;

  /// Chemin local (dans le cache de la bibliothèque) d'un chemin relatif.
  /// Les chemins relatifs utilisent toujours `/` (portables) ; la conversion
  /// vers le séparateur de la plateforme se fait ici.
  String localPathFor(Library library, String relativePath) {
    return LibrarySoundPaths.localPathFor(library.localRootPath, relativePath);
  }

  /// Garantit la présence locale du fichier ; le télécharge depuis Drive si
  /// absent. Retourne le chemin local absolu.
  ///
  /// Si [driveFileId] est fourni (identité forte, immuable), le fichier est
  /// téléchargé directement par son ID — sans re-résolution par nom, fragile
  /// aux accents/normalisation Unicode, doublons et renommages. La résolution
  /// par nom n'est conservée qu'en repli pour les sons legacy sans ID Drive.
  Future<String> ensureCached({
    required DriveClient client,
    required Library library,
    required String relativePath,
    String? driveFileId,
  }) async {
    final normalizedPath =
        LibrarySoundPaths.normalizeRelativePath(relativePath);
    var cachePath = normalizedPath;
    final localPath = localPathFor(library, cachePath);
    final cachedPath =
        await PathUnicode.canonicalizeLocalPath(localPath) ?? localPath;
    final localFile = File(cachedPath);

    if (await localFile.exists()) {
      await _touch(library, cachePath, await localFile.length());
      return localFile.path;
    }

    // Chemin rapide et robuste : téléchargement par identité forte.
    if (driveFileId != null) {
      final downloadPath = localPathFor(library, cachePath);
      await File(downloadPath).parent.create(recursive: true);
      await client.downloadToFile(
        fileId: driveFileId,
        destinationPath: downloadPath,
      );
      final materialized =
          await PathUnicode.canonicalizeLocalPath(downloadPath) ?? downloadPath;
      final size = await File(materialized).length();
      SyncLog.trace('téléchargé (id) $cachePath — $size o');
      await _touch(library, cachePath, size);
      await _evictIfNeeded(library, protect: cachePath);
      return materialized;
    }

    var remote = await _resolveRemote(client, library, normalizedPath);
    if (remote == null) {
      final fallback = await _findFileByName(
        client,
        library,
        _nameOf(normalizedPath),
        pathHint: normalizedPath,
      );
      if (fallback != null) {
        remote = fallback.file;
        cachePath = fallback.relativePath;
      }
    }
    if (remote == null) {
      throw StateError('Fichier introuvable sur Drive : $normalizedPath');
    }

    final downloadPath = localPathFor(library, cachePath);
    await File(downloadPath).parent.create(recursive: true);
    await client.downloadToFile(fileId: remote.id, destinationPath: downloadPath);

    final materialized =
        await PathUnicode.canonicalizeLocalPath(downloadPath) ?? downloadPath;
    final size = await File(materialized).length();
    // Repli par NOM : signalé explicitement, c'est le chemin fragile (sensible
    // aux accents, doublons et renommages) et il ne devrait servir que pour les
    // sons legacy sans identité forte.
    SyncLog.trace('téléchargé (repli par nom) $cachePath — $size o');
    await _touch(library, cachePath, size);
    await _evictIfNeeded(library, protect: cachePath);
    return materialized;
  }

  /// Téléverse [source] dans la bibliothèque (Drive + copie cache local) sous
  /// [relativePath]. Crée les sous-dossiers distants au besoin.
  Future<ImportedAudio> importFile({
    required DriveClient client,
    required Library library,
    required File source,
    required String relativePath,
  }) async {
    final parentId = await _ensureRemoteFolders(
      client,
      library,
      _dirOf(relativePath),
    );
    final length = await source.length();
    final uploaded = await client.uploadFile(
      name: _nameOf(relativePath),
      parentId: parentId,
      data: source.openRead(),
      length: length,
      mimeType: _audioMimeType(relativePath),
    );

    // Copie dans le cache local (sauf si la source est déjà à destination).
    final localPath = localPathFor(library, relativePath);
    if (p.normalize(source.path) != p.normalize(localPath)) {
      final localFile = File(localPath);
      await localFile.parent.create(recursive: true);
      await source.copy(localPath);
    }
    await _touch(library, relativePath, length);
    await _evictIfNeeded(library, protect: relativePath);

    return ImportedAudio(relativePath: relativePath, driveFileId: uploaded.id);
  }

  /// Supprime les téléchargements interrompus (`*.part`) de la racine de cache.
  ///
  /// [DriveClient.downloadToFile] écrit dans un `.part` puis renomme : un échec
  /// réseau nettoie derrière lui, mais pas un process tué (OS, coupure). Ces
  /// résidus ne sont jamais renommés, donc jamais inscrits dans l'index LRU,
  /// donc jamais évincés — ils occupent le disque en pure perte, invisibles à
  /// la mesure d'espace disponible qui déclenche l'éviction. À appeler au
  /// lancement.
  ///
  /// Best-effort : une racine absente ou un fichier verrouillé n'est pas une
  /// erreur. Retourne le nombre d'octets récupérés.
  Future<int> cleanupPartialDownloads(Library library) async {
    final root = Directory(library.localRootPath);
    if (!await root.exists()) return 0;

    var reclaimed = 0;
    try {
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.part')) continue;
        try {
          final size = await entity.length();
          await entity.delete();
          reclaimed += size;
        } catch (_) {
          // Fichier verrouillé ou déjà disparu : on passe au suivant.
        }
      }
    } catch (_) {
      // Racine illisible : le ménage n'est pas critique.
    }
    return reclaimed;
  }

  /// Indique si un chemin relatif est déjà présent dans le cache local.
  Future<bool> isCached(Library library, String relativePath) async {
    final localPath = localPathFor(library, relativePath);
    return await PathUnicode.canonicalizeLocalPath(localPath) != null;
  }

  /// Vérifie si un fichier audio existe sur Drive (sans téléchargement).
  ///
  /// Si [driveFileId] est fourni, la présence est vérifiée par identité forte
  /// (fiable même pour les noms accentués) ; sinon, résolution par nom (legacy).
  Future<bool> existsOnDrive({
    required DriveClient client,
    required Library library,
    required String relativePath,
    String? driveFileId,
  }) async {
    if (driveFileId != null) {
      return await client.getFile(
            driveFileId,
            sharedDriveId: library.sharedDriveId,
          ) !=
          null;
    }
    final normalizedPath =
        LibrarySoundPaths.normalizeRelativePath(relativePath);
    if (await _resolveRemote(client, library, normalizedPath) != null) {
      return true;
    }
    final fallback = await _findFileByName(
      client,
      library,
      _nameOf(normalizedPath),
      pathHint: normalizedPath,
    );
    return fallback != null;
  }

  // ── Résolution distante ──────────────────────────────────────────────────

  /// Recherche un fichier audio par nom dans toute la bibliothèque Drive.
  ///
  /// Comparaison insensible à la casse. En cas de doublons, [pathHint] permet
  /// de choisir le chemin relatif qui correspond (insensible à la casse).
  Future<({DriveFile file, String relativePath})?> _findFileByName(
    DriveClient client,
    Library library,
    String fileName, {
    String? pathHint,
  }) async {
    final matches = <({DriveFile file, String relativePath})>[];
    await _collectFilesByName(
      client,
      library.driveFolderId!,
      '',
      fileName,
      matches,
      sharedDriveId: library.sharedDriveId,
    );
    if (matches.isEmpty) return null;
    if (matches.length == 1) return matches.first;

    if (pathHint != null) {
      final hint = pathHint.toLowerCase();
      final hinted = matches
          .where((m) => m.relativePath.toLowerCase() == hint)
          .toList();
      if (hinted.length == 1) return hinted.first;
    }
    return null;
  }

  Future<void> _collectFilesByName(
    DriveClient client,
    String folderId,
    String relativePrefix,
    String fileName,
    List<({DriveFile file, String relativePath})> matches, {
    String? sharedDriveId,
  }) async {
    final children = await client.listFolder(
      folderId,
      sharedDriveId: sharedDriveId,
    );
    for (final child in children) {
      if (child.isFolder) {
        if (child.name == '.stagecue') continue;
        final subPrefix = relativePrefix.isEmpty
            ? child.name
            : '$relativePrefix/${child.name}';
        await _collectFilesByName(
          client,
          child.id,
          subPrefix,
          fileName,
          matches,
          sharedDriveId: sharedDriveId,
        );
      } else if (_namesEqual(child.name, fileName)) {
        final relativePath = relativePrefix.isEmpty
            ? child.name
            : '$relativePrefix/${child.name}';
        matches.add((file: child, relativePath: relativePath));
      }
    }
  }

  Future<DriveFile?> _resolveRemote(
    DriveClient client,
    Library library,
    String relativePath,
  ) async {
    final segments = relativePath.split('/');
    var parentId = library.driveFolderId;
    if (parentId == null) return null;
    for (var i = 0; i < segments.length - 1; i++) {
      final folder = await _findInFolderCaseInsensitive(
        client,
        parentId: parentId!,
        name: segments[i],
        sharedDriveId: library.sharedDriveId,
      );
      if (folder == null) return null;
      parentId = folder.id;
    }
    return _findInFolderCaseInsensitive(
      client,
      parentId: parentId!,
      name: segments.last,
      sharedDriveId: library.sharedDriveId,
    );
  }

  /// Recherche exacte puis repli insensible à la casse dans le dossier parent.
  Future<DriveFile?> _findInFolderCaseInsensitive(
    DriveClient client, {
    required String parentId,
    required String name,
    String? sharedDriveId,
  }) async {
    final exact = await client.findInFolder(
      parentId: parentId,
      name: name,
      sharedDriveId: sharedDriveId,
    );
    if (exact != null) return exact;

    final children = await client.listFolder(
      parentId,
      sharedDriveId: sharedDriveId,
    );
    for (final child in children) {
      if (_namesEqual(child.name, name)) return child;
    }
    return null;
  }

  // Comparaison insensible à la casse ET à la normalisation Unicode (NFC/NFD) :
  // les noms accentués peuvent différer en forme entre Drive et la base.
  bool _namesEqual(String a, String b) =>
      PathUnicode.sameName(a.toLowerCase(), b.toLowerCase());

  Future<String> _ensureRemoteFolders(
    DriveClient client,
    Library library,
    String dir,
  ) async {
    var parentId = library.driveFolderId!;
    if (dir.isEmpty) return parentId;
    for (final segment in dir.split('/')) {
      var folder = await client.findInFolder(
        parentId: parentId,
        name: segment,
        sharedDriveId: library.sharedDriveId,
      );
      folder ??= await client.createFolder(name: segment, parentId: parentId);
      parentId = folder.id;
    }
    return parentId;
  }

  // ── Éviction LRU ─────────────────────────────────────────────────────────

  /// Évince explicitement un fichier du cache (suppression fichier + entrée
  /// LRU). Deux usages à l'indexation :
  /// - retrait du son côté Drive (élagage) — évite de laisser un fichier orphelin
  ///   sur disque et une entrée LRU fantôme (`total` surévalué → évictions
  ///   prématurées d'autres sons) ;
  /// - édition « en place » (contenu écrasé à ID constant) — force le
  ///   re-téléchargement du contenu à jour au prochain accès.
  ///
  /// Best-effort : un échec de suppression ne doit pas interrompre l'indexation.
  Future<void> evictCachedFile(Library library, String relativePath) async {
    final normalized = LibrarySoundPaths.normalizeRelativePath(relativePath);
    final localPath = localPathFor(library, normalized);
    final canonical =
        await PathUnicode.canonicalizeLocalPath(localPath) ?? localPath;
    try {
      final file = File(canonical);
      if (await file.exists()) await file.delete();
    } catch (e) {
      // Le fichier survit à la ligne en base : occupe le disque sans être
      // référencé. Non bloquant, mais c'est l'origine typique d'un cache qui
      // grossit sans raison apparente.
      SyncLog.evictionFailed(path: canonical, error: e);
      // Best-effort : un fichier non supprimable ne doit pas bloquer l'index.
    }
    final index = await _indexFor(library.localRootPath);
    // Les entrées sont désormais toujours normalisées (cf. [_indexKey]) ; on
    // retire aussi la forme brute pour purger les index écrits par les versions
    // antérieures, qui pouvaient contenir les deux.
    final removed = index.entries.remove(normalized) != null;
    final removedRaw = index.entries.remove(relativePath) != null;
    if (removed || removedRaw) {
      await _saveIndex(library.localRootPath, index);
    }
  }

  /// Toutes les entrées de l'index LRU sont indexées sous la forme NORMALISÉE.
  ///
  /// Les appelants fournissent des formes hétérogènes : chemin déjà normalisé
  /// ([ensureCached]), nom brut issu du listing Drive (repli par nom), ou chemin
  /// d'origine avec préfixe `sounds/` legacy ([importFile]). Sans ce passage
  /// obligé, un même fichier obtenait DEUX entrées, faussant la taille suivie
  /// par fichier (utile au calcul de l'espace libéré par une éviction).
  String _indexKey(String relativePath) =>
      LibrarySoundPaths.normalizeRelativePath(relativePath);

  Future<void> _touch(Library library, String relativePath, int size) async {
    final index = await _indexFor(library.localRootPath);
    index.entries[_indexKey(relativePath)] = _AccessEntry(_clock(), size);
    await _saveIndex(library.localRootPath, index);
  }

  /// Déclenche l'éviction seulement si l'espace disque réel passe sous
  /// [minFreeDiskBytes] — pas de plafond de taille de cache arbitraire (cf.
  /// [0016](../../../docs/decisions/0016-cache-sans-plafond-garde-fou-disque.md)).
  /// Une mesure indisponible (`null`, plateforme non supportée ou échec de
  /// l'appel système) est traitée comme « espace suffisant » plutôt que
  /// d'évincer à l'aveugle.
  Future<void> _evictIfNeeded(Library library, {String? protect}) async {
    final free = await _availableDiskBytes(library.localRootPath);
    if (free == null || free >= minFreeDiskBytes) return;

    final protectedKey = protect != null ? _indexKey(protect) : null;
    final index = await _indexFor(library.localRootPath);

    // Chemins épinglés : exclus de l'éviction, même peu récents.
    //
    // Ils viennent de la base sous leur forme BRUTE, alors que l'index est
    // normalisé (cf. [_indexKey]) : sans cette conversion, un favori au préfixe
    // `sounds/` legacy ou en NFD ne serait jamais reconnu comme épinglé, donc
    // évincé malgré la protection.
    final pinnedRaw = await _pinnedPaths?.call(library) ?? const <String>{};
    final pinned = pinnedRaw.map(_indexKey).toSet();

    final ordered = index.entries.entries.toList()
      ..sort((a, b) => a.value.accessedAt.compareTo(b.value.accessedAt));

    // Chaque suppression libère réellement de l'espace disque ; on simule le
    // gain cumulé plutôt que de rappeler l'OS après chaque fichier (un seul
    // appel système par passe suffit, le reste est déjà connu via la taille
    // trackée à l'écriture).
    var freed = 0;
    for (final entry in ordered) {
      if (free + freed >= minFreeDiskBytes) break;
      if (entry.key == protectedKey) continue;
      if (pinned.contains(entry.key)) continue; // épinglé : jamais évincé
      final fileToDelete = File(localPathFor(library, entry.key));
      try {
        if (await fileToDelete.exists()) await fileToDelete.delete();
      } catch (_) {
        // Best-effort : un fichier non supprimable ne doit pas bloquer.
      }
      index.entries.remove(entry.key);
      freed += entry.value.size;
    }
    await _saveIndex(library.localRootPath, index);
  }

  /// Sérialise les sauvegardes de l'index par racine de cache.
  ///
  /// [DownloadQueue] autorise deux téléchargements simultanés : leurs `_touch`
  /// terminent quasi ensemble et sauvegardaient l'index en parallèle, sur le
  /// même fichier. L'écriture n'étant pas atomique, un JSON tronqué était
  /// possible — et au rechargement l'index repart à vide (catch de
  /// [_AccessIndex.load]), donc `total = 0` : plus aucune éviction tant que
  /// l'index ne s'est pas reconstitué.
  Future<void> _saveIndex(String rootPath, _AccessIndex index) {
    final previous = _saveChains[rootPath] ?? Future<void>.value();
    final next = previous.then((_) => index.save());
    // La chaîne ne doit pas mourir sur un échec ; l'erreur reste visible pour
    // l'appelant via le future retourné.
    _saveChains[rootPath] = next.catchError((_) {});
    return next;
  }

  Future<_AccessIndex> _indexFor(String rootPath) async {
    final cached = _indices[rootPath];
    if (cached != null) return cached;
    final loaded = await _AccessIndex.load(
      p.join(rootPath, _accessIndexFileName),
    );
    _indices[rootPath] = loaded;
    return loaded;
  }

  // ── Helpers chemins/mime ─────────────────────────────────────────────────

  String _dirOf(String relativePath) {
    final idx = relativePath.lastIndexOf('/');
    return idx < 0 ? '' : relativePath.substring(0, idx);
  }

  String _nameOf(String relativePath) {
    final idx = relativePath.lastIndexOf('/');
    return idx < 0 ? relativePath : relativePath.substring(idx + 1);
  }

  String _audioMimeType(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.mp3':
        return 'audio/mpeg';
      case '.wav':
        return 'audio/wav';
      case '.m4a':
      case '.aac':
        return 'audio/aac';
      case '.ogg':
      case '.opus':
        return 'audio/ogg';
      case '.flac':
        return 'audio/flac';
      case '.wma':
        return 'audio/x-ms-wma';
      default:
        return 'application/octet-stream';
    }
  }
}

class _AccessEntry {
  final int accessedAt;
  final int size;
  const _AccessEntry(this.accessedAt, this.size);
}

/// Index LRU persisté en JSON dans la racine de cache d'une bibliothèque.
class _AccessIndex {
  final File file;
  final Map<String, _AccessEntry> entries;

  _AccessIndex(this.file, this.entries);

  static Future<_AccessIndex> load(String indexPath) async {
    final file = File(indexPath);
    if (await file.exists()) {
      try {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final raw = (json['entries'] as Map<String, dynamic>?) ?? const {};
        final entries = <String, _AccessEntry>{};
        raw.forEach((key, value) {
          final map = value as Map<String, dynamic>;
          entries[key] = _AccessEntry(
            (map['a'] as num).toInt(),
            (map['s'] as num).toInt(),
          );
        });
        return _AccessIndex(file, entries);
      } catch (e) {
        // Index corrompu : on repart d'un index vide plutôt que de planter.
        // Conséquence à ne pas taire — l'éviction perd tout son historique
        // d'accès et redevient arbitraire jusqu'à ce que l'index se reconstitue.
        SyncLog.warn(
          'Index LRU illisible ($indexPath), repart à vide — $e',
          error: e,
        );
      }
    }
    return _AccessIndex(file, {});
  }

  Future<void> save() async {
    await file.parent.create(recursive: true);
    final json = {
      'version': 1,
      'entries': entries.map(
        (key, e) => MapEntry(key, {'a': e.accessedAt, 's': e.size}),
      ),
    };
    // Écriture atomique (temp + renommage) : une interruption en pleine écriture
    // laisserait un JSON tronqué, rechargé en index VIDE — donc un budget LRU
    // remis à zéro et un cache qui grossit sans borne.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(json));
    await tmp.rename(file.path);
  }
}
