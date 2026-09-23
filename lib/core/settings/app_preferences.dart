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
        ConnectivityMode.liveOffline => 'Live',
        ConnectivityMode.offline => 'Hors ligne',
      };

  String get description => switch (this) {
        ConnectivityMode.connected =>
          'Synchronisation Drive et téléchargements actifs.',
        ConnectivityMode.liveOffline =>
          'Mode scène : seuls les pads en cache local sont affichés et jouables.',
        ConnectivityMode.offline =>
          'Aucune synchro ni téléchargement, mais tous les pads restent visibles.',
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
  static const _keyCueOutputDeviceId = 'cue_output_device_id';
  static const _keyWindowsFullScreen = 'windows_full_screen';
  static const _keyLastUpdateCheckAt = 'last_update_check_at';
  static const _keyPadHotkeys = 'pad_hotkeys';

  bool _autoDownloadPadSounds = true;
  bool _autoDownloadDriveByDefault = true;
  ConnectivityMode _connectivityMode = ConnectivityMode.liveOffline;
  String? _cueOutputDeviceId;
  bool _isWindowsFullScreen = false;
  DateTime? _lastUpdateCheckAt;
  // padId (local, cet appareil) → LogicalKeyboardKey.keyId. Volontairement
  // local-only (jamais dans le snapshot Drive, cf. décision projet) : un id
  // de pad n'est stable que tant qu'aucune synchro ne réimporte son board
  // (LWW distant plus récent) ou qu'un Annuler ne le recrée — l'entrée
  // devient alors orpheline silencieusement (jamais retrouvée, jamais
  // fautive), à réassigner. Pas de nettoyage automatique en v1.
  Map<int, int> _padHotkeys = {};
  bool _loaded = false;

  /// Télécharge automatiquement les sons ajoutés à un pad (si Drive connecté).
  bool get autoDownloadPadSounds => _autoDownloadPadSounds;

  /// Active le téléchargement auto sur chaque nouvelle bibliothèque Drive liée.
  bool get autoDownloadDriveByDefault => _autoDownloadDriveByDefault;

  /// Mode réseau choisi par l'utilisateur (Paramètres).
  ConnectivityMode get connectivityMode => _connectivityMode;

  /// Périphérique de sortie de pré-écoute (cue), ou `null` pour « défaut
  /// système ». Utilisé sur desktop pour router les auditions vers un casque
  /// séparé pendant que la sortie « salle » reste sur le device par défaut.
  String? get cueOutputDeviceId => _cueOutputDeviceId;

  /// Dernier état plein écran connu de la fenêtre Windows — appliqué à la
  /// réouverture de l'app (voir `SoundboardApp._toggleFullScreen`).
  bool get isWindowsFullScreen => _isWindowsFullScreen;

  /// Horodatage du dernier check de mise à jour **automatique** (lancement) —
  /// sert à le limiter à une fois toutes les 6h. Le bouton manuel de Réglages
  /// ignore ce throttle.
  DateTime? get lastUpdateCheckAt => _lastUpdateCheckAt;

  /// Touches clavier assignées, par id de pad LOCAL (cet appareil), jamais
  /// synchronisé — voir le commentaire sur [_padHotkeys].
  Map<int, int> get padHotkeys => Map.unmodifiable(_padHotkeys);

  /// `LogicalKeyboardKey.keyId` assigné à [padId], ou `null` si aucune touche.
  int? hotkeyForPad(int padId) => _padHotkeys[padId];

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
        // Clé absente → défaut activé (true), valeur persistée respectée sinon.
        _autoDownloadPadSounds =
            (data[_keyAutoDownloadPadSounds] as bool?) ?? true;
        _autoDownloadDriveByDefault =
            (data[_keyAutoDownloadDriveByDefault] as bool?) ?? true;
        _connectivityMode = ConnectivityModeUi.fromStorageKey(
          data[_keyConnectivityMode] as String?,
        );
        _cueOutputDeviceId = data[_keyCueOutputDeviceId] as String?;
        _isWindowsFullScreen =
            (data[_keyWindowsFullScreen] as bool?) ?? false;
        final lastUpdateCheckRaw = data[_keyLastUpdateCheckAt] as String?;
        _lastUpdateCheckAt = lastUpdateCheckRaw == null
            ? null
            : DateTime.tryParse(lastUpdateCheckRaw);
        final hotkeysRaw = data[_keyPadHotkeys] as Map<String, dynamic>?;
        if (hotkeysRaw != null) {
          _padHotkeys = {
            for (final entry in hotkeysRaw.entries)
              if (int.tryParse(entry.key) case final padId?)
                if (entry.value is int) padId: entry.value as int,
          };
        }
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

  /// Choisit le device de pré-écoute (`null` = défaut système).
  Future<void> setCueOutputDeviceId(String? value) async {
    if (_cueOutputDeviceId == value) return;
    _cueOutputDeviceId = value;
    notifyListeners();
    await _save();
  }

  /// Persiste l'état plein écran de la fenêtre Windows (F11).
  Future<void> setWindowsFullScreen(bool value) async {
    if (_isWindowsFullScreen == value) return;
    _isWindowsFullScreen = value;
    await _save();
  }

  /// Assigne (ou efface si [keyId] est `null`) la touche déclenchant [padId].
  Future<void> setPadHotkey(int padId, int? keyId) async {
    if (keyId == null) {
      if (_padHotkeys.remove(padId) == null) return;
    } else {
      if (_padHotkeys[padId] == keyId) return;
      _padHotkeys = {..._padHotkeys, padId: keyId};
    }
    notifyListeners();
    await _save();
  }

  /// Marque l'instant du dernier check automatique — pas de notification, un
  /// throttle n'a pas besoin de reconstruire l'UI.
  Future<void> markUpdateCheckedNow() async {
    _lastUpdateCheckAt = DateTime.now();
    await _save();
  }

  /// Bascule le mode sans persistance (tests unitaires).
  @visibleForTesting
  void debugSetConnectivityMode(ConnectivityMode value) {
    if (_connectivityMode == value) return;
    _connectivityMode = value;
    notifyListeners();
  }

  /// Assigne une touche sans persistance (tests unitaires).
  @visibleForTesting
  void debugSetPadHotkey(int padId, int? keyId) {
    if (keyId == null) {
      _padHotkeys.remove(padId);
    } else {
      _padHotkeys = {..._padHotkeys, padId: keyId};
    }
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
        _keyCueOutputDeviceId: _cueOutputDeviceId,
        _keyWindowsFullScreen: _isWindowsFullScreen,
        _keyLastUpdateCheckAt: _lastUpdateCheckAt?.toIso8601String(),
        _keyPadHotkeys: {
          for (final entry in _padHotkeys.entries)
            entry.key.toString(): entry.value,
        },
      }),
    );
  }
}
