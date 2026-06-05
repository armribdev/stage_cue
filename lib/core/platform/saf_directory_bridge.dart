import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Métadonnées d'affichage d'un dossier SAF (nom + chemin lisible).
class SafTreeInfo {
  final String displayName;
  final String displayPath;
  final String? driveFileId;
  final bool isGoogleDrive;

  const SafTreeInfo({
    required this.displayName,
    required this.displayPath,
    this.driveFileId,
    this.isGoogleDrive = false,
  });

  factory SafTreeInfo.fromJson(Map<String, dynamic> json) {
    return SafTreeInfo(
      displayName: json['displayName'] as String? ?? 'Dossier',
      displayPath: json['displayPath'] as String? ?? 'Dossier cloud',
      driveFileId: json['driveFileId'] as String?,
      isGoogleDrive: json['isGoogleDrive'] as bool? ?? false,
    );
  }
}

/// Résultat du sélecteur SAF natif Android.
class SafPickResult {
  final String uri;
  final String displayName;
  final String displayPath;
  final String? driveFileId;
  final bool isGoogleDrive;
  final List<String> googleAccountEmails;

  const SafPickResult({
    required this.uri,
    required this.displayName,
    required this.displayPath,
    this.driveFileId,
    this.isGoogleDrive = false,
    this.googleAccountEmails = const [],
  });

  factory SafPickResult.fromJson(Map<String, dynamic> json) {
    final emails = json['googleAccountEmails'] as List<dynamic>? ?? const [];
    return SafPickResult(
      uri: json['uri'] as String,
      displayName: json['displayName'] as String? ?? 'Dossier',
      displayPath: json['displayPath'] as String? ?? 'Dossier cloud',
      driveFileId: json['driveFileId'] as String?,
      isGoogleDrive: json['isGoogleDrive'] as bool? ?? false,
      googleAccountEmails: emails.map((e) => e.toString()).toList(),
    );
  }

  SafTreeInfo get treeInfo => SafTreeInfo(
    displayName: displayName,
    displayPath: displayPath,
    driveFileId: driveFileId,
    isGoogleDrive: isGoogleDrive,
  );
}

/// Entrée audio découverte dans un arbre de documents Android (SAF).
class SafAudioEntry {
  final String uri;
  final String name;
  final String relativePath;

  const SafAudioEntry({
    required this.uri,
    required this.name,
    required this.relativePath,
  });

  factory SafAudioEntry.fromJson(Map<String, dynamic> json) {
    return SafAudioEntry(
      uri: json['uri'] as String,
      name: json['name'] as String,
      relativePath: json['relativePath'] as String,
    );
  }
}

/// Levée quand le code natif Android n'a pas été reconstruit ou chargé.
class SafDirectoryUnavailableException implements Exception {
  final String message;

  const SafDirectoryUnavailableException(this.message);

  @override
  String toString() => message;
}

/// Pont vers le sélecteur SAF natif Android (stockage local, Drive, etc.).
class SafDirectoryBridge {
  SafDirectoryBridge._();

  static const MethodChannel _channel = MethodChannel('stage_cue/saf');

  static bool get isSupported => Platform.isAndroid;

  static bool isSafTreeUri(String path) => path.startsWith('content://');

  static bool isGoogleDriveUri(String path) {
    if (!isSafTreeUri(path)) {
      return false;
    }
    final uri = Uri.tryParse(path);
    return uri?.authority == 'com.google.android.apps.docs.storage' ||
        uri?.authority == 'com.google.android.apps.docs';
  }

  /// Chemin racine du cache local pour un dossier SAF indexé.
  static String cacheRootForWatchedPath(int watchedPathId, String baseDir) {
    return '$baseDir/saf_watch/$watchedPathId';
  }

  /// Ouvre le sélecteur système et renvoie les métadonnées du dossier choisi.
  static Future<SafPickResult?> pickDirectory() async {
    if (!isSupported) {
      return null;
    }
    try {
      final raw = await _channel.invokeMethod<String>('pickDirectory');
      if (raw == null || raw.isEmpty) {
        return null;
      }

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return SafPickResult.fromJson(decoded);
    } on MissingPluginException {
      throw SafDirectoryUnavailableException(
        'Le sélecteur natif n\'est pas disponible. '
        'Arrêtez l\'app puis relancez avec « flutter run » (pas un hot reload).',
      );
    }
  }

  static Future<SafTreeInfo?> getTreeInfo(String treeUri) async {
    if (!isSupported) {
      return null;
    }

    try {
      final raw = await _channel.invokeMethod<String>(
        'getTreeInfo',
        {'treeUri': treeUri},
      );
      if (raw == null || raw.isEmpty) {
        return null;
      }

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return SafTreeInfo.fromJson(decoded);
    } on PlatformException {
      return null;
    }
  }

  static Future<List<SafAudioEntry>> listAudioFiles(String treeUri) async {
    if (!isSupported) {
      return const [];
    }

    final raw = await _channel.invokeMethod<String>(
      'listAudioFiles',
      {'treeUri': treeUri},
    );
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((entry) => SafAudioEntry.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  static Future<void> copyToFile({
    required String documentUri,
    required String destinationPath,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('SAF uniquement disponible sur Android');
    }

    await _channel.invokeMethod<void>('copyToFile', {
      'documentUri': documentUri,
      'destinationPath': destinationPath,
    });
  }
}
