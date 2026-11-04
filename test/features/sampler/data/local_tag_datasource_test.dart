import 'package:drift/drift.dart' show Value;
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

  group('tags de l’IA (décision 0030)', () {
    Future<void> linkAuto(int soundId, int tagId, {bool hidden = false}) =>
        database
            .into(database.soundAutoTags)
            .insert(
              db.SoundAutoTagsCompanion.insert(
                soundId: soundId,
                tagId: tagId,
                hidden: Value(hidden),
              ),
            );

    test('la recherche trouve un son par un tag de l’IA visible', () async {
      final categoryId = await insertCategory();
      final tagId = await insertTag('Angoisse', categoryId);
      final soundId = await insertSound('Musique');
      await linkAuto(soundId, tagId);

      expect(await dataSource.findSoundIdsByTagQuery('angoisse'), {soundId});
    });

    test('un tag de l’IA masqué n’est plus cherché', () async {
      final categoryId = await insertCategory();
      final tagId = await insertTag('Angoisse', categoryId);
      final soundId = await insertSound('Musique');
      await linkAuto(soundId, tagId, hidden: true);

      expect(await dataSource.findSoundIdsByTagQuery('angoisse'), isEmpty);
    });

    test('tags visibles = ceux de l’utilisateur + ceux de l’IA non masqués, '
        'sans doublon', () async {
      final categoryId = await insertCategory();
      final mine = await insertTag('Calme', categoryId);
      final both = await insertTag('Sombre', categoryId);
      final ai = await insertTag('Tension', categoryId);
      final masked = await insertTag('Triste', categoryId);
      final soundId = await insertSound('Musique');
      await linkSoundTag(soundId, mine);
      await linkSoundTag(soundId, both);
      await linkAuto(soundId, both);
      await linkAuto(soundId, ai);
      await linkAuto(soundId, masked, hidden: true);

      final visible = await dataSource.getVisibleTagsForSound(soundId);
      expect(visible.map((t) => t.name), ['Calme', 'Sombre', 'Tension']);

      final all = await dataSource.getTagsForAllSounds();
      expect(all[soundId]!.map((t) => t.name).toSet(), {
        'Calme',
        'Sombre',
        'Tension',
      });
      expect(all[soundId]!.length, 3, reason: 'Sombre n’est listé qu’une fois');
    });

    test('getTagsForSound ne renvoie que les tags de l’utilisateur : '
        'l’édition ne les mélange pas à ceux de l’IA', () async {
      final categoryId = await insertCategory();
      final mine = await insertTag('Calme', categoryId);
      final ai = await insertTag('Tension', categoryId);
      final soundId = await insertSound('Musique');
      await linkSoundTag(soundId, mine);
      await linkAuto(soundId, ai);

      final user = await dataSource.getTagsForSound(soundId);
      expect(user.map((t) => t.name), ['Calme']);
    });

    test(
      'masquer puis rétablir : la ligne reste, seul l’état change',
      () async {
        final categoryId = await insertCategory();
        final tagId = await insertTag('Tension', categoryId);
        final soundId = await insertSound('Musique');
        await linkAuto(soundId, tagId);

        await dataSource.setAutoTagHidden(soundId, tagId, hidden: true);
        var auto = await dataSource.getAutoTagsForSound(soundId);
        expect(auto, hasLength(1));
        expect(auto.single.hidden, isTrue);
        expect(await dataSource.getVisibleTagsForSound(soundId), isEmpty);

        await dataSource.setAutoTagHidden(soundId, tagId, hidden: false);
        auto = await dataSource.getAutoTagsForSound(soundId);
        expect(auto.single.hidden, isFalse);
        expect(
          (await dataSource.getVisibleTagsForSound(soundId)).single.name,
          'Tension',
        );
      },
    );
  });
}
