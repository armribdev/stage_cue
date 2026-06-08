import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Préférences applicatives persistées hors Drift (réglages sampler, etc.).
class AppPreferences extends ChangeNotifier {
  static const _subdir = '.stagecue';
  static const _fileName = 'app_preferences.json';
  static const _keyAutoDownloadPadSounds = 'auto_download_pad_sounds';

  bool _autoDownloadPadSounds = false;
  bool _loaded = false;

  /// Télécharge automatiquement les sons ajoutés à un pad (si Drive connecté).
  bool get autoDownloadPadSounds => _autoDownloadPadSounds;

  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final file = await _preferencesFile();
    if (await file.exists()) {
      try {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _autoDownloadPadSounds = data[_keyAutoDownloadPadSounds] == true;
      } catch (_) {
        // Fichier corrompu : valeurs par défaut.
      }
    }
    _loaded = true;
  }

  Future<void> setAutoDownloadPadSounds(bool value) async {
    if (_autoDownloadPadSounds == value) return;
    _autoDownloadPadSounds = value;
    notifyListeners();
    await _save();
  }

  Future<File> _preferencesFile() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _subdir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, _fileName));
  }

  Future<void> _save() async {
    final file = await _preferencesFile();
    await file.writeAsString(
      jsonEncode({_keyAutoDownloadPadSounds: _autoDownloadPadSounds}),
    );
  }
}
