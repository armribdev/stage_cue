import '../../domain/entities/tag_category.dart' as domain;
import '../../../../core/database/database.dart' as db;

/// Mapping Drift -> domain pour TagCategory.
class TagCategoryModel {
  static domain.TagCategory toEntity(db.TagCategory row) {
    return domain.TagCategory(
      id: row.id,
      name: row.name,
      color: row.color,
      sortOrder: row.sortOrder,
      description: row.description,
    );
  }
}
