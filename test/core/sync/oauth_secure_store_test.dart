import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:stage_cue/core/sync/google_oauth_config.dart';
import 'package:stage_cue/core/sync/oauth_secure_store.dart';

void main() {
  late MemoryOAuthSecretStore memory;

  setUp(() {
    memory = MemoryOAuthSecretStore();
    OAuthSecureStore.debugReplace(memory);
    GoogleOAuthConfig.debugResetRuntime();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    GoogleOAuthConfig.debugResetRuntime();
  });

  group('GoogleOAuthConfig runtime credentials', () {
    test('saveRuntimeCredentials rend isConfigured vrai', () async {
      expect(GoogleOAuthConfig.hasRuntimeCredentials, isFalse);

      await GoogleOAuthConfig.saveRuntimeCredentials(
        clientId: '  id.apps.googleusercontent.com ',
        clientSecret: ' secret ',
      );

      expect(GoogleOAuthConfig.clientId, 'id.apps.googleusercontent.com');
      expect(GoogleOAuthConfig.clientSecret, 'secret');
      expect(GoogleOAuthConfig.isConfigured, isTrue);
      expect(GoogleOAuthConfig.hasRuntimeCredentials, isTrue);
      expect(
        memory.values[OAuthSecureKeys.clientId],
        'id.apps.googleusercontent.com',
      );
      expect(memory.values[OAuthSecureKeys.clientSecret], 'secret');
    });

    test('load restaure les credentials du coffre', () async {
      await memory.write(OAuthSecureKeys.clientId, 'stored-id');
      await memory.write(OAuthSecureKeys.clientSecret, 'stored-secret');

      await GoogleOAuthConfig.load();

      expect(GoogleOAuthConfig.clientId, 'stored-id');
      expect(GoogleOAuthConfig.clientSecret, 'stored-secret');
      expect(GoogleOAuthConfig.debugLoaded, isTrue);
    });

    test('clearRuntimeCredentials efface le coffre', () async {
      await GoogleOAuthConfig.saveRuntimeCredentials(
        clientId: 'id',
        clientSecret: 'secret',
      );
      await GoogleOAuthConfig.clearRuntimeCredentials();

      expect(GoogleOAuthConfig.hasRuntimeCredentials, isFalse);
      expect(memory.values.containsKey(OAuthSecureKeys.clientId), isFalse);
      expect(memory.values.containsKey(OAuthSecureKeys.clientSecret), isFalse);
    });

    test('refuse les credentials vides', () async {
      expect(
        () => GoogleOAuthConfig.saveRuntimeCredentials(
          clientId: '  ',
          clientSecret: 'secret',
        ),
        throwsArgumentError,
      );
    });
  });

  group('OAuthSecureStore migration', () {
    test('migre le jeton SharedPreferences vers le coffre', () async {
      SharedPreferences.setMockInitialValues({
        OAuthSecureKeys.legacyPrefsToken: '{"access_token":"legacy"}',
      });
      OAuthSecureStore.debugResetMigrationFlag();

      final token = await OAuthSecureStore.readDriveToken();

      expect(token, '{"access_token":"legacy"}');
      expect(
        memory.values[OAuthSecureKeys.driveToken],
        '{"access_token":"legacy"}',
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(OAuthSecureKeys.legacyPrefsToken), isFalse);
    });

    test('ne réécrit pas un jeton déjà présent dans le coffre', () async {
      await memory.write(
        OAuthSecureKeys.driveToken,
        '{"access_token":"secure"}',
      );
      SharedPreferences.setMockInitialValues({
        OAuthSecureKeys.legacyPrefsToken: '{"access_token":"legacy"}',
      });
      OAuthSecureStore.debugResetMigrationFlag();

      final token = await OAuthSecureStore.readDriveToken();

      expect(token, '{"access_token":"secure"}');
    });

    test('deleteDriveToken retire coffre et legacy', () async {
      SharedPreferences.setMockInitialValues({
        OAuthSecureKeys.legacyPrefsToken: '{"access_token":"legacy"}',
      });
      await memory.write(
        OAuthSecureKeys.driveToken,
        '{"access_token":"secure"}',
      );
      OAuthSecureStore.debugResetMigrationFlag();

      await OAuthSecureStore.deleteDriveToken();

      expect(memory.values.containsKey(OAuthSecureKeys.driveToken), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(OAuthSecureKeys.legacyPrefsToken), isFalse);
    });
  });
}
