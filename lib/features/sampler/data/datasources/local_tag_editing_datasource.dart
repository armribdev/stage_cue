import 'package:drift/drift.dart';

import '../../../../core/autotag/mood_tagging.dart';
import '../../../../core/database/database.dart' as db;
import '../../../../core/utils/string_utils.dart';
import '../../domain/entities/tag_catalog_change.dart';
import '../../domain/entities/tag_category.dart';
import '../../domain/entities/tag_item.dart';
import 'local_tag_datasource.dart';

/// Un alias de tag avec son identifiant (pour le retirer).
typedef TagAliasEntry = ({int id, String alias});

/// Un tag du catalogue avec ce que l'éditeur en affiche.
typedef TagEditorEntry = ({
  TagItem tag,

  /// Nombre de sons qui portent ce tag (`sound_tags`).
  int usage,
  List<TagAliasEntry> aliases,
});

typedef TagEditorCategory = ({
  TagCategory category,
  List<TagEditorEntry> entries,
});

/// Écritures de l'éditeur de catalogue de développement (décision 0047).
///
/// Chaque opération s'applique à la base locale et **renvoie la modification
/// faite** : l'éditeur les accumule pour en déduire la déclaration à ajouter au
/// catalogue du code (`database_tag_seed.dart`), seule source de vérité
/// (décision 0046). Une opération refusée lève [TagEditException], sans rien
/// avoir écrit.
///
/// Les tags visés par une ambiance de l'analyse automatique ([isMoodTag]) ne se
/// renomment, ne se fusionnent ailleurs et ne se suppriment pas : l'analyse les
/// retrouve par nom.
class LocalTagEditingDataSource {
  final db.AppDatabase _database;
  final LocalTagDataSource _tags;

  LocalTagEditingDataSource(this._database)
    : _tags = LocalTagDataSource(_database);

  /// Catalogue complet : catégories, tags, usages et alias.
  Future<List<TagEditorCategory>> load() async {
    final catalog = await _tags.getCatalog();

    final usage = <int, int>{};
    for (final row
        in await _database
            .customSelect(
              'SELECT tag_id, COUNT(*) AS n FROM sound_tags GROUP BY tag_id',
            )
            .get()) {
      usage[row.read<int>('tag_id')] = row.read<int>('n');
    }

    final aliases = <int, List<TagAliasEntry>>{};
    for (final row
        in await _database
            .customSelect(
              'SELECT id, tag_id, alias FROM tag_aliases ORDER BY normalized_alias',
            )
            .get()) {
      (aliases[row.read<int>('tag_id')] ??= []).add((
        id: row.read<int>('id'),
        alias: row.read<String>('alias'),
      ));
    }

    return [
      for (final entry in catalog)
        (
          category: entry.category,
          entries: [
            for (final tag in entry.tags)
              (
                tag: tag,
                usage: usage[tag.id] ?? 0,
                aliases: aliases[tag.id] ?? const [],
              ),
          ],
        ),
    ];
  }

  Future<TagCatalogChange> createTag({
    required int categoryId,
    required String name,
    List<String> aliases = const [],
  }) {
    return _database.transaction(() async {
      final clean = _cleanName(name);
      final category = await _categoryName(categoryId);
      final normalized = normalizeForSearch(clean);
      if (await _tagIdIn(categoryId, normalized) != null) {
        throw TagEditException('« $clean » existe déjà dans $category.');
      }
      final tagId = await _database
          .into(_database.tagItems)
          .insert(
            db.TagItemsCompanion.insert(
              categoryId: categoryId,
              name: clean,
              normalizedName: normalized,
            ),
          );
      final added = <String>[];
      for (final alias in aliases) {
        added.add(await _insertAlias(tagId, alias));
      }
      return TagCreated(category: category, tag: clean, aliases: added);
    });
  }

  /// Renomme en place (le tag garde son identifiant, donc ses usages). L'ancien
  /// nom reste cherchable : il devient un alias, comme pour une fusion.
  Future<TagCatalogChange> renameTag({
    required int tagId,
    required String name,
  }) {
    return _database.transaction(() async {
      final clean = _cleanName(name);
      final tag = await _tag(tagId);
      _refuseMoodTag(tag, 'renommé');
      final normalized = normalizeForSearch(clean);
      final other = await _tagIdIn(tag.categoryId, normalized);
      if (other != null && other != tagId) {
        throw TagEditException('« $clean » existe déjà dans ${tag.category}.');
      }
      if (clean == tag.name) {
        throw const TagEditException('Le nom est inchangé.');
      }
      await _database.customStatement(
        'UPDATE tags SET name = ?, normalized_name = ? WHERE id = ?',
        [clean, normalized, tagId],
      );
      // Une simple retouche de casse ou d'accent garde le même nom normalisé :
      // pas d'alias identique au tag.
      if (normalizeForSearch(tag.name) != normalized) {
        await _database.customStatement(
          'INSERT OR IGNORE INTO tag_aliases (tag_id, alias, normalized_alias) '
          'VALUES (?, ?, ?)',
          [tagId, tag.name, normalizeForSearch(tag.name)],
        );
      }
      return TagRenamed(category: tag.category, from: tag.name, to: clean);
    });
  }

