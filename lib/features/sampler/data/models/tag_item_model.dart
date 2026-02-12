import '../../domain/entities/tag_item.dart' as domain;
import '../../../../core/database/database.dart' as db;

/// Mapping Drift -> domain pour TagItem.
class TagItemModel {
  static domain.TagItem toEntity(db.TagItem row) {
    return domain.TagItem(
      id: row.id,
      categoryId: row.categoryId,
      name: row.name,
      normalizedName: row.normalizedName,
      description: row.description,
    );
  }
}
