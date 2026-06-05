import 'google_oauth_secrets.dart'
    if (dart.library.html) 'google_oauth_secrets.example.dart';

/// Identifiants OAuth « Web application » requis pour l'authentification
/// Google Drive sur Windows et Linux.
///
/// Priorité : `--dart-define`, puis `google_oauth_secrets.dart`.
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

  static String get clientId =>
      _clientIdFromDefine.isNotEmpty
          ? _clientIdFromDefine
          : googleOAuthClientId;

  static String get clientSecret =>
      _clientSecretFromDefine.isNotEmpty
          ? _clientSecretFromDefine
          : googleOAuthClientSecret;

  static bool get isConfigured =>
      clientId.isNotEmpty && clientSecret.isNotEmpty;

  static const String setupHint =
      'Éditez lib/core/sync/google_oauth_secrets.dart avec le Client ID '
      'et le Client Secret d\'un client OAuth « Web » (redirect URI : '
      'http://localhost:8000), puis redémarrez l\'app.';
}

/// Levée quand l'auth Drive desktop est demandée sans identifiants OAuth.
class GoogleOAuthNotConfiguredException implements Exception {
  final String message;

  const GoogleOAuthNotConfiguredException(this.message);

  @override
  String toString() => message;
}
