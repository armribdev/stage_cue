/// Tag individuel (ex: Impact, Voiture)
class TagItem {
  final int id;
  final int categoryId;
  final String name;
  final String normalizedName;
  final String? description;

  TagItem({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.normalizedName,
    this.description,
  });
}
