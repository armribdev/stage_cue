import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_log.dart';

/// Clés du coffre OAuth Drive (desktop).
abstract final class OAuthSecureKeys {
  static const driveToken = 'drive_oauth_token';
  static const clientId = 'drive_oauth_client_id';
  static const clientSecret = 'drive_oauth_client_secret';

  /// Ancienne clé SharedPreferences (jeton en clair) — migrée puis effacée.
  static const legacyPrefsToken = 'token';
}

/// Stockage clé/valeur pour secrets OAuth (client + jetons de session).
///
/// Abstraction pour injecter une implémentation mémoire en tests.
abstract class OAuthSecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Backend [FlutterSecureStorage] (DPAPI / Keychain / Keystore selon OS).
class FlutterOAuthSecretStore implements OAuthSecretStore {
  FlutterOAuthSecretStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Backend mémoire pour les tests unitaires.
class MemoryOAuthSecretStore implements OAuthSecretStore {
  final Map<String, String> _values = {};

  Map<String, String> get values => Map.unmodifiable(_values);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

/// Accès global au coffre OAuth + migration unique depuis SharedPreferences.
class OAuthSecureStore {
  OAuthSecureStore._();

  static OAuthSecretStore _backend = FlutterOAuthSecretStore();
  static bool _legacyTokenMigrated = false;

  static OAuthSecretStore get instance => _backend;

  /// Remplace le backend (tests) et réarme la migration.
  @visibleForTesting
  static void debugReplace(OAuthSecretStore store) {
    _backend = store;
    _legacyTokenMigrated = false;
  }

  @visibleForTesting
  static void debugResetMigrationFlag() {
    _legacyTokenMigrated = false;
  }

  static Future<String?> read(String key) => _backend.read(key);

  static Future<void> write(String key, String value) =>
      _backend.write(key, value);

  static Future<void> delete(String key) => _backend.delete(key);

  /// Lit le jeton Drive ; migre l'ancien stockage SharedPreferences si besoin.
  static Future<String?> readDriveToken() async {
    await _migrateLegacyTokenIfNeeded();
    return _backend.read(OAuthSecureKeys.driveToken);
  }

  static Future<void> writeDriveToken(String tokenJson) =>
      _backend.write(OAuthSecureKeys.driveToken, tokenJson);

  static Future<void> deleteDriveToken() async {
    await _migrateLegacyTokenIfNeeded();
    await _backend.delete(OAuthSecureKeys.driveToken);
    // Nettoyage défensif si la migration n'avait pas encore tourné.
    await _deleteLegacyPrefsToken();
  }

  static Future<void> _migrateLegacyTokenIfNeeded() async {
    if (_legacyTokenMigrated) {
      return;
    }
    _legacyTokenMigrated = true;

    final existing = await _backend.read(OAuthSecureKeys.driveToken);
    if (existing != null && existing.isNotEmpty) {
      await _deleteLegacyPrefsToken();
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(OAuthSecureKeys.legacyPrefsToken);
      if (legacy == null || legacy.isEmpty) {
        return;
      }
      await _backend.write(OAuthSecureKeys.driveToken, legacy);
      await prefs.remove(OAuthSecureKeys.legacyPrefsToken);
      SyncLog.info(
        'Jeton Drive migré de SharedPreferences vers le stockage sécurisé.',
      );
    } catch (e) {
      SyncLog.warn('Migration du jeton Drive impossible — $e');
    }
  }

  static Future<void> _deleteLegacyPrefsToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(OAuthSecureKeys.legacyPrefsToken)) {
        await prefs.remove(OAuthSecureKeys.legacyPrefsToken);
      }
    } catch (_) {
      // Prefs indisponibles (tests hors binding) : ignorer.
    }
  }
}
