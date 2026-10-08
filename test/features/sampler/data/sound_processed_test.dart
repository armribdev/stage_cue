// Statut « traité » d'un son : la validation en masse de la file « À traiter »
// ne marque que les sons demandés et ne touche à aucun autre réglage.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/features/sampler/data/datasources/local_sound_datasource.dart';

void main() {
  late db.AppDatabase database;
  late LocalSoundDataSource dataSource;
  late List<int> ids;

  setUp(() async {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    dataSource = LocalSoundDataSource(database);
    ids = [
      for (final name in ['porte', 'pluie', 'orage'])
        await database.into(database.sounds).insert(
              db.SoundsCompanion.insert(
                title: name,
                filePath: '/cache/$name.wav',
                displayName: name,
              ),
            ),
    ];
  });

  tearDown(() => database.close());

  Future<Map<int, bool>> processedById() async => {
        for (final s in await database.select(database.sounds).get())
          s.id: s.isProcessed,
      };

  test('un son nouveau est « à traiter » par défaut', () async {
    expect((await processedById()).values, everyElement(isFalse));
  });

  test('markSoundsProcessed ne marque que les ids demandés', () async {
    await dataSource.markSoundsProcessed([ids[0], ids[2]]);

    expect(await processedById(), {ids[0]: true, ids[1]: false, ids[2]: true});
  });

  test('markSoundsProcessed laisse les autres réglages intacts', () async {
    await dataSource.updateSoundSettings(
      id: ids[0],
      displayName: 'Porte grinçante',
      updateDisplayName: true,
      volume: 0.4,
    );

    await dataSource.markSoundsProcessed([ids[0]]);

    final row = await (database.select(database.sounds)
          ..where((s) => s.id.equals(ids[0])))
        .getSingle();
    expect(row.displayName, 'Porte grinçante');
    expect(row.volume, 0.4);
    expect(row.isProcessed, isTrue);
  });

  test('markSoundsProcessed avec une liste vide est sans effet', () async {
    await dataSource.markSoundsProcessed(const []);

    expect((await processedById()).values, everyElement(isFalse));
  });

  test('updateSoundSettings sans isProcessed ne change pas le statut',
      () async {
    await dataSource.markSoundsProcessed([ids[1]]);

    await dataSource.updateSoundSettings(id: ids[1], volume: 0.7);

    expect((await processedById())[ids[1]], isTrue);
  });
}
