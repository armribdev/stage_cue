import 'package:drift/drift.dart';
import '../../../../core/database/database.dart' as db;
import '../../../../core/utils/string_utils.dart';
import '../../domain/entities/tag_category.dart' as domain;
import '../../domain/entities/tag_item.dart' as domain;
import '../../domain/entities/tag_category_with_tags.dart' as domain;
import '../models/tag_category_model.dart';
import '../models/tag_item_model.dart';

/// Source de données locale pour les tags
class LocalTagDataSource {
  final db.AppDatabase _database;

  LocalTagDataSource(this._database);

  Future<List<domain.TagCategory>> getCategories() async {
    final rows = await (_database.select(_database.tagCategories)
          ..orderBy([
            (c) => OrderingTerm(expression: c.sortOrder),
            (c) => OrderingTerm(expression: c.name),
          ]))
        .get();
    return rows.map(TagCategoryModel.toEntity).toList();
  }

  Future<List<domain.TagItem>> getTagsByCategory(int categoryId) async {
    final rows = await (_database.select(_database.tagItems)
          ..where((t) => t.categoryId.equals(categoryId))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
    return rows.map(TagItemModel.toEntity).toList();
  }

  Future<List<domain.TagItem>> getTagsForSound(int soundId) async {
    final query = _database.select(_database.tagItems).join([
      innerJoin(
        _database.soundTags,
        _database.soundTags.tagId.equalsExp(_database.tagItems.id),
      ),
    ])
      ..where(_database.soundTags.soundId.equals(soundId))
      ..orderBy([OrderingTerm(expression: _database.tagItems.name)]);

    final rows = await query.get();
    return rows
        .map((row) => row.readTable(_database.tagItems))
        .map(TagItemModel.toEntity)
        .toList();
  }

  Future<void> setTagsForSound(int soundId, List<int> tagIds) async {
    await _database.transaction(() async {
      await (_database.delete(_database.soundTags)
            ..where((t) => t.soundId.equals(soundId)))
          .go();
      for (final tagId in tagIds) {
        await _database.into(_database.soundTags).insert(
              db.SoundTagsCompanion.insert(
                soundId: soundId,
                tagId: tagId,
                addedAt: Value(DateTime.now()),
              ),
            );
      }
    });
  }

  Future<Set<int>> findSoundIdsByTagQuery(String query) async {
    final normalized = normalizeForSearch(query);
    if (normalized.isEmpty) {
      return {};
    }
    final like = '%$normalized%';
    final tagIdRows = await _database.customSelect(
      '''
        SELECT id FROM tags WHERE normalized_name LIKE ?
        UNION
        SELECT tag_id AS id FROM tag_aliases WHERE normalized_alias LIKE ?
      ''',
      variables: [Variable<String>(like), Variable<String>(like)],
    ).get();

    if (tagIdRows.isEmpty) {
      return {};
    }

    final tagIds = tagIdRows.map((r) => r.read<int>('id')).toList();
    final placeholders = List.filled(tagIds.length, '?').join(',');
    final soundRows = await _database.customSelect(
      'SELECT DISTINCT sound_id FROM sound_tags WHERE tag_id IN ($placeholders)',
      variables: [for (final id in tagIds) Variable<int>(id)],
    ).get();

    return soundRows.map((r) => r.read<int>('sound_id')).toSet();
  }

  Future<List<domain.TagCategoryWithTags>> getCatalog() async {
    final categories = await getCategories();
    final result = <domain.TagCategoryWithTags>[];
    for (final category in categories) {
      final tags = await getTagsByCategory(category.id);
      result.add(
        domain.TagCategoryWithTags(category: category, tags: tags),
      );
    }
    return result;
  }
}
