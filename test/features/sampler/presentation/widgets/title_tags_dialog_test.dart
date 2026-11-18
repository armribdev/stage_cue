// Aperçu de l'action groupée « Tags des titres » (décision 0041) : rien n'est
// retenu sans confirmation, et chaque tag se retire d'un toucher.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/utils/title_tag_matcher.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';
import 'package:stage_cue/features/sampler/domain/entities/tag_category.dart';
import 'package:stage_cue/features/sampler/domain/entities/tag_category_with_tags.dart';
import 'package:stage_cue/features/sampler/domain/entities/tag_item.dart';
import 'package:stage_cue/features/sampler/presentation/utils/title_tag_proposals.dart';
import 'package:stage_cue/features/sampler/presentation/widgets/title_tags_dialog.dart';

void main() {
  const sonnerieId = 1;
  const porteId = 2;

  TagItem tag(int id, String name) => TagItem(
    id: id,
    categoryId: 1,
    name: name,
    normalizedName: name.toLowerCase(),
  );

  Sound sound(int id, String title) => Sound(
    id: id,
    title: title,
    filePath: '/cache/$title.wav',
    createdAt: DateTime(2026, 11, 18),
  );

  final catalog = [
    TagCategoryWithTags(
      category: TagCategory(
        id: 1,
        name: 'OBJET',
        color: 0xFF7C5CFF,
        sortOrder: 0,
      ),
      tags: [tag(sonnerieId, 'Sonnerie'), tag(porteId, 'Porte')],
    ),
  ];

  final proposals = <TitleTagProposal>[
    (
      sound: sound(10, 'Sonette porte'),
      matches: const [
        TitleTagMatch(tagId: sonnerieId, matchedText: 'Sonette'),
        TitleTagMatch(tagId: porteId, matchedText: 'porte'),
      ],
    ),
    (
      sound: sound(11, 'Porte 2'),
      matches: const [TitleTagMatch(tagId: porteId, matchedText: 'Porte')],
    ),
  ];

  Future<Map<int, Set<int>>?> openDialog(
    WidgetTester tester,
    Future<void> Function() interact,
  ) async {
    Map<int, Set<int>>? result;
    var closed = false;
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await TitleTagsDialog.show(
                  context,
                  proposals: proposals,
                  tagCatalog: catalog,
                );
                closed = true;
              },
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await interact();
    await tester.pumpAndSettle();
    expect(closed, isTrue, reason: 'le dialogue doit s’être fermé');
    return result;
  }

  testWidgets('affiche chaque son avec ses tags et le total à ajouter', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TitleTagsDialog(proposals: proposals, tagCatalog: catalog),
        ),
      ),
    );

    expect(find.text('Sonette porte'), findsOneWidget);
    expect(find.text('Porte 2'), findsOneWidget);
    expect(find.text('Sonnerie'), findsOneWidget);
    expect(find.text('Porte'), findsNWidgets(2));
    expect(find.text('Ajouter 3 tags à 2 sons'), findsOneWidget);
  });

  testWidgets('confirmer renvoie tous les tags proposés', (tester) async {
    final result = await openDialog(tester, () async {
      await tester.tap(find.text('Ajouter 3 tags à 2 sons'));
    });

    expect(result, {
      10: {sonnerieId, porteId},
      11: {porteId},
    });
  });

  testWidgets('retirer un tag l’exclut du résultat et du total', (
    tester,
  ) async {
    final result = await openDialog(tester, () async {
      await tester.tap(find.byTooltip('Ne pas ajouter').first);
      await tester.pumpAndSettle();
      expect(find.text('Ajouter 2 tags à 2 sons'), findsOneWidget);
      await tester.tap(find.text('Ajouter 2 tags à 2 sons'));
    });

    expect(result, {
      10: {porteId},
      11: {porteId},
    });
  });

  testWidgets('retirer le dernier tag d’un son le retire du résultat', (
    tester,
  ) async {
    final result = await openDialog(tester, () async {
      // Retire Sonnerie et Porte du premier son : il ne reste que le second.
      await tester.tap(find.byTooltip('Ne pas ajouter').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ne pas ajouter').first);
      await tester.pumpAndSettle();
      expect(find.text('Ajouter 1 tag à 1 son'), findsOneWidget);
      await tester.tap(find.text('Ajouter 1 tag à 1 son'));
    });

    expect(result, {
      11: {porteId},
    });
  });

  testWidgets('un tag retiré se remet d’un toucher sur sa pastille fantôme', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TitleTagsDialog(proposals: proposals, tagCatalog: catalog),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Ne pas ajouter').first);
    await tester.pump();
    expect(find.text('Ajouter 2 tags à 2 sons'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('title-tags-10-$sonnerieId')));
    await tester.pump();
    expect(find.text('Ajouter 3 tags à 2 sons'), findsOneWidget);
  });

  testWidgets('annuler ne renvoie rien', (tester) async {
    final result = await openDialog(tester, () async {
      await tester.tap(find.text('Annuler'));
    });

    expect(result, isNull);
  });

  testWidgets('tout retirer désactive la confirmation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TitleTagsDialog(proposals: proposals, tagCatalog: catalog),
        ),
      ),
    );

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Ne pas ajouter').first);
      await tester.pump();
    }

    final confirm = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(confirm.onPressed, isNull);
    expect(find.text('Aucun tag'), findsOneWidget);
  });
}
