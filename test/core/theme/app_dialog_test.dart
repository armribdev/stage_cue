import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/theme/app_dialog.dart';

void main() {
  Widget host(void Function(BuildContext) onOpen) => MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => onOpen(context),
          child: const Text('ouvrir'),
        ),
      ),
    ),
  );

  testWidgets('showAppDialog affiche le dialogue et rend sa valeur', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      host((context) async {
        result = await showAppDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Titre'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop('ok'),
                child: const Text('Valider'),
              ),
            ],
          ),
        );
      }),
    );

    await tester.tap(find.text('ouvrir'));
    await tester.pump();
    // Entrée en cours : le dialogue est monté mais pas encore opaque.
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('Titre'), findsOneWidget);
    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.text('Titre'),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, inInclusiveRange(0.01, 0.99));

    await tester.pumpAndSettle();
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();

    expect(find.text('Titre'), findsNothing);
    expect(result, 'ok');
  });

  testWidgets(
    'barrierDismissible: false empêche la fermeture par la barrière',
    (tester) async {
      await tester.pumpWidget(
        host(
          (context) => showAppDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => const AlertDialog(title: Text('Bloquant')),
          ),
        ),
      );

      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();

      expect(find.text('Bloquant'), findsOneWidget);
    },
  );

  testWidgets('animations réduites : le dialogue apparaît sans transition', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: host(
          (context) => showAppDialog<void>(
            context: context,
            builder: (_) => const AlertDialog(title: Text('Immédiat')),
          ),
        ),
      ),
    );

    await tester.tap(find.text('ouvrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('Immédiat'), findsOneWidget);
  });
}
