import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/sync/local_availability_probe.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('probe_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// Crée un fichier (contenu non pertinent : la sonde ne lit pas les octets).
  Future<void> writeFile(String relativePath) async {
    final file = File(p.joinAll([tempDir.path, ...relativePath.split('/')]));
    await file.parent.create(recursive: true);
    await file.writeAsString('x');
  }

  Sound librarySound(int id, String relativePath, {int libraryId = 1}) => Sound(
        id: id,
        title: 'son $id',
        filePath: p.joinAll([tempDir.path, ...relativePath.split('/')]),
        createdAt: DateTime(2026),
        libraryId: libraryId,
        relativePath: relativePath,
      );

  group('probeLocallyAvailableSoundIds', () {
    test('ne retient que les sons présents dans le cache', () async {
      await writeFile('Effets/clap.wav');
      await writeFile('Musiques/intro.mp3');

      final ids = await probeLocallyAvailableSoundIds(
        sounds: [
          librarySound(1, 'Effets/clap.wav'),
          librarySound(2, 'Musiques/intro.mp3'),
          librarySound(3, 'Effets/absent.wav'),
        ],
        libraryRootPaths: {1: tempDir.path},
      );

      expect(ids, {1, 2});
    });

    test('compare en NFC : un fichier NFD sur disque reste trouvé', () async {
      // Windows matérialise souvent les accents en NFD alors que la base stocke
      // en NFC — sans normalisation commune le son passerait pour absent.
      await writeFile('Bruitages/Débile 1.mp3');

      final ids = await probeLocallyAvailableSoundIds(
        sounds: [librarySound(1, 'Bruitages/Débile 1.mp3')],
        libraryRootPaths: {1: tempDir.path},
      );

      expect(ids, {1});
    });

    test('accepte le préfixe sounds/ legacy des chemins relatifs', () async {
      await writeFile('clap.wav');

      final ids = await probeLocallyAvailableSoundIds(
        sounds: [librarySound(1, 'sounds/clap.wav')],
        libraryRootPaths: {1: tempDir.path},
      );

      expect(ids, {1});
    });

    test('ignore les téléchargements inachevés (.part)', () async {
      await writeFile('Effets/clap.wav.part');

      final ids = await probeLocallyAvailableSoundIds(
        sounds: [librarySound(1, 'Effets/clap.wav.part')],
        libraryRootPaths: {1: tempDir.path},
      );

      expect(ids, isEmpty);
    });

    test('bibliothèque sans racine connue -> aucun son disponible', () async {
      await writeFile('Effets/clap.wav');

      final ids = await probeLocallyAvailableSoundIds(
        sounds: [librarySound(1, 'Effets/clap.wav', libraryId: 42)],
        libraryRootPaths: {1: tempDir.path},
      );

      expect(ids, isEmpty);
    });

    test('racine inexistante -> aucun son, pas d\'exception', () async {
      final ids = await probeLocallyAvailableSoundIds(
        sounds: [librarySound(1, 'Effets/clap.wav')],
        libraryRootPaths: {1: p.join(tempDir.path, 'jamais_cree')},
      );

      expect(ids, isEmpty);
    });

    test('son legacy (sans bibliothèque) testé par son filePath', () async {
      await writeFile('local/present.wav');

      final present = Sound(
        id: 1,
        title: 'present',
        filePath: p.join(tempDir.path, 'local', 'present.wav'),
        createdAt: DateTime(2026),
      );
      final absent = Sound(
        id: 2,
        title: 'absent',
        filePath: p.join(tempDir.path, 'local', 'absent.wav'),
        createdAt: DateTime(2026),
      );

      final ids = await probeLocallyAvailableSoundIds(
        sounds: [present, absent],
        libraryRootPaths: const {},
      );

      expect(ids, {1});
    });

    test('relativePath vide -> son ignoré sans planter', () async {
      final ids = await probeLocallyAvailableSoundIds(
        sounds: [librarySound(1, '')],
        libraryRootPaths: {1: tempDir.path},
      );

      expect(ids, isEmpty);
    });
  });
}
