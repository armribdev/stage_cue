// Le nom affiché d'un son n'est jamais vide : un nom vide retombe sur le titre
// du fichier, garanti par la couche données (pas seulement par le formulaire).

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/features/sampler/data/datasources/local_sound_datasource.dart';

void main() {
  late db.AppDatabase database;
  late LocalSoundDataSource dataSource;
  late int soundId;

  setUp(() async {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    dataSource = LocalSoundDataSource(database);
    soundId = await database.into(database.sounds).insert(
          db.SoundsCompanion.insert(
            title: 'porte',
            filePath: '/cache/porte.wav',
            displayName: const Value('Porte grinçante'),
          ),
        );
  });

  tearDown(() => database.close());

  Future<String?> displayName() async => (await (database.select(
              database.sounds)
          ..where((s) => s.id.equals(soundId)))
        .getSingle())
      .displayName;

  test('un nom vide ou blanc retombe sur le titre du fichier', () async {
    for (final blank in <String?>['', '   ', null]) {
      await dataSource.updateSoundSettings(
        id: soundId,
        displayName: 'Autre nom',
        updateDisplayName: true,
      );
      await dataSource.updateSoundSettings(
        id: soundId,
        displayName: blank,
        updateDisplayName: true,
      );
      expect(await displayName(), 'porte', reason: 'saisie : "$blank"');
    }
  });

  test('un nom saisi est enregistré rogné', () async {
    await dataSource.updateSoundSettings(
      id: soundId,
      displayName: '  Grincement  ',
      updateDisplayName: true,
    );
    expect(await displayName(), 'Grincement');
  });

  test('sans updateDisplayName, le nom n\'est pas touché', () async {
    await dataSource.updateSoundSettings(id: soundId, volume: 0.5);
    expect(await displayName(), 'Porte grinçante');
  });
}
