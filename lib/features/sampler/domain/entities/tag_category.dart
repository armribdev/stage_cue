/// Catégorie de tags (ex: ACTION, OBJET)
class TagCategory {
  final int id;
  final String name;
  final int color;
  final int sortOrder;
  final String? description;

  TagCategory({
    required this.id,
    required this.name,
    required this.color,
    required this.sortOrder,
    this.description,
  });
}
