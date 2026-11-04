import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/core/utils/string_utils.dart';
import 'package:stage_cue/features/sampler/data/datasources/local_tag_datasource.dart';

/// Vérifie la recherche de sons par tag, y compris le repli tolérant aux
/// fautes de frappe quand aucune correspondance exacte n'est trouvée.
void main() {
  late db.AppDatabase database;
  late LocalTagDataSource dataSource;

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    dataSource = LocalTagDataSource(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<int> insertCategory({String name = 'AMBIANCE'}) => database
      .into(database.tagCategories)
      .insert(db.TagCategoriesCompanion.insert(name: name, color: 0xFF000000));

  Future<int> insertTag(String name, int categoryId) => database
      .into(database.tagItems)
      .insert(
        db.TagItemsCompanion.insert(
          categoryId: categoryId,
          name: name,
          normalizedName: normalizeForSearch(name),
        ),
      );

  Future<int> insertSound(String title) => database
      .into(database.sounds)
      .insert(
        db.SoundsCompanion.insert(
          title: title,
          displayName: title,
          filePath: '/x/$title.mp3',
        ),
      );

  Future<void> linkSoundTag(int soundId, int tagId) => database
      .into(database.soundTags)
      .insert(db.SoundTagsCompanion.insert(soundId: soundId, tagId: tagId));

  test('correspondance exacte (sous-chaîne) sur le nom du tag', () async {
    final categoryId = await insertCategory();
    final tagId = await insertTag('Explosion', categoryId);
    final soundId = await insertSound('Boom');
    await linkSoundTag(soundId, tagId);

    final result = await dataSource.findSoundIdsByTagQuery('explo');
    expect(result, {soundId});
  });

  test(
    'faute de frappe (lettres interverties) sur le nom du tag -> repli flou',
    () async {
      final categoryId = await insertCategory();
      final tagId = await insertTag('Explosion', categoryId);
      final soundId = await insertSound('Boom');
      await linkSoundTag(soundId, tagId);

      final result = await dataSource.findSoundIdsByTagQuery('epxlosion');
      expect(result, {soundId});
    },
  );

  test('faute de frappe sur un alias -> repli flou', () async {
    // Mots choisis pour ne pas entrer en collision avec les alias par
    // défaut (uniques globalement) insérés au premier lancement de la DB.
    final categoryId = await insertCategory();
    final tagId = await insertTag('Vaisselle cassée', categoryId);
    final soundId = await insertSound('Coup de feu');
    await linkSoundTag(soundId, tagId);
    await database
        .into(database.tagAliases)
        .insert(
          db.TagAliasesCompanion.insert(
            tagId: tagId,
            alias: 'porcelaine',
            normalizedAlias: normalizeForSearch('porcelaine'),
          ),
        );

    final result = await dataSource.findSoundIdsByTagQuery('procelaine');
    expect(result, {soundId});
  });

  test('aucune correspondance, même floue -> ensemble vide', () async {
    final categoryId = await insertCategory();
    final tagId = await insertTag('Explosion', categoryId);
    final soundId = await insertSound('Boom');
    await linkSoundTag(soundId, tagId);

    final result = await dataSource.findSoundIdsByTagQuery('xyzzyplugh');
    expect(result, isEmpty);
  });

  group('suggestions de l’IA (décision 0031)', () {
    Future<void> linkAuto(int soundId, int tagId, {double score = 0.4}) =>
        database
            .into(database.soundAutoTags)
            .insert(
              db.SoundAutoTagsCompanion.insert(
                soundId: soundId,
                tagId: tagId,
                score: score,
              ),
            );

    test(
      'la recherche ne trouve pas un son par une simple suggestion',
      () async {
        final categoryId = await insertCategory();
        final tagId = await insertTag('Angoisse', categoryId);
        final soundId = await insertSound('Musique');
        await linkAuto(soundId, tagId);

        expect(await dataSource.findSoundIdsByTagQuery('angoisse'), isEmpty);

        // Acceptée (ajoutée aux tags du son), elle est cherchable.
        await linkSoundTag(soundId, tagId);
        expect(await dataSource.findSoundIdsByTagQuery('angoisse'), {soundId});
      },
    );

    test('les suggestions ne se mêlent pas aux tags listés', () async {
      final categoryId = await insertCategory();
      final mine = await insertTag('Calme', categoryId);
      final ai = await insertTag('Tension', categoryId);
      final soundId = await insertSound('Musique');
      await linkSoundTag(soundId, mine);
      await linkAuto(soundId, ai);

      expect((await dataSource.getTagsForSound(soundId)).map((t) => t.name), [
        'Calme',
      ]);
      final all = await dataSource.getTagsForAllSounds();
      expect(all[soundId]!.map((t) => t.name), ['Calme']);
    });

    test(
      'suggestions renvoyées avec leur confiance, la plus sûre d’abord',
      () async {
        final categoryId = await insertCategory();
        final low = await insertTag('Calme', categoryId);
        final high = await insertTag('Tension', categoryId);
        final mid = await insertTag('Triste', categoryId);
        final soundId = await insertSound('Musique');
        await linkAuto(soundId, low, score: 0.1);
        await linkAuto(soundId, high, score: 0.6);
        await linkAuto(soundId, mid, score: 0.3);

        final auto = await dataSource.getAutoTagsForSound(soundId);
        expect(auto.map((a) => a.tag.name), ['Tension', 'Triste', 'Calme']);
        expect(auto.map((a) => a.score), [0.6, 0.3, 0.1]);
      },
    );
  });
}
