import 'dart:async';
import 'dart:convert';

import 'package:google_sign_in_all_platforms/google_sign_in_all_platforms.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'drive_account_profile.dart';
import 'drive_client.dart';
import 'google_drive_client.dart';
import 'google_oauth_config.dart';

const String _kTokenKey = 'token';
const String _kExpiresAtKey = 'expires_at';
const Duration _kDefaultAccessTokenLifetime = Duration(minutes: 55);

const List<String> _kDriveScopes = [
  'openid',
  drive.DriveApi.driveScope,
  drive.DriveApi.driveFileScope,
  drive.DriveApi.driveReadonlyScope,
  'https://www.googleapis.com/auth/userinfo.email',
  'https://www.googleapis.com/auth/userinfo.profile',
];

/// Authentification Google Drive sur Windows/Linux via OAuth navigateur.
class GoogleDriveDesktopAuthenticator implements DriveAuthenticator {
  GoogleDriveDesktopAuthenticator({GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn;

  final GoogleSignIn? _googleSignIn;
  GoogleSignIn? _resolvedSignIn;
  DriveAccountProfile? _cachedProfile;
  StreamSubscription<auth.AccessCredentials>? _credentialSubscription;

  GoogleSignIn get _signIn =>
      _resolvedSignIn ??= _googleSignIn ?? _createSignIn();

  static GoogleSignIn _createSignIn() {
    if (!GoogleOAuthConfig.isConfigured) {
      throw GoogleOAuthNotConfiguredException(GoogleOAuthConfig.setupHint);
    }

    return GoogleSignIn(
      params: GoogleSignInParams(
        clientId: GoogleOAuthConfig.clientId,
        clientSecret: GoogleOAuthConfig.clientSecret,
        saveAccessToken: _saveStoredToken,
        retrieveAccessToken: _readStoredToken,
        deleteAccessToken: _deleteStoredToken,
        scopes: _kDriveScopes,
      ),
    );
  }

  @override
  String? get accountEmail => _cachedProfile?.email;

  @override
  DriveAccountProfile? get accountProfile => _cachedProfile;

  @override
  Future<void> restoreAccountProfile() async {
    if (_cachedProfile != null) {
      return;
    }
    final stored = await _loadStoredCredentials();
    if (stored == null) {
      return;
    }
    _cachedProfile = await _resolveProfile(stored.credentials);
  }

  Future<DriveClient?> _clientForCredentials(
    GoogleSignInCredentials credentials, {
    DateTime? accessTokenExpiry,
  }) async {
    _cachedProfile = await _resolveProfile(credentials);
    final authClient = _createAuthHttpClient(
      credentials,
      accessTokenExpiry: accessTokenExpiry,
    );
    if (authClient == null) {
      return null;
    }
    return GoogleDriveClient(drive.DriveApi(authClient), authClient);
  }

  http.Client? _createAuthHttpClient(
    GoogleSignInCredentials credentials, {
    DateTime? accessTokenExpiry,
  }) {
    final scopes =
        credentials.scopes.isEmpty ? _kDriveScopes : credentials.scopes;
    final expiry = accessTokenExpiry ??
        DateTime.now().toUtc().subtract(const Duration(seconds: 1));
    final refreshToken = credentials.refreshToken;

    if (refreshToken != null && refreshToken.isNotEmpty) {
      final accessCreds = auth.AccessCredentials(
        auth.AccessToken(
          credentials.tokenType ?? 'Bearer',
          credentials.accessToken,
          expiry,
        ),
        refreshToken,
        scopes,
        idToken: credentials.idToken,
      );

      final client = auth.autoRefreshingClient(
        auth.ClientId(
          GoogleOAuthConfig.clientId,
          GoogleOAuthConfig.clientSecret,
        ),
        accessCreds,
        http.Client(),
      );
      _listenCredentialUpdates(client, credentials);
      return client;
    }

    return auth.authenticatedClient(
      http.Client(),
      auth.AccessCredentials(
        auth.AccessToken(
          credentials.tokenType ?? 'Bearer',
          credentials.accessToken,
          expiry,
        ),
        null,
        scopes,
        idToken: credentials.idToken,
      ),
    );
  }

  void _listenCredentialUpdates(
    auth.AutoRefreshingAuthClient client,
    GoogleSignInCredentials base,
  ) {
    _credentialSubscription?.cancel();
    _credentialSubscription = client.credentialUpdates.listen((creds) {
      unawaited(_persistRefreshedCredentials(base, creds));
    });
  }

  @override
  Future<DriveClient?> connect() async {
    final credentials = await _signIn.signIn();
    if (credentials == null) {
      return null;
    }
    final expiry = await _resolveAccessTokenExpiry(credentials);
    return _clientForCredentials(credentials, accessTokenExpiry: expiry);
  }

  @override
  Future<DriveClient?> connectSilently() async {
    await _signIn.signInOffline();
    final stored = await _loadStoredCredentials();
    if (stored == null) {
      return null;
    }

    _cachedProfile ??= await _resolveProfile(stored.credentials);

    final expiry = stored.expiresAt;
    final accessTokenExpiry = expiry == null || expiry.isBefore(DateTime.now())
        ? DateTime.now().toUtc().subtract(const Duration(seconds: 1))
        : expiry;

    return _clientForCredentials(
      stored.credentials,
      accessTokenExpiry: accessTokenExpiry,
    );
  }

  Future<DateTime> _resolveAccessTokenExpiry(
    GoogleSignInCredentials credentials,
  ) async {
    final stored = await _loadStoredCredentials();
    if (stored != null &&
        stored.credentials.accessToken == credentials.accessToken) {
      final expiresAt = stored.expiresAt;
      if (expiresAt != null && expiresAt.isAfter(DateTime.now())) {
        return expiresAt;
      }
      return DateTime.now().toUtc().subtract(const Duration(seconds: 1));
    }
    return DateTime.now().toUtc().add(_kDefaultAccessTokenLifetime);
  }

  @override
  Future<void> signOut() async {
    _credentialSubscription?.cancel();
    _credentialSubscription = null;
    _cachedProfile = null;
    await _signIn.signOut();
  }

  static Future<void> _saveStoredToken(String tokenJson) async {
    final map = Map<String, dynamic>.from(jsonDecode(tokenJson) as Map);
    map.putIfAbsent(
      _kExpiresAtKey,
      () => DateTime.now()
          .toUtc()
          .add(_kDefaultAccessTokenLifetime)
          .toIso8601String(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTokenKey, jsonEncode(map));
  }

  static Future<String?> _readStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kTokenKey);
  }

  static Future<void> _deleteStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokenKey);
  }

  static Future<_StoredCredentials?> _loadStoredCredentials() async {
    final raw = await _readStoredToken();
    if (raw == null) {
      return null;
    }

    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final expiresRaw = map[_kExpiresAtKey];
      final expiresAt = expiresRaw is String
          ? DateTime.tryParse(expiresRaw)?.toUtc()
          : null;
      return _StoredCredentials(
        credentials: _credentialsFromStoredMap(map),
        expiresAt: expiresAt,
      );
    } catch (_) {
      return null;
    }
  }

  static GoogleSignInCredentials _credentialsFromStoredMap(
    Map<String, dynamic> map,
  ) {
    return GoogleSignInCredentials(
      accessToken: map['access_token'] as String,
      refreshToken: map['refresh_token'] as String?,
      scopes: _parseScopes(map['scope']),
      tokenType: map['token_type'] as String?,
      idToken: map['id_token'] as String?,
    );
  }

  static List<String> _parseScopes(dynamic raw) {
    if (raw is List) {
      return raw.cast<String>();
    }
    if (raw is String && raw.isNotEmpty) {
      return raw.split(' ').where((scope) => scope.isNotEmpty).toList();
    }
    return const [];
  }

  static Future<void> _persistRefreshedCredentials(
    GoogleSignInCredentials base,
    auth.AccessCredentials creds,
  ) async {
    final payload = <String, dynamic>{
      'access_token': creds.accessToken.data,
      'refresh_token': creds.refreshToken ?? base.refreshToken,
      'scope': creds.scopes,
      'token_type': creds.accessToken.type,
      _kExpiresAtKey: creds.accessToken.expiry.toIso8601String(),
    };
    final idToken = creds.idToken ?? base.idToken;
    if (idToken != null) {
      payload['id_token'] = idToken;
    }
    await _saveStoredToken(jsonEncode(payload));
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

class _StoredCredentials {
  const _StoredCredentials({
    required this.credentials,
    required this.expiresAt,
  });

  final GoogleSignInCredentials credentials;
  final DateTime? expiresAt;
}
