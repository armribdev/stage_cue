import 'dart:io';
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
    print('Erreur lors du scan de ${directory.path}: $e');
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
