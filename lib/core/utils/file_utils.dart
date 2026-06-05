import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

/// Extensions audio supportées
final List<String> audioExtensions = [
  'mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'wma', 'opus'
];

/// Vérifie si un fichier est un fichier audio
bool isAudioFile(String filePath) {
  final extension = p.extension(filePath).toLowerCase().replaceFirst('.', '');
  return audioExtensions.contains(extension);
}

/// Calcule une empreinte rapide et déterministe du contenu d'un fichier.
///
/// Combine la taille + un échantillon de début/fin via FNV-1a 64 bits. Permet
/// de réidentifier un fichier déplacé ou renommé sans lire tout le fichier
/// (suffisant pour la déduplication et la résolution de bibliothèque, pas un
/// usage cryptographique). Retourne `null` si le fichier est illisible.
Future<String?> computeQuickHash(File file, {int sampleSize = 65536}) async {
  try {
    final length = await file.length();
    const int offsetBasis = 0xcbf29ce484222325;
    const int prime = 0x100000001b3;

    int hash = offsetBasis;
    void mix(int byte) {
      hash ^= byte;
      hash = hash * prime; // débordement 64 bits (int natif Dart)
    }

    // Intègre la taille dans l'empreinte.
    for (var shift = 0; shift < 64; shift += 8) {
      mix((length >> shift) & 0xff);
    }

    final raf = await file.open();
    try {
      // Échantillon de début.
      final head = await raf.read(sampleSize);
      for (final b in head) {
        mix(b);
      }
      // Échantillon de fin (si le fichier dépasse l'échantillon de début).
      if (length > sampleSize) {
        final tailStart = length - sampleSize < sampleSize
            ? sampleSize
            : length - sampleSize;
        await raf.setPosition(tailStart);
        final tail = await raf.read(sampleSize);
        for (final b in tail) {
          mix(b);
        }
      }
    } finally {
      await raf.close();
    }

    final unsigned = hash.toUnsigned(64);
    return '${length.toRadixString(16)}-${unsigned.toRadixString(16)}';
  } catch (e) {
    debugPrint('Impossible de calculer le hash de ${file.path}: $e');
    return null;
  }
}

/// Scanne récursivement un dossier et retourne tous les fichiers audio
Future<List<File>> scanDirectoryForAudioFiles(Directory directory) async {
  final List<File> audioFiles = [];
  
  try {
    if (!await directory.exists()) {
      return audioFiles;
    }

    // Sur Android, vérifier et demander la permission MANAGE_EXTERNAL_STORAGE si nécessaire
    if (Platform.isAndroid) {
      final manageStorageStatus = await Permission.manageExternalStorage.status;
      
      if (!manageStorageStatus.isGranted) {
        await Permission.manageExternalStorage.request();
        // Note: On continue même si la permission n'est pas accordée,
        // car FilePicker peut avoir donné un accès temporaire via SAF
      }
    }
    
    // Utiliser listSync() qui fonctionne mieux sur Android
    try {
      // Récupérer toutes les entités récursivement
      List<FileSystemEntity> entities = directory.listSync(recursive: true, followLinks: false);
      
      // Filtrer pour ne garder que les fichiers
      List<File> allFiles = entities.whereType<File>().toList();
      
      // Parcourir les fichiers et trouver les fichiers audio
      for (var file in allFiles) {
        try {
          if (isAudioFile(file.path)) {
            audioFiles.add(file);
          }
        } catch (e) {
          // Ignorer les erreurs sur des fichiers individuels
        }
      }
    } catch (e) {
      // Si listSync() échoue, essayer un scan manuel récursif en fallback
      await _scanDirectoryRecursive(directory, audioFiles);
    }
  } catch (e) {
    debugPrint('Erreur lors du scan de ${directory.path}: $e');
  }
  
  return audioFiles;
}

/// Fonction récursive manuelle pour scanner un dossier et ses sous-dossiers (fallback)
Future<void> _scanDirectoryRecursive(
  Directory directory,
  List<File> audioFiles, {
  int depth = 0,
  int maxDepth = 20,
}) async {
  if (depth > maxDepth) {
    return;
  }

  try {
    if (!await directory.exists()) {
      return;
    }
    
    await for (FileSystemEntity entity in directory.list(followLinks: false)) {
      try {
        if (entity is File) {
          if (isAudioFile(entity.path)) {
            audioFiles.add(entity);
          }
        } else if (entity is Directory) {
          // Scanner récursivement les sous-dossiers
          await _scanDirectoryRecursive(entity, audioFiles, depth: depth + 1, maxDepth: maxDepth);
        }
      } catch (e) {
        // Ignorer les erreurs sur des fichiers/dossiers individuels
      }
    }
  } catch (e) {
    // Ignorer les erreurs d'accès au dossier
  }
}
