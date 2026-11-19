import '../../domain/entities/tag_catalog_change.dart';

/// Déclaration à ajouter au catalogue du code (`database_tag_seed.dart`) pour
/// que les [changes] faits dans l'éditeur de développement arrivent chez tous
/// les utilisateurs (décisions 0046 et 0047).
///
/// Les modifications sont rejouées dans l'ordre et **compactées** : un tag créé
/// puis renommé ou supprimé dans la même session ne laisse que son état final,
/// une chaîne de fusions A → B puis B → C se réécrit A → C (sinon la fusion de A
/// viserait un tag d'accueil qui n'existe plus au catalogue). Renvoie `''` s'il
/// n'y a rien à déclarer.
String renderTagCatalogSnippet(List<TagCatalogChange> changes) {
  // catégorie → tag → alias, dans l'ordre d'apparition.
  final extra = <String, Map<String, Set<String>>>{};
  // Tags créés pendant la session : absents du catalogue du code, donc rien à
  // fusionner ni à élaguer pour eux, il suffit de ne plus les déclarer.
  final created = <(String, String)>{};
  final merged = <(String, String, String, String)>[];
  final pruned = <(String, String)>[];
  final removedAliases = <(String, String, String)>[];

  Set<String> aliasesOf(String category, String tag) =>
      (extra[category] ??= {})[tag] ??= <String>{};

  // Le tag [from] disparaît au profit de [into] (fusion ou renommage) : ses
  // alias de la session passent sur [into], et son nom devient un alias de
  // [into] sauf s'il n'a jamais existé au catalogue du code. [intoIsNew] : un
  // renommage fait naître [into], qui n'est pas encore au catalogue.
  void absorb(
    String fromCategory,
    String from,
    String intoCategory,
    String into, {
    required bool intoIsNew,
  }) {
    final carried = extra[fromCategory]?.remove(from) ?? const <String>{};
    final host = aliasesOf(intoCategory, into)..addAll(carried);
    for (var i = 0; i < merged.length; i++) {
      final m = merged[i];
      if (m.$3 == fromCategory && m.$4 == from) {
        merged[i] = (m.$1, m.$2, intoCategory, into);
      }
    }
    final wasCreated = created.remove((fromCategory, from));
    if (intoIsNew) created.add((intoCategory, into));
    if (wasCreated) return;
    host.add(from);
    merged.add((fromCategory, from, intoCategory, into));
  }

  for (final change in changes) {
    switch (change) {
      case TagCreated():
        created.add((change.category, change.tag));
        aliasesOf(change.category, change.tag).addAll(change.aliases);
      case TagAliasAdded():
        aliasesOf(change.category, change.tag).add(change.alias);
      case TagAliasRemoved():
        final session = extra[change.category]?[change.tag];
        if (session == null || !session.remove(change.alias)) {
          removedAliases.add((change.category, change.tag, change.alias));
        }
      case TagRenamed():
        absorb(
          change.category,
          change.from,
          change.category,
          change.to,
          intoIsNew: true,
        );
      case TagMerged():
        absorb(
          change.fromCategory,
          change.from,
          change.intoCategory,
          change.into,
          intoIsNew: false,
        );
      case TagDeleted():
        extra[change.category]?.remove(change.tag);
        // Un tag fusionné ici plus tôt n'a plus d'accueil : il est élagué.
        final orphans = merged
            .where((m) => m.$3 == change.category && m.$4 == change.tag)
            .toList();
        merged.removeWhere((m) => orphans.contains(m));
        pruned.addAll([for (final m in orphans) (m.$1, m.$2)]);
        if (!created.remove((change.category, change.tag))) {
          pruned.add((change.category, change.tag));
        }
    }
  }

  final out = StringBuffer();

  final extraEntries = [
    for (final category in extra.entries)
      for (final tag in category.value.entries)
        // Un tag existant sans alias à ajouter n'a rien à déclarer.
        if (tag.value.isNotEmpty || created.contains((category.key, tag.key)))
          (category.key, tag.key, tag.value),
  ];
  if (extraEntries.isNotEmpty) {
    out.writeln('// _extraTagCatalog : tags à créer, alias à ajouter');
    String? currentCategory;
    for (final (category, tag, aliases) in extraEntries) {
      if (category != currentCategory) {
        if (currentCategory != null) out.writeln('},');
        out.writeln('${_q(category)}: {');
        currentCategory = category;
      }
      out.writeln(
        aliases.isEmpty
            ? '  ${_q(tag)}: [],'
            : '  ${_q(tag)}: [${aliases.map(_q).join(', ')}],',
      );
    }
    out.writeln('},');
  }

  if (merged.isNotEmpty) {
    if (out.isNotEmpty) out.writeln();
    out.writeln('// mergedTags');
    for (final (fromCategory, from, intoCategory, into) in merged) {
      out.writeln(
        '(${_q(fromCategory)}, ${_q(from)}, ${_q(intoCategory)}, ${_q(into)}),',
      );
    }
  }

  if (pruned.isNotEmpty) {
    if (out.isNotEmpty) out.writeln();
    out.writeln('// prunedTags');
    for (final (category, tag) in pruned) {
      out.writeln('(${_q(category)}, ${_q(tag)}),');
    }
  }

  if (removedAliases.isNotEmpty) {
    if (out.isNotEmpty) out.writeln();
    out.writeln(
      '// À retirer à la main du catalogue (l\'alias est ajouté, jamais '
      'retiré, par la réconciliation) :',
    );
    for (final (category, tag, alias) in removedAliases) {
      out.writeln('//   alias ${_q(alias)} du tag ${_q(tag)} ($category)');
    }
  }

  return out.toString();
}

/// Littéral Dart entre apostrophes.
String _q(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$');
  return "'$escaped'";
}
