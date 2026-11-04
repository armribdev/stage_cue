import 'package:drift/drift.dart';
import '../../../../core/database/database.dart' as db;
import '../../../../core/utils/string_utils.dart';
import '../../domain/entities/sound_auto_tag.dart' as domain;
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
    final rows =
        await (_database.select(_database.tagCategories)..orderBy([
              (c) => OrderingTerm(expression: c.sortOrder),
              (c) => OrderingTerm(expression: c.name),
            ]))
            .get();
    return rows.map(TagCategoryModel.toEntity).toList();
  }

  Future<List<domain.TagItem>> getTagsByCategory(int categoryId) async {
    final rows =
        await (_database.select(_database.tagItems)
              ..where((t) => t.categoryId.equals(categoryId))
              ..orderBy([(t) => OrderingTerm(expression: t.name)]))
            .get();
    return rows.map(TagItemModel.toEntity).toList();
  }

  Future<List<domain.TagItem>> getTagsForSound(int soundId) async {
    final query =
        _database.select(_database.tagItems).join([
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

  /// Tags **visibles** d'un son : ceux de l'utilisateur plus ceux de l'IA non
  /// masqués (décision 0030), dédoublonnés. Pour l'affichage ; l'édition des
  /// tags de l'utilisateur passe par [getTagsForSound].
  Future<List<domain.TagItem>> getVisibleTagsForSound(int soundId) async {
    final user = await getTagsForSound(soundId);
    final auto = await getAutoTagsForSound(soundId);
    final seen = {for (final t in user) t.id};
    final all = [
      ...user,
      for (final a in auto)
        if (!a.hidden && seen.add(a.tag.id)) a.tag,
    ]..sort((a, b) => a.name.compareTo(b.name));
    return all;
  }

  /// Tags trouvés par l'IA pour un son, masqués compris (décision 0030).
  Future<List<domain.SoundAutoTag>> getAutoTagsForSound(int soundId) async {
    final query =
        _database.select(_database.soundAutoTags).join([
            innerJoin(
              _database.tagItems,
              _database.tagItems.id.equalsExp(_database.soundAutoTags.tagId),
            ),
          ])
          ..where(_database.soundAutoTags.soundId.equals(soundId))
          ..orderBy([OrderingTerm(expression: _database.tagItems.name)]);
    final rows = await query.get();
    return [
      for (final row in rows)
        domain.SoundAutoTag(
          tag: TagItemModel.toEntity(row.readTable(_database.tagItems)),
          hidden: row.readTable(_database.soundAutoTags).hidden,
        ),
    ];
  }

  /// Masque ou rétablit un tag de l'IA. La ligne n'est jamais supprimée : c'est
  /// la mémoire qui empêche l'IA de reposer un tag écarté. [when] date le
  /// changement (arbitre la fusion de synchro).
  Future<void> setAutoTagHidden(
    int soundId,
    int tagId, {
    required bool hidden,
    DateTime? when,
  }) async {
    await (_database.update(
      _database.soundAutoTags,
    )..where((t) => t.soundId.equals(soundId) & t.tagId.equals(tagId))).write(
      db.SoundAutoTagsCompanion(
        hidden: Value(hidden),
        updatedAt: Value(when ?? DateTime.now()),
      ),
    );
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
    ])..orderBy([OrderingTerm(expression: _database.tagItems.name)]);

    final rows = await query.get();
    final tagsBySound = <int, List<domain.TagItem>>{};
    for (final row in rows) {
      final soundId = row.readTable(_database.soundTags).soundId;
      final tag = TagItemModel.toEntity(row.readTable(_database.tagItems));
      (tagsBySound[soundId] ??= []).add(tag);
    }

    // Tags de l'IA non masqués (décision 0030), sans doublon avec ceux de
    // l'utilisateur.
    final autoRows =
        await (_database.select(_database.soundAutoTags).join([
                innerJoin(
                  _database.tagItems,
                  _database.tagItems.id.equalsExp(
                    _database.soundAutoTags.tagId,
                  ),
                ),
              ])
              ..where(_database.soundAutoTags.hidden.equals(false))
              ..orderBy([OrderingTerm(expression: _database.tagItems.name)]))
            .get();
    for (final row in autoRows) {
      final soundId = row.readTable(_database.soundAutoTags).soundId;
      final tag = TagItemModel.toEntity(row.readTable(_database.tagItems));
      final list = tagsBySound[soundId] ??= [];
      if (!list.any((t) => t.id == tag.id)) list.add(tag);
    }
    return tagsBySound;
  }

  Future<void> setTagsForSound(int soundId, List<int> tagIds) async {
    await _database.transaction(() async {
      await (_database.delete(
        _database.soundTags,
      )..where((t) => t.soundId.equals(soundId))).go();
      for (final tagId in tagIds) {
        await _database
            .into(_database.soundTags)
            .insert(
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
    final soundRows = await _database
        .customSelect(
          'SELECT sound_id FROM sound_tags WHERE tag_id IN ($placeholders) '
          'UNION '
          'SELECT sound_id FROM sound_auto_tags '
          'WHERE hidden = 0 AND tag_id IN ($placeholders)',
          variables: [
            for (final id in tagIds) Variable<int>(id),
            for (final id in tagIds) Variable<int>(id),
          ],
        )
        .get();

    return soundRows.map((r) => r.read<int>('sound_id')).toSet();
  }

  Future<List<int>> _tagIdsMatchingSubstring(String normalized) async {
    final like = '%$normalized%';
    final rows = await _database
        .customSelect(
          '''
        SELECT id FROM tags WHERE normalized_name LIKE ?
        UNION
        SELECT tag_id AS id FROM tag_aliases WHERE normalized_alias LIKE ?
      ''',
          variables: [Variable<String>(like), Variable<String>(like)],
        )
        .get();
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
      result.add(domain.TagCategoryWithTags(category: category, tags: tags));
    }
    return result;
  }
}
