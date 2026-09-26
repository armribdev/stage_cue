import 'package:flutter/foundation.dart' show visibleForTesting;

import 'google_oauth_secrets.dart'
    if (dart.library.html) 'google_oauth_secrets.example.dart';
import 'oauth_secure_store.dart';

/// Identifiants OAuth « Web application » requis pour l'authentification
/// Google Drive sur Windows et Linux.
///
/// Priorité : `--dart-define`, puis credentials saisis dans l'app (coffre
/// sécurisé), puis `google_oauth_secrets.dart` (dev local).
class GoogleOAuthConfig {
  GoogleOAuthConfig._();

  static const String _clientIdFromDefine = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_ID',
    defaultValue: '',
  );

  static const String _clientSecretFromDefine = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_SECRET',
    defaultValue: '',
  );

  static String _runtimeClientId = '';
  static String _runtimeClientSecret = '';
  static bool _loaded = false;

  /// Charge les credentials éventuellement saisis au runtime (coffre).
  /// À appeler une fois au démarrage avant toute connexion Drive.
  static Future<void> load() async {
    final id = await OAuthSecureStore.read(OAuthSecureKeys.clientId);
    final secret = await OAuthSecureStore.read(OAuthSecureKeys.clientSecret);
    _runtimeClientId = id?.trim() ?? '';
    _runtimeClientSecret = secret?.trim() ?? '';
    _loaded = true;
  }

  /// Persiste des credentials saisis dans l'UI (beta / binaire sans dart-define).
  static Future<void> saveRuntimeCredentials({
    required String clientId,
    required String clientSecret,
  }) async {
    final id = clientId.trim();
    final secret = clientSecret.trim();
    if (id.isEmpty || secret.isEmpty) {
      throw ArgumentError('Client ID et Client Secret sont requis.');
    }
    await OAuthSecureStore.write(OAuthSecureKeys.clientId, id);
    await OAuthSecureStore.write(OAuthSecureKeys.clientSecret, secret);
    _runtimeClientId = id;
    _runtimeClientSecret = secret;
    _loaded = true;
  }

  /// Efface les credentials runtime (pas les dart-define ni le fichier secrets).
  static Future<void> clearRuntimeCredentials() async {
    await OAuthSecureStore.delete(OAuthSecureKeys.clientId);
    await OAuthSecureStore.delete(OAuthSecureKeys.clientSecret);
    _runtimeClientId = '';
    _runtimeClientSecret = '';
  }

  @visibleForTesting
  static void debugResetRuntime() {
    _runtimeClientId = '';
    _runtimeClientSecret = '';
    _loaded = false;
  }

  @visibleForTesting
  static bool get debugLoaded => _loaded;

  static String get clientId {
    if (_clientIdFromDefine.isNotEmpty) {
      return _clientIdFromDefine;
    }
    if (_runtimeClientId.isNotEmpty) {
      return _runtimeClientId;
    }
    return googleOAuthClientId;
  }

  static String get clientSecret {
    if (_clientSecretFromDefine.isNotEmpty) {
      return _clientSecretFromDefine;
    }
    if (_runtimeClientSecret.isNotEmpty) {
      return _runtimeClientSecret;
    }
    return googleOAuthClientSecret;
  }

  static bool get isConfigured =>
      clientId.isNotEmpty && clientSecret.isNotEmpty;

  /// Vrai si la config actuelle vient d'une saisie utilisateur (pas define/fichier).
  static bool get hasRuntimeCredentials =>
      _runtimeClientId.isNotEmpty && _runtimeClientSecret.isNotEmpty;

  static const String setupHint =
      'Saisissez le Client ID et le Client Secret d\'un client OAuth « Web » '
      '(redirect URI : http://localhost:8000) dans le dialogue affiché, '
      'ou via --dart-define / google_oauth_secrets.dart en développement.';
}

/// Levée quand l'auth Drive desktop est demandée sans identifiants OAuth.
class GoogleOAuthNotConfiguredException implements Exception {
  final String message;

  const GoogleOAuthNotConfiguredException(this.message);

  @override
  String toString() => message;
}
