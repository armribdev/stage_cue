import 'dart:io';

import 'package:path/path.dart' as p;

import '../../features/sampler/domain/entities/sound.dart';
import '../utils/path_unicode.dart';
import 'library_sound_paths.dart';

/// Sonde « en lot » de disponibilité locale, pour les écrans qui doivent
/// répondre sur toute la bibliothèque d'un coup (recherche-éclair, filtre
/// hors-ligne).
///
/// À ne pas confondre avec `LibraryRepository.resolvePlayablePath`, qui reste
/// la voie de la LECTURE : celui-ci valide l'en-tête audio, écrit le chemin
/// résolu en base et sait déclencher un téléchargement. Le facturer par son sur
/// un millier d'entrées coûte autant de requêtes et d'accès disque — et, pour
/// chaque fichier absent, un listage complet du dossier parent via
/// [PathUnicode.canonicalizeLocalPath]. Ici on parcourt UNE fois l'arborescence
/// de chaque cache et on teste l'appartenance en mémoire.
///
/// [libraryRootPaths] associe l'id d'une bibliothèque à la racine de son cache
/// local. Un son dont la bibliothèque manque à la table est considéré
/// indisponible ; les sons purement locaux (`libraryId == null`, legacy) sont
/// testés fichier par fichier.
Future<Set<int>> probeLocallyAvailableSoundIds({
  required Iterable<Sound> sounds,
  required Map<int, String> libraryRootPaths,
}) async {
  final all = sounds.toList(growable: false);
  final available = <int>{};

  final neededLibraryIds = <int>{
    for (final sound in all)
      if (sound.libraryId != null) sound.libraryId!,
  };

  final cachedPathsByLibrary = <int, Set<String>>{};
  for (final libraryId in neededLibraryIds) {
    final rootPath = libraryRootPaths[libraryId];
    if (rootPath == null) continue;
    cachedPathsByLibrary[libraryId] = await _listCachedRelativePaths(rootPath);
  }

  final legacySounds = <Sound>[];
  for (final sound in all) {
    final libraryId = sound.libraryId;
    if (libraryId == null) {
      legacySounds.add(sound);
      continue;
    }
    final relativePath = sound.relativePath;
    if (relativePath == null || relativePath.isEmpty) continue;
    final cached = cachedPathsByLibrary[libraryId];
    if (cached == null) continue;
    if (cached.contains(
      LibrarySoundPaths.normalizeRelativePath(relativePath),
    )) {
      available.add(sound.id);
    }
  }

  // Sons legacy : pas de racine commune à parcourir, donc un test par fichier.
  // Concurrence bornée pour ne pas saturer la file d'I/O d'un coup.
  const chunkSize = 64;
  for (var i = 0; i < legacySounds.length; i += chunkSize) {
    final end = (i + chunkSize).clamp(0, legacySounds.length);
    final chunk = legacySounds.sublist(i, end);
    final exists = await Future.wait(
      chunk.map((sound) => File(sound.filePath).exists()),
    );
    for (var j = 0; j < chunk.length; j++) {
      if (exists[j]) available.add(chunk[j].id);
    }
  }

  return available;
}

/// Chemins relatifs (NFC, séparateurs `/`) des fichiers présents sous [rootPath].
///
/// Même canonicalisation que [LibrarySoundPaths.normalizeRelativePath] côté
/// base, pour que la comparaison NFC/NFD soit correcte sans repasser par le
/// disque — c'est tout l'intérêt du listage unique.
Future<Set<String>> _listCachedRelativePaths(String rootPath) async {
  final root = Directory(rootPath);
  final paths = <String>{};
  try {
    if (!await root.exists()) return paths;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: rootPath);
      // Métadonnées du cache (`.stagecue/`, `.cache_access.json`) et
      // téléchargements inachevés (`.part`) : jamais des sons jouables.
      if (relative.startsWith('.')) continue;
      if (relative.endsWith('.part')) continue;
      paths.add(PathUnicode.toNfc(relative.split(p.separator).join('/')));
    }
  } on FileSystemException {
    // Racine illisible (volume démonté, droits) : bibliothèque traitée comme
    // non disponible plutôt que d'échouer la recherche entière.
  }
  return paths;
}
