import 'dart:convert';

import 'package:google_sign_in_all_platforms/google_sign_in_all_platforms.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'drive_account_profile.dart';
import 'drive_client.dart';
import 'google_drive_client.dart';
import 'google_oauth_config.dart';

/// Authentification Google Drive sur Windows/Linux via OAuth navigateur.
class GoogleDriveDesktopAuthenticator implements DriveAuthenticator {
  GoogleDriveDesktopAuthenticator({GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn;

  final GoogleSignIn? _googleSignIn;
  GoogleSignIn? _resolvedSignIn;
  DriveAccountProfile? _cachedProfile;

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
          'openid',
          drive.DriveApi.driveScope,
          drive.DriveApi.driveFileScope,
          drive.DriveApi.driveReadonlyScope,
          'https://www.googleapis.com/auth/userinfo.email',
          'https://www.googleapis.com/auth/userinfo.profile',
        ],
      ),
    );
  }

  @override
  String? get accountEmail => _cachedProfile?.email;

  @override
  DriveAccountProfile? get accountProfile => _cachedProfile;

  Future<DriveClient?> _clientForCredentials(
    GoogleSignInCredentials credentials,
  ) async {
    _cachedProfile = await _resolveProfile(credentials);
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
    _cachedProfile = null;
    await _signIn.signOut();
  }

  static Future<DriveAccountProfile?> _resolveProfile(
    GoogleSignInCredentials credentials,
  ) async {
    final fromIdToken = _profileFromIdToken(credentials.idToken);
    if (fromIdToken != null && fromIdToken.photoUrl?.isNotEmpty == true) {
      return fromIdToken;
    }

    final fromUserInfo = await _profileFromUserInfo(credentials.accessToken);
    if (fromIdToken == null) {
      return fromUserInfo;
    }
    if (fromUserInfo == null) {
      return fromIdToken;
    }

    return DriveAccountProfile(
      email: fromIdToken.email,
      displayName: fromIdToken.displayName ?? fromUserInfo.displayName,
      photoUrl: fromUserInfo.photoUrl ?? fromIdToken.photoUrl,
    );
  }

  static Future<DriveAccountProfile?> _profileFromUserInfo(
    String accessToken,
  ) async {
    try {
      final response = await http.get(
        Uri.https('www.googleapis.com', '/oauth2/v3/userinfo'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (response.statusCode != 200) {
        return null;
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final email = payload['email'] as String?;
      if (email == null || email.isEmpty) {
        return null;
      }

      return DriveAccountProfile(
        email: email,
        displayName: payload['name'] as String?,
        photoUrl: payload['picture'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  static DriveAccountProfile? _profileFromIdToken(String? idToken) {
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
      final email = payload['email'] as String?;
      if (email == null || email.isEmpty) {
        return null;
      }
      return DriveAccountProfile(
        email: email,
        displayName: payload['name'] as String?,
        photoUrl: payload['picture'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
