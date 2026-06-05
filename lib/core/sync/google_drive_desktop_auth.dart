import 'dart:convert';

import 'package:google_sign_in_all_platforms/google_sign_in_all_platforms.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import 'drive_client.dart';
import 'google_drive_client.dart';
import 'google_oauth_config.dart';

/// Authentification Google Drive sur Windows/Linux via OAuth navigateur.
class GoogleDriveDesktopAuthenticator implements DriveAuthenticator {
  GoogleDriveDesktopAuthenticator({GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn;

  final GoogleSignIn? _googleSignIn;
  GoogleSignIn? _resolvedSignIn;
  String? _cachedAccountEmail;

  GoogleSignIn get _signIn => _resolvedSignIn ??= _googleSignIn ?? _createSignIn();

  static GoogleSignIn _createSignIn() {
    if (!GoogleOAuthConfig.isConfigured) {
      throw GoogleOAuthNotConfiguredException(GoogleOAuthConfig.setupHint);
    }

    return GoogleSignIn(
      params: GoogleSignInParams(
        clientId: GoogleOAuthConfig.clientId,
        clientSecret: GoogleOAuthConfig.clientSecret,
        scopes: const [
          drive.DriveApi.driveFileScope,
          drive.DriveApi.driveReadonlyScope,
          'https://www.googleapis.com/auth/userinfo.email',
          'https://www.googleapis.com/auth/userinfo.profile',
        ],
      ),
    );
  }

  @override
  String? get accountEmail => _cachedAccountEmail;

  Future<DriveClient?> _clientForCredentials(
    GoogleSignInCredentials credentials,
  ) async {
    _cachedAccountEmail ??= _emailFromIdToken(credentials.idToken);
    final authClient = await _signIn.authenticatedClient;
    if (authClient == null) {
      return null;
    }
    return GoogleDriveClient(drive.DriveApi(authClient), authClient);
  }

  @override
  Future<DriveClient?> connect() async {
    final credentials = await _signIn.signIn();
    if (credentials == null) {
      return null;
    }
    return _clientForCredentials(credentials);
  }

  @override
  Future<DriveClient?> connectSilently() async {
    final credentials = await _signIn.signInOffline();
    if (credentials == null) {
      return null;
    }
    return _clientForCredentials(credentials);
  }

  @override
  Future<void> signOut() async {
    _cachedAccountEmail = null;
    await _signIn.signOut();
  }

  static String? _emailFromIdToken(String? idToken) {
    if (idToken == null) {
      return null;
    }

    try {
      final parts = idToken.split('.');
      if (parts.length < 2) {
        return null;
      }
      final normalized = base64Url.normalize(parts[1]);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)))
          as Map<String, dynamic>;
      return payload['email'] as String?;
    } catch (_) {
      return null;
    }
  }
}
