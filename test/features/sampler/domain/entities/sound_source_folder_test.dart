import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';

Sound _sound({String? relativePath}) => Sound(
  id: 1,
  title: 't',
  filePath: '',
  createdAt: DateTime(2026),
  relativePath: relativePath,
);

void main() {
  group('Sound.sourceFolder', () {
    test('sous-dossiers : rattachés au dossier de premier niveau', () {
      expect(
        _sound(relativePath: 'Musique/Épique/a.mp3').sourceFolder,
        'Musique',
      );
      expect(_sound(relativePath: 'Musique/a.mp3').sourceFolder, 'Musique');
    });

    test('fichier à la racine : chaîne vide', () {
      expect(_sound(relativePath: 'a.mp3').sourceFolder, '');
    });

    test('son local ou chemin vide : null', () {
      expect(_sound().sourceFolder, isNull);
      expect(_sound(relativePath: '').sourceFolder, isNull);
    });
  });
}
