import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/settings/app_preferences.dart';

// Utilise `debugSetPadHotkey` (mutation en mémoire, sans `_save()`), comme
// les tests existants sur `AppPreferences` le font déjà pour connectivityMode
// (`debugSetConnectivityMode`) — ce fichier touche le disque via
// `path_provider`, indisponible sans mock de plateforme en `flutter test`.
void main() {
  group('AppPreferences.padHotkeys', () {
    test('aucune touche assignée par défaut', () {
      final prefs = AppPreferences();
      expect(prefs.hotkeyForPad(1), isNull);
      expect(prefs.padHotkeys, isEmpty);
    });

    test('assigne puis retrouve la touche du pad', () {
      final prefs = AppPreferences();
      prefs.debugSetPadHotkey(1, 100);
      expect(prefs.hotkeyForPad(1), 100);
      expect(prefs.padHotkeys, {1: 100});
    });

    test('efface une touche assignée (keyId null)', () {
      final prefs = AppPreferences();
      prefs.debugSetPadHotkey(1, 100);
      prefs.debugSetPadHotkey(1, null);
      expect(prefs.hotkeyForPad(1), isNull);
      expect(prefs.padHotkeys, isEmpty);
    });

    test('deux pads gardent des touches indépendantes', () {
      final prefs = AppPreferences();
      prefs.debugSetPadHotkey(1, 100);
      prefs.debugSetPadHotkey(2, 200);
      expect(prefs.hotkeyForPad(1), 100);
      expect(prefs.hotkeyForPad(2), 200);
      prefs.debugSetPadHotkey(1, null);
      expect(prefs.hotkeyForPad(1), isNull);
      expect(prefs.hotkeyForPad(2), 200);
    });

    test('réassigner écrase la touche précédente du même pad', () {
      final prefs = AppPreferences();
      prefs.debugSetPadHotkey(1, 100);
      prefs.debugSetPadHotkey(1, 999);
      expect(prefs.hotkeyForPad(1), 999);
      expect(prefs.padHotkeys, {1: 999});
    });

    test('padHotkeys renvoie une map non modifiable', () {
      final prefs = AppPreferences();
      prefs.debugSetPadHotkey(1, 100);
      expect(() => prefs.padHotkeys[2] = 200, throwsUnsupportedError);
    });
  });
}
