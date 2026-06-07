import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/sync/library_sound_paths.dart';

void main() {
  group('LibrarySoundPaths', () {
    test('localPathFor convertit les / en séparateur de plateforme', () {
      const root = '/cache/lib';
      expect(
        LibrarySoundPaths.localPathFor(root, 'Effets/Pistolet 4é.mp3'),
        p.join(root, 'Effets', 'Pistolet 4é.mp3'),
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
  });
}
