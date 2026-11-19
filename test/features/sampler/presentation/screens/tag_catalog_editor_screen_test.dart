import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/features/sampler/data/datasources/local_tag_editing_datasource.dart';
import 'package:stage_cue/features/sampler/presentation/screens/tag_catalog_editor_screen.dart';

/// Parcours de l'éditeur de catalogue de développement (décision 0047) : liste,
/// fiche d'un tag, alias ajouté, puis déclaration à copier.
void main() {
  late db.AppDatabase database;

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  /// Drift tourne sur de vraies E/S : le temps simulé du testeur ne suffit pas.
  /// Attend (au plus 5 s) que [finder] apparaisse.
  Future<void> settle(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  testWidgets('ajouter un alias à un tag', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: TagCatalogEditorScreen(
          editor: LocalTagEditingDataSource(database),
        ),
      ),
    );
    await settle(tester, find.text('ACTION'));

    // La liste est paresseuse : le filtre ramène le tag visé en vue.
    await tester.enterText(find.byType(TextField).first, 'urbain');
    await tester.pump();
    expect(find.text('AMBIANCE'), findsOneWidget);
    expect(find.text('Urbain'), findsOneWidget);
    // Rien à copier tant que rien n'a changé.
    expect(find.text('Copier le code'), findsOneWidget);

    await tester.tap(find.text('Urbain'));
    await tester.pumpAndSettle();
    expect(find.text('Ajouter un alias'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'embouteillage');
    await tester.tap(find.text('Ajouter'));
    await settle(tester, find.text('embouteillage'));
    await tester.pumpAndSettle();

    // L'alias apparaît dans la fiche, qui reste ouverte.
    expect(find.text('embouteillage'), findsOneWidget);
    // …et la modification est à copier dans le catalogue du code.
    expect(find.text('Copier le code (1)'), findsOneWidget);
  });
}