  /// Fusionne [fromId] dans [intoId] : usages, suggestions et alias suivent, le
  /// nom de [fromId] devient un alias de [intoId].
  Future<TagCatalogChange> mergeTag({
    required int fromId,
    required int intoId,
  }) {
    return _database.transaction(() async {
      if (fromId == intoId) {
        throw const TagEditException(
          'Un tag ne se fusionne pas dans lui-même.',
        );
      }
      final from = await _tag(fromId);
      final into = await _tag(intoId);
      _refuseMoodTag(from, 'fusionné ailleurs');
      await _database.customStatement(
        'INSERT OR IGNORE INTO tag_aliases (tag_id, alias, normalized_alias) '
        'VALUES (?, ?, ?)',
        [intoId, from.name, normalizeForSearch(from.name)],
      );
      await _database.mergeTagInto(from: fromId, into: intoId);
      return TagMerged(
        fromCategory: from.category,
        from: from.name,
        intoCategory: into.category,
        into: into.name,
      );
    });
  }

  /// Supprime le tag **avec** ses usages, suggestions et alias : à réserver à
  /// un tag sans famille d'accueil (sinon, fusionner).
  Future<TagCatalogChange> deleteTag(int tagId) {
    return _database.transaction(() async {
      final tag = await _tag(tagId);
      _refuseMoodTag(tag, 'supprimé');
      for (final table in const ['sound_tags', 'sound_auto_tags']) {
        await _database.customStatement('DELETE FROM $table WHERE tag_id = ?', [
          tagId,
        ]);
      }
      await _database.customStatement(
        'DELETE FROM tag_aliases WHERE tag_id = ?',
        [tagId],
      );
      await _database.customStatement('DELETE FROM tags WHERE id = ?', [tagId]);
      return TagDeleted(category: tag.category, tag: tag.name);
    });
  }

  Future<TagCatalogChange> addAlias({
    required int tagId,
    required String alias,
  }) {
    return _database.transaction(() async {
      final tag = await _tag(tagId);
      final added = await _insertAlias(tagId, alias);
      return TagAliasAdded(category: tag.category, tag: tag.name, alias: added);
    });
  }

  Future<TagCatalogChange> removeAlias(int aliasId) {
    return _database.transaction(() async {
      final row = await _database
          .customSelect(
            'SELECT tag_id, alias FROM tag_aliases WHERE id = ?',
            variables: [Variable<int>(aliasId)],
          )
          .getSingleOrNull();
      if (row == null) throw const TagEditException('Alias introuvable.');
      final tag = await _tag(row.read<int>('tag_id'));
      await _database.customStatement('DELETE FROM tag_aliases WHERE id = ?', [
        aliasId,
      ]);
      return TagAliasRemoved(
        category: tag.category,
        tag: tag.name,
        alias: row.read<String>('alias'),
      );
    });
  }

  // ── Lectures et gardes ────────────────────────────────────────────────────

  String _cleanName(String name) {
    final clean = name.trim();
    if (clean.isEmpty) throw const TagEditException('Le nom est vide.');
    return clean;
  }

  Future<String> _categoryName(int categoryId) async {
    final row = await _database
        .customSelect(
          'SELECT name FROM tag_categories WHERE id = ?',
          variables: [Variable<int>(categoryId)],
        )
        .getSingleOrNull();
    if (row == null) throw const TagEditException('Catégorie introuvable.');
    return row.read<String>('name');
  }

  Future<({int categoryId, String category, String name})> _tag(
    int tagId,
  ) async {
    final row = await _database
        .customSelect(
          'SELECT t.category_id, t.name, c.name AS category FROM tags t '
          'JOIN tag_categories c ON c.id = t.category_id WHERE t.id = ?',
          variables: [Variable<int>(tagId)],
        )
        .getSingleOrNull();
    if (row == null) throw const TagEditException('Tag introuvable.');
    return (
      categoryId: row.read<int>('category_id'),
      category: row.read<String>('category'),
      name: row.read<String>('name'),
    );
  }

  Future<int?> _tagIdIn(int categoryId, String normalizedName) async {
    final row = await _database
        .customSelect(
          'SELECT id FROM tags WHERE category_id = ? AND normalized_name = ? '
          'LIMIT 1',
          variables: [
            Variable<int>(categoryId),
            Variable<String>(normalizedName),
          ],
        )
        .getSingleOrNull();
    return row?.read<int>('id');
  }

  void _refuseMoodTag(
    ({int categoryId, String category, String name}) tag,
    String verb,
  ) {
    if (isMoodTag(category: tag.category, tag: tag.name)) {
      throw TagEditException(
        '« ${tag.name} » est une ambiance de l\'analyse automatique : '
        'il ne peut pas être $verb (voir kMoods).',
      );
    }
  }

  /// Pose l'alias et renvoie sa forme rognée. Les alias sont uniques sur tout
  /// le catalogue : un alias déjà pris est refusé en nommant son propriétaire.
  Future<String> _insertAlias(int tagId, String alias) async {
    final clean = alias.trim();
    if (clean.isEmpty) throw const TagEditException('L\'alias est vide.');
    final normalized = normalizeForSearch(clean);
    final owner = await _database
        .customSelect(
          'SELECT t.name FROM tag_aliases a JOIN tags t ON t.id = a.tag_id '
          'WHERE a.normalized_alias = ? LIMIT 1',
          variables: [Variable<String>(normalized)],
        )
        .getSingleOrNull();
    if (owner != null) {
      throw TagEditException(
        'L\'alias « $clean » est déjà porté par « ${owner.read<String>('name')} ».',
      );
    }
    await _database
        .into(_database.tagAliases)
        .insert(
          db.TagAliasesCompanion.insert(
            tagId: tagId,
            alias: clean,
            normalizedAlias: normalized,
          ),
        );
    return clean;
  }
}
