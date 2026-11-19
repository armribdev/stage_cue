/// Modification du catalogue de tags faite depuis l'éditeur de développement
/// (décision 0047). Les noms de catégorie et de tag (pas leurs identifiants)
/// suffisent à écrire la déclaration correspondante dans le catalogue du code.
sealed class TagCatalogChange {
  const TagCatalogChange();
}

final class TagCreated extends TagCatalogChange {
  final String category;
  final String tag;
  final List<String> aliases;

  const TagCreated({
    required this.category,
    required this.tag,
    this.aliases = const [],
  });
}

final class TagRenamed extends TagCatalogChange {
  final String category;
  final String from;
  final String to;

  const TagRenamed({
    required this.category,
    required this.from,
    required this.to,
  });
}

final class TagMerged extends TagCatalogChange {
  final String fromCategory;
  final String from;
  final String intoCategory;
  final String into;

  const TagMerged({
    required this.fromCategory,
    required this.from,
    required this.intoCategory,
    required this.into,
  });
}

final class TagDeleted extends TagCatalogChange {
  final String category;
  final String tag;

  const TagDeleted({required this.category, required this.tag});
}

final class TagAliasAdded extends TagCatalogChange {
  final String category;
  final String tag;
  final String alias;

  const TagAliasAdded({
    required this.category,
    required this.tag,
    required this.alias,
  });
}

final class TagAliasRemoved extends TagCatalogChange {
  final String category;
  final String tag;
  final String alias;

  const TagAliasRemoved({
    required this.category,
    required this.tag,
    required this.alias,
  });
}

/// Modification refusée (nom vide, doublon, tag protégé…). Le message est fait
/// pour être affiché tel quel.
class TagEditException implements Exception {
  final String message;

  const TagEditException(this.message);

  @override
  String toString() => message;
}
