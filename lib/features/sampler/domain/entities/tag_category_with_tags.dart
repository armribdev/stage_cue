import 'tag_category.dart';
import 'tag_item.dart';

/// Catégorie avec sa liste de tags.
class TagCategoryWithTags {
  final TagCategory category;
  final List<TagItem> tags;

  TagCategoryWithTags({
    required this.category,
    required this.tags,
  });
}
