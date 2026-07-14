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

  Future<int> insertCategory({String name = 'AMBIANCE'}) =>
      database.into(database.tagCategories).insert(
            db.TagCategoriesCompanion.insert(name: name, color: 0xFF000000),
          );

  Future<int> insertTag(String name, int categoryId) =>
      database.into(database.tagItems).insert(
            db.TagItemsCompanion.insert(
              categoryId: categoryId,
              name: name,
              normalizedName: normalizeForSearch(name),
            ),
          );

  Future<int> insertSound(String title) =>
      database.into(database.sounds).insert(
            db.SoundsCompanion.insert(title: title, filePath: '/x/$title.mp3'),
          );

  Future<void> linkSoundTag(int soundId, int tagId) =>
      database.into(database.soundTags).insert(
            db.SoundTagsCompanion.insert(soundId: soundId, tagId: tagId),
          );

  test('correspondance exacte (sous-chaîne) sur le nom du tag', () async {
    final categoryId = await insertCategory();
    final tagId = await insertTag('Explosion', categoryId);
    final soundId = await insertSound('Boom');
    await linkSoundTag(soundId, tagId);

    final result = await dataSource.findSoundIdsByTagQuery('explo');
    expect(result, {soundId});
  });

  test('faute de frappe (lettres interverties) sur le nom du tag -> repli flou',
      () async {
    final categoryId = await insertCategory();
    final tagId = await insertTag('Explosion', categoryId);
    final soundId = await insertSound('Boom');
    await linkSoundTag(soundId, tagId);

    final result = await dataSource.findSoundIdsByTagQuery('epxlosion');
    expect(result, {soundId});
  });

  test('faute de frappe sur un alias -> repli flou', () async {
    // Mots choisis pour ne pas entrer en collision avec les alias par
    // défaut (uniques globalement) insérés au premier lancement de la DB.
    final categoryId = await insertCategory();
    final tagId = await insertTag('Vaisselle cassée', categoryId);
    final soundId = await insertSound('Coup de feu');
    await linkSoundTag(soundId, tagId);
    await database.into(database.tagAliases).insert(
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
}
