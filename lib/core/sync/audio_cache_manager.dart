import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'library_sound_paths.dart';
import '../../features/sampler/domain/entities/library.dart';
import 'drive_client.dart';
import 'drive_models.dart';

/// Résultat d'un import de fichier audio dans une bibliothèque.
class ImportedAudio {
  final String relativePath;
  final String driveFileId;
  const ImportedAudio({required this.relativePath, required this.driveFileId});
}

/// Gère le cache local des fichiers audio d'une bibliothèque portable :
/// - matérialise les sons distants à la demande ([ensureCached]) ;
/// - téléverse les fichiers ajoutés ([importFile]) ;
/// - applique une éviction LRU quand le cache dépasse [maxCacheBytes].
///
/// Indépendant du SDK Google (passe par [DriveClient]) et de la base : repose
/// uniquement sur le système de fichiers, donc testable avec des mocks.
class AudioCacheManager {
  final int maxCacheBytes;
  final int Function() _clock;

  /// Fournit les chemins relatifs « épinglés » d'une bibliothèque : ces fichiers
  /// (favoris) ne sont jamais évincés par le LRU, même rarement lus. La scène
  /// active est, elle, protégée implicitement par la récence (sons fraîchement
  /// mis en cache). Optionnel : null = aucun épinglage (refonte UX P3).
  final Future<Set<String>> Function(Library library)? _pinnedPaths;

  /// Index LRU chargé paresseusement, indexé par racine de cache.
  final Map<String, _AccessIndex> _indices = {};

  static const String _accessIndexFileName = '.cache_access.json';

  AudioCacheManager({
    this.maxCacheBytes = 2 * 1024 * 1024 * 1024, // 2 Go par défaut
    int Function()? clock,
    Future<Set<String>> Function(Library library)? pinnedPaths,
  })  : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _pinnedPaths = pinnedPaths;

  /// Chemin local (dans le cache de la bibliothèque) d'un chemin relatif.
  /// Les chemins relatifs utilisent toujours `/` (portables) ; la conversion
  /// vers le séparateur de la plateforme se fait ici.
  String localPathFor(Library library, String relativePath) {
    return LibrarySoundPaths.localPathFor(library.localRootPath, relativePath);
  }

  /// Garantit la présence locale du fichier ; le télécharge depuis Drive si
  /// absent. Retourne le chemin local absolu.
  Future<String> ensureCached({
    required DriveClient client,
    required Library library,
    required String relativePath,
  }) async {
    final localPath = localPathFor(library, relativePath);
    final localFile = File(localPath);

    if (await localFile.exists()) {
      await _touch(library, relativePath, await localFile.length());
      return localPath;
    }

    final remote = await _resolveRemote(client, library, relativePath);
    if (remote == null) {
      throw StateError('Fichier introuvable sur Drive : $relativePath');
    }
    await localFile.parent.create(recursive: true);
    await client.downloadToFile(fileId: remote.id, destinationPath: localPath);

    final size = await File(localPath).length();
    await _touch(library, relativePath, size);
    await _evictIfNeeded(library, protect: relativePath);
    return localPath;
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

  /// Indique si un chemin relatif est déjà présent dans le cache local.
  Future<bool> isCached(Library library, String relativePath) {
    return File(localPathFor(library, relativePath)).exists();
  }

  // ── Résolution distante ──────────────────────────────────────────────────

  Future<DriveFile?> _resolveRemote(
    DriveClient client,
    Library library,
    String relativePath,
  ) async {
    final segments = relativePath.split('/');
    var parentId = library.driveFolderId;
    if (parentId == null) return null;
    for (var i = 0; i < segments.length - 1; i++) {
      final folder = await client.findInFolder(
        parentId: parentId!,
        name: segments[i],
        sharedDriveId: library.sharedDriveId,
      );
      if (folder == null) return null;
      parentId = folder.id;
    }
    return client.findInFolder(
      parentId: parentId!,
      name: segments.last,
      sharedDriveId: library.sharedDriveId,
    );
  }

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

  Future<void> _touch(Library library, String relativePath, int size) async {
    final index = await _indexFor(library.localRootPath);
    index.entries[relativePath] = _AccessEntry(_clock(), size);
    await index.save();
  }

  Future<void> _evictIfNeeded(Library library, {String? protect}) async {
    final index = await _indexFor(library.localRootPath);
    var total =
        index.entries.values.fold<int>(0, (sum, e) => sum + e.size);
    if (total <= maxCacheBytes) return;

    // Favoris épinglés : exclus de l'éviction, même peu récents.
    final pinned = await _pinnedPaths?.call(library) ?? const <String>{};

    final ordered = index.entries.entries.toList()
      ..sort((a, b) => a.value.accessedAt.compareTo(b.value.accessedAt));

    for (final entry in ordered) {
      if (total <= maxCacheBytes) break;
      if (entry.key == protect) continue;
      if (pinned.contains(entry.key)) continue; // épinglé : jamais évincé
      final fileToDelete = File(localPathFor(library, entry.key));
      try {
        if (await fileToDelete.exists()) await fileToDelete.delete();
      } catch (_) {
        // Best-effort : un fichier non supprimable ne doit pas bloquer.
      }
      index.entries.remove(entry.key);
      total -= entry.value.size;
    }
    await index.save();
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
      } catch (_) {
        // Index corrompu : on repart d'un index vide plutôt que de planter.
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
    await file.writeAsString(jsonEncode(json));
  }
}
