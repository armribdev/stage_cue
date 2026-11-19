import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/features/sampler/domain/entities/tag_catalog_change.dart';
import 'package:stage_cue/features/sampler/presentation/utils/tag_catalog_snippet.dart';

/// Déclaration tirée des modifications de l'éditeur de catalogue (décision
/// 0047) : ce que l'on colle dans `database_tag_seed.dart`.
void main() {
  test('rien à déclarer', () {
    expect(renderTagCatalogSnippet(const []), '');
  });

  test('un tag créé avec ses alias va dans le catalogue des tags ajoutés', () {
    expect(
      renderTagCatalogSnippet(const [
        TagCreated(
          category: 'AMBIANCE',
          tag: 'Cirque',
          aliases: ['chapiteau', 'clown'],
        ),
        TagAliasAdded(category: 'AMBIANCE', tag: 'Cirque', alias: 'piste'),
      ]),
      "// _extraTagCatalog : tags à créer, alias à ajouter\n"
      "'AMBIANCE': {\n"
      "  'Cirque': ['chapiteau', 'clown', 'piste'],\n"
      "},\n",
    );
  });

  test('une fusion déclare mergedTags et le nom en alias de l\'accueil', () {
    expect(
      renderTagCatalogSnippet(const [
        TagMerged(
          fromCategory: 'AMBIANCE',
          from: 'Urbain',
          intoCategory: 'AMBIANCE',
          into: 'Nature',
        ),
      ]),
      "// _extraTagCatalog : tags à créer, alias à ajouter\n"
      "'AMBIANCE': {\n"
      "  'Nature': ['Urbain'],\n"
      "},\n"
      "\n"
      "// mergedTags\n"
      "('AMBIANCE', 'Urbain', 'AMBIANCE', 'Nature'),\n",
    );
  });

  test('un renommage est une fusion vers le nouveau nom', () {
    final snippet = renderTagCatalogSnippet(const [
      TagRenamed(category: 'OBJET', from: 'Porte', to: 'Porte d\'entrée'),
    ]);
    expect(snippet, contains("'Porte d\\'entrée': ['Porte']"));
    expect(
      snippet,
      contains("('OBJET', 'Porte', 'OBJET', 'Porte d\\'entrée'),"),
    );
  });

  test('une suppression déclare prunedTags', () {
    expect(
      renderTagCatalogSnippet(const [
        TagDeleted(category: 'OBJET', tag: 'Livre'),
      ]),
      "// prunedTags\n"
      "('OBJET', 'Livre'),\n",
    );
  });

  test('un tag créé puis supprimé ne laisse rien', () {
    expect(
      renderTagCatalogSnippet(const [
        TagCreated(category: 'AMBIANCE', tag: 'Cirque', aliases: ['clown']),
        TagDeleted(category: 'AMBIANCE', tag: 'Cirque'),
      ]),
      '',
    );
  });

  test('un tag créé puis renommé n\'est déclaré que sous son nom final', () {
    final snippet = renderTagCatalogSnippet(const [
      TagCreated(category: 'AMBIANCE', tag: 'Cirque', aliases: ['clown']),
      TagRenamed(category: 'AMBIANCE', from: 'Cirque', to: 'Chapiteau'),
    ]);
    expect(snippet, contains("'Chapiteau': ['clown']"));
    expect(snippet, isNot(contains('mergedTags')));
    expect(snippet, isNot(contains("'Cirque'")));
  });

  test('une chaîne de fusions A → B puis B → C se réécrit A → C', () {
    final snippet = renderTagCatalogSnippet(const [
      TagMerged(
        fromCategory: 'AMBIANCE',
        from: 'Aube',
        intoCategory: 'AMBIANCE',
        into: 'Matin',
      ),
      TagMerged(
        fromCategory: 'AMBIANCE',
        from: 'Matin',
        intoCategory: 'AMBIANCE',
        into: 'Jour',
      ),
    ]);
    expect(snippet, contains("('AMBIANCE', 'Aube', 'AMBIANCE', 'Jour'),"));
    expect(snippet, contains("('AMBIANCE', 'Matin', 'AMBIANCE', 'Jour'),"));
    expect(snippet, isNot(contains("'AMBIANCE', 'Matin'),")));
  });

  test('supprimer l\'accueil d\'une fusion élague le tag fusionné', () {
    final snippet = renderTagCatalogSnippet(const [
      TagMerged(
        fromCategory: 'AMBIANCE',
        from: 'Aube',
        intoCategory: 'AMBIANCE',
        into: 'Matin',
      ),
      TagDeleted(category: 'AMBIANCE', tag: 'Matin'),
    ]);
    expect(snippet, isNot(contains('mergedTags')));
    expect(snippet, contains("// prunedTags\n('AMBIANCE', 'Aube'),"));
    expect(snippet, contains("('AMBIANCE', 'Matin'),"));
  });

  test('un alias retiré du catalogue existant se signale à la main', () {
    final snippet = renderTagCatalogSnippet(const [
      TagAliasRemoved(category: 'AMBIANCE', tag: 'Nature', alias: 'sea'),
    ]);
    expect(snippet, contains("alias 'sea' du tag 'Nature' (AMBIANCE)"));
  });

  test('un alias ajouté puis retiré dans la session ne laisse rien', () {
    expect(
      renderTagCatalogSnippet(const [
        TagAliasAdded(category: 'AMBIANCE', tag: 'Nature', alias: 'bois'),
        TagAliasRemoved(category: 'AMBIANCE', tag: 'Nature', alias: 'bois'),
      ]),
      '',
    );
  });

  test('un tag créé sans alias est tout de même déclaré', () {
    expect(
      renderTagCatalogSnippet(const [
        TagCreated(category: 'AMBIANCE', tag: 'Cirque'),
      ]),
      "// _extraTagCatalog : tags à créer, alias à ajouter\n"
      "'AMBIANCE': {\n"
      "  'Cirque': [],\n"
      "},\n",
    );
  });

  test('échappe les apostrophes, antislashs et dollars', () {
    final snippet = renderTagCatalogSnippet(const [
      TagDeleted(category: 'EMOTION_STYLE', tag: r"Musique d'ambiance $\"),
    ]);
    expect(snippet, contains(r"'Musique d\'ambiance \$\\'"));
  });
}
