import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/sync/library_sound_paths.dart';

void main() {
  group('LibrarySoundPaths', () {
    test('localPathFor convertit les / en séparateur de plateforme', () {
      const root = '/cache/lib';
      expect(
        LibrarySoundPaths.localPathFor(root, 'Effets/Pistolet 4.mp3'),
        p.join(root, 'Effets', 'Pistolet 4.mp3'),
      );
    });

    test('normalizeRelativePath retire le préfixe sounds/ legacy', () {
      expect(
        LibrarySoundPaths.normalizeRelativePath('sounds/clap.wav'),
        'clap.wav',
      );
      expect(
        LibrarySoundPaths.normalizeRelativePath('Effets/clap.wav'),
        'Effets/clap.wav',
      );
    });

    test('normalizeRelativePath convertit en NFC', () {
      const nfd = 'Bruitages/De\u0301bile 1.mp3';
      const nfc = 'Bruitages/D\u00e9bile 1.mp3';
      expect(
        LibrarySoundPaths.normalizeRelativePath(nfd),
        LibrarySoundPaths.normalizeRelativePath(nfc),
      );
    });
  });
}
