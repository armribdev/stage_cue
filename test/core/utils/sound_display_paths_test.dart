import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/utils/sound_display_paths.dart';
import 'package:stage_cue/features/sampler/domain/entities/library.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';

Sound _sound({
  int? libraryId,
  String? relativePath,
  String filePath = r'C:\cache\local\Pistolet.mp3',
}) {
  return Sound(
    id: 1,
    title: 'Pistolet',
    filePath: filePath,
    type: SoundType.soundEffect,
    createdAt: DateTime(2024),
    libraryId: libraryId,
    relativePath: relativePath,
  );
}

Library _library({
  String? drivePath,
  String? ownerEmail,
}) {
  return Library(
    id: 10,
    name: 'Scène 2',
    localRootPath: r'C:\cache\scene2',
    drivePath: drivePath,
    ownerEmail: ownerEmail,
    createdAt: DateTime(2024),
  );
}

void main() {
  group('SoundDisplayPaths', () {
    test('son local : conserve filePath', () {
      expect(
        SoundDisplayPaths.forSound(
          _sound(filePath: r'D:\Sons\door.wav'),
        ),
        r'D:\Sons\door.wav',
      );
    });

    test('son Drive : chemin propriétaire + bibliothèque + relatif', () {
      final path = SoundDisplayPaths.forSound(
        _sound(
          libraryId: 10,
          relativePath: 'Effets/Pistolet 4é.mp3',
        ),
        library: _library(
          drivePath: 'Mon Projet / Scène 2',
          ownerEmail: 'owner@gmail.com',
        ),
      );

      expect(
        path,
        'owner@gmail.com/Mon Projet/Scène 2/Effets/Pistolet 4é.mp3',
      );
    });

    test('son Drive sans propriétaire : chemin relatif seulement', () {
      expect(
        SoundDisplayPaths.forSound(
          _sound(
            libraryId: 10,
            relativePath: 'Ambiance/pluie.mp3',
          ),
          library: _library(drivePath: 'Théâtre'),
        ),
        'Théâtre/Ambiance/pluie.mp3',
      );
    });

    test('n utilise pas le compte connecté comme repli', () {
      expect(
        SoundDisplayPaths.drivePathForSound(
          relativePath: 'fx.wav',
          library: _library(drivePath: 'Théâtre'),
        ),
        'Théâtre/fx.wav',
      );
    });
  });
}
