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

  /// Tags de TOUS les sons, en une seule requête.
  ///
  /// La recherche affiche les tags de chaque résultat : un aller-retour par son
  /// ([getTagsForSound]) coûte des centaines de requêtes dès qu'une saisie large
  /// matche la bibliothèque. Le volume total reste modeste (quelques tags par
  /// son), donc on le charge d'un bloc pour le servir depuis la mémoire.
  Future<Map<int, List<domain.TagItem>>> getTagsForAllSounds() async {
    final query = _database.select(_database.soundTags).join([
      innerJoin(
        _database.tagItems,
        _database.tagItems.id.equalsExp(_database.soundTags.tagId),
      ),
    ])
      ..orderBy([OrderingTerm(expression: _database.tagItems.name)]);

    final rows = await query.get();
    final tagsBySound = <int, List<domain.TagItem>>{};
    for (final row in rows) {
      final soundId = row.readTable(_database.soundTags).soundId;
      final tag = TagItemModel.toEntity(row.readTable(_database.tagItems));
      (tagsBySound[soundId] ??= []).add(tag);
    }
    return tagsBySound;
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

    var tagIds = await _tagIdsMatchingSubstring(normalized);
    if (tagIds.isEmpty) {
      // Pas de correspondance exacte : peut-être une faute de frappe. Le
      // catalogue de tags reste petit (quelques centaines d'entrées au
      // plus), donc un balayage flou en mémoire est négligeable — contrairement
      // à un LIKE flou en SQL, qui ne pourrait pas utiliser d'index de toute façon.
      tagIds = await _tagIdsMatchingTypo(normalized);
    }
    if (tagIds.isEmpty) {
      return {};
    }

    final placeholders = List.filled(tagIds.length, '?').join(',');
    final soundRows = await _database.customSelect(
      'SELECT DISTINCT sound_id FROM sound_tags WHERE tag_id IN ($placeholders)',
      variables: [for (final id in tagIds) Variable<int>(id)],
    ).get();

    return soundRows.map((r) => r.read<int>('sound_id')).toSet();
  }

  Future<List<int>> _tagIdsMatchingSubstring(String normalized) async {
    final like = '%$normalized%';
    final rows = await _database.customSelect(
      '''
        SELECT id FROM tags WHERE normalized_name LIKE ?
        UNION
        SELECT tag_id AS id FROM tag_aliases WHERE normalized_alias LIKE ?
      ''',
      variables: [Variable<String>(like), Variable<String>(like)],
    ).get();
    return rows.map((r) => r.read<int>('id')).toList();
  }

  Future<List<int>> _tagIdsMatchingTypo(String normalized) async {
    final nameRows = await _database
        .customSelect('SELECT id, normalized_name FROM tags')
        .get();
    final aliasRows = await _database
        .customSelect('SELECT tag_id, normalized_alias FROM tag_aliases')
        .get();

    final matched = <int>{};
    for (final row in nameRows) {
      if (matchesWithTypo(row.read<String>('normalized_name'), normalized)) {
        matched.add(row.read<int>('id'));
      }
    }
    for (final row in aliasRows) {
      if (matchesWithTypo(row.read<String>('normalized_alias'), normalized)) {
        matched.add(row.read<int>('tag_id'));
      }
    }
    return matched.toList();
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
