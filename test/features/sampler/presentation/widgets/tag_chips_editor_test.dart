// Éditeur de tags : le panneau reste ouvert entre deux ajouts, Entrée valide le
// premier résultat d'une recherche, l'ordre est insensible à la casse/accents,
// et le panneau se referme seul quand il ne reste rien à ajouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/features/sampler/domain/entities/tag_category.dart';
import 'package:stage_cue/features/sampler/domain/entities/tag_category_with_tags.dart';
import 'package:stage_cue/features/sampler/domain/entities/tag_item.dart';
import 'package:stage_cue/features/sampler/presentation/widgets/tag_chips_editor.dart';

TagItem _tag(int id, int categoryId, String name) => TagItem(
  id: id,
  categoryId: categoryId,
  name: name,
  normalizedName: name.toLowerCase(),
);

TagCategory _category(int id, String name, int color) =>
    TagCategory(id: id, name: name, color: color, sortOrder: id);

void main() {
  final catalog = [
    TagCategoryWithTags(
      category: _category(1, 'ACTION', 0xFFE53935),
      tags: [_tag(1, 1, 'Zen'), _tag(2, 1, 'Épique')],
    ),
    TagCategoryWithTags(
      category: _category(2, 'OBJET', 0xFF1E88E5),
      tags: [_tag(3, 2, 'Porte'), _tag(4, 2, 'Voiture')],
    ),
  ];

  Future<Set<int>> pump(
    WidgetTester tester, {
    List<TagCategoryWithTags>? tagCatalog,
    Set<int> initial = const {},
  }) async {
    final selected = {...initial};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TagChipsEditor(
              tagCatalog: tagCatalog ?? catalog,
              selectedTagIds: selected,
              onTagAdded: (id) => setState(() => selected.add(id)),
              onTagRemoved: (id) => setState(() => selected.remove(id)),
            ),
          ),
        ),
      ),
    );
    return selected;
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
  }

  Finder row(String name) => find.descendant(
    of: find.byType(SingleChildScrollView),
    matching: find.text(name),
  );

  testWidgets('catalogue vide : message dédié, pas de bouton +', (
    tester,
  ) async {
    await pump(tester, tagCatalog: const []);

    expect(find.text('Aucun tag disponible'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets('le panneau reste ouvert après un ajout, recherche vidée', (
    tester,
  ) async {
    final selected = await pump(tester);
    await openPicker(tester);

    await tester.enterText(find.byType(TextField), 'por');
    await tester.pump();
    await tester.tap(row('Porte'));
    await tester.pumpAndSettle();

    expect(selected, {3});
    // Panneau toujours là, champ vidé, les autres tags à nouveau proposés.
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
    expect(row('Voiture'), findsOneWidget);
    expect(row('Porte'), findsNothing);
  });

  testWidgets('Entrée ajoute le premier résultat de la recherche', (
    tester,
  ) async {
    final selected = await pump(tester);
    await openPicker(tester);

    await tester.enterText(find.byType(TextField), 'epi');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(selected, {2});
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('Entrée sans saisie n\'ajoute rien', (tester) async {
    final selected = await pump(tester);
    await openPicker(tester);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(selected, isEmpty);
  });

  testWidgets('Entrée sans résultat n\'ajoute rien', (tester) async {
    final selected = await pump(tester);
    await openPicker(tester);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(selected, isEmpty);
    expect(find.text('Aucun résultat'), findsOneWidget);
  });

  testWidgets('puces triées sans tenir compte des accents ni de la casse', (
    tester,
  ) async {
    await pump(tester, initial: {1, 2, 3});

    final labels = tester
        .widgetList<InputChip>(find.byType(InputChip))
        .map((c) => (c.label as Text).data)
        .toList();
    expect(labels, ['Épique', 'Porte', 'Zen']);
  });

  testWidgets('le panneau se referme seul après le dernier tag disponible', (
    tester,
  ) async {
    final selected = await pump(tester, initial: {1, 2, 3});
    await openPicker(tester);

    await tester.tap(row('Voiture'));
    await tester.pumpAndSettle();

    expect(selected, {1, 2, 3, 4});
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets(
    'filtre de catégorie épuisé : retombe sur « Tous » au lieu d\'une liste vide',
    (tester) async {
      await pump(tester);
      await openPicker(tester);

      // Filtre « Objets », puis on pose les deux tags de la catégorie... il
      // reste alors uniquement des « Actions » : le filtre doit être ignoré.
      await tester.tap(find.text('Objets'));
      await tester.pumpAndSettle();
      await tester.tap(row('Porte'));
      await tester.pumpAndSettle();
      await tester.tap(row('Voiture'));
      await tester.pumpAndSettle();

      expect(find.text('Aucun résultat'), findsNothing);
      expect(row('Zen'), findsOneWidget);
      expect(row('Épique'), findsOneWidget);
    },
  );

  testWidgets('le bouton + porte une infobulle', (tester) async {
    await pump(tester);

    expect(find.byTooltip('Ajouter un tag'), findsOneWidget);
    await openPicker(tester);
    expect(find.byTooltip('Fermer la liste des tags'), findsOneWidget);
  });
}
