import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Stratégie réseau de l'application (réglage global dans Paramètres).
enum ConnectivityMode {
  /// Synchronisation Drive et téléchargements à la demande.
  connected,

  /// Spectacle sans réseau : seuls les sons en cache local sont jouables.
  liveOffline,

  /// Travail local : pas de synchro auto ni téléchargement, catalogue complet.
  offline,
}

extension ConnectivityModeUi on ConnectivityMode {
  String get label => switch (this) {
        ConnectivityMode.connected => 'Connecté',
        ConnectivityMode.liveOffline => 'Live hors ligne',
        ConnectivityMode.offline => 'Hors ligne',
      };

  String get description => switch (this) {
        ConnectivityMode.connected =>
          'Synchronisation Drive et téléchargements actifs.',
        ConnectivityMode.liveOffline =>
          'Masque les pads sans fichier local, lecture depuis le cache uniquement.',
        ConnectivityMode.offline =>
          'Pas de synchro ni téléchargement automatique, tous les pads restent visibles.',
      };

  String get storageKey => switch (this) {
        ConnectivityMode.connected => 'connected',
        ConnectivityMode.liveOffline => 'live_offline',
        ConnectivityMode.offline => 'offline',
      };

  static ConnectivityMode fromStorageKey(String? raw) => switch (raw) {
        'connected' => ConnectivityMode.connected,
        'offline' => ConnectivityMode.offline,
        _ => ConnectivityMode.liveOffline,
      };
}

/// Préférences applicatives persistées hors Drift (réglages sampler, etc.).
class AppPreferences extends ChangeNotifier {
  static const _subdir = '.stagecue';
  static const _fileName = 'app_preferences.json';
  static const _keyAutoDownloadPadSounds = 'auto_download_pad_sounds';
  static const _keyAutoDownloadDriveByDefault =
      'auto_download_drive_by_default';
  static const _keyConnectivityMode = 'connectivity_mode';

  bool _autoDownloadPadSounds = false;
  bool _autoDownloadDriveByDefault = false;
  ConnectivityMode _connectivityMode = ConnectivityMode.liveOffline;
  bool _loaded = false;

  /// Télécharge automatiquement les sons ajoutés à un pad (si Drive connecté).
  bool get autoDownloadPadSounds => _autoDownloadPadSounds;

  /// Active le téléchargement auto sur chaque nouvelle bibliothèque Drive liée.
  bool get autoDownloadDriveByDefault => _autoDownloadDriveByDefault;

  /// Mode réseau choisi par l'utilisateur (Paramètres).
  ConnectivityMode get connectivityMode => _connectivityMode;

  /// Synchro Drive automatique (push débouncé, pull au lancement).
  bool get allowsNetworkSync =>
      _connectivityMode == ConnectivityMode.connected;

  /// Spectacle local : masque les pads sans son en cache.
  bool get isLiveOfflineMode =>
      _connectivityMode == ConnectivityMode.liveOffline;

  /// Téléchargements à la demande (pads, prefetch, préparation plateau).
  bool get allowsSoundDownload =>
      _connectivityMode == ConnectivityMode.connected;

  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final file = await _preferencesFile();
    if (await file.exists()) {
      try {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _autoDownloadPadSounds = data[_keyAutoDownloadPadSounds] == true;
        _autoDownloadDriveByDefault =
            data[_keyAutoDownloadDriveByDefault] == true;
        _connectivityMode = ConnectivityModeUi.fromStorageKey(
          data[_keyConnectivityMode] as String?,
        );
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

  Future<void> setAutoDownloadDriveByDefault(bool value) async {
    if (_autoDownloadDriveByDefault == value) return;
    _autoDownloadDriveByDefault = value;
    notifyListeners();
    await _save();
  }

  Future<void> setConnectivityMode(ConnectivityMode value) async {
    if (_connectivityMode == value) return;
    _connectivityMode = value;
    notifyListeners();
    await _save();
  }

  /// Bascule le mode sans persistance (tests unitaires).
  @visibleForTesting
  void debugSetConnectivityMode(ConnectivityMode value) {
    if (_connectivityMode == value) return;
    _connectivityMode = value;
    notifyListeners();
  }

  Future<File> _preferencesFile() async {
    final docs = await getApplicationSupportDirectory();
    final dir = Directory(p.join(docs.path, _subdir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, _fileName));
  }

  Future<void> _save() async {
    final file = await _preferencesFile();
    await file.writeAsString(
      jsonEncode({
        _keyAutoDownloadPadSounds: _autoDownloadPadSounds,
        _keyAutoDownloadDriveByDefault: _autoDownloadDriveByDefault,
        _keyConnectivityMode: _connectivityMode.storageKey,
      }),
    );
  }
}
