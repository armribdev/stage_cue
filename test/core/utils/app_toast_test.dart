import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/theme/app_theme.dart';
import 'package:stage_cue/core/utils/app_snackbar.dart';
import 'package:stage_cue/core/utils/app_toast_host.dart';

/// Fenêtre de test : `MaterialApp` avec l'hôte de toasts, comme `app.dart`.
Widget _app({Widget? home, bool disableAnimations = false}) => MaterialApp(
  theme: AppTheme.darkTheme,
  builder: (context, child) {
    final host = AppToastHost(child: child!);
    return disableAnimations
        ? MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: host,
          )
        : host;
  },
  home: home ?? const Scaffold(body: SizedBox.expand()),
);

BuildContext _context(WidgetTester tester) =>
    tester.element(find.byType(Scaffold).first);

void _show(
  WidgetTester tester,
  String message, {
  AppToastAction? action,
  bool copyable = false,
  Duration duration = const Duration(seconds: 4),
}) {
  AppSnackBar.show(
    _context(tester),
    message,
    action: action,
    copyable: copyable,
    duration: duration,
  );
}

void main() {
  // Le contrôleur est global : on referme tout toast resté en suspens pour que
  // son `Timer` ne fuie pas d'un test à l'autre.
  tearDown(() => AppSnackBar.controller.dismissCurrent());

  testWidgets('un toast en remplace un autre au lieu de s\'empiler', (
    tester,
  ) async {
    await tester.pumpWidget(_app());

    _show(tester, 'Premier');
    await tester.pump();
    _show(tester, 'Second');
    await tester.pump();

    expect(find.text('Premier'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    AppSnackBar.controller.dismissCurrent();
    await tester.pumpAndSettle();
  });

  testWidgets('se ferme après la durée, sans animation avancée', (
    tester,
  ) async {
    await tester.pumpWidget(_app());

    _show(tester, 'Éphémère', duration: const Duration(seconds: 2));
    await tester.pump();
    expect(AppSnackBar.controller.current, isNotNull);

    // Aucun `pump` de frame : seul le temps Dart avance. La fermeture doit
    // venir du `Timer` du contrôleur, pas d'un ticker d'animation.
    await tester.binding.delayed(const Duration(seconds: 2));
    expect(AppSnackBar.controller.current, isNull);

    await tester.pumpAndSettle();
    expect(find.text('Éphémère'), findsNothing);
  });

  testWidgets('la fermeture d\'un ancien toast ne ferme pas le nouveau', (
    tester,
  ) async {
    await tester.pumpWidget(_app());

    final first = AppSnackBar.controller.show(
      'Ancien',
      duration: const Duration(seconds: 3),
    );
    await tester.pump();
    AppSnackBar.controller.show(
      'Récent',
      duration: const Duration(seconds: 10),
    );
    await tester.pump();

    // Échéance de l'ancien dépassée, et fermeture explicite par son id.
    await tester.pump(const Duration(seconds: 4));
    AppSnackBar.controller.dismiss(first.id);
    await tester.pump();

    expect(find.text('Récent'), findsOneWidget);
    AppSnackBar.controller.dismissCurrent();
    await tester.pumpAndSettle();
  });

  testWidgets('copyable : copie le message puis affiche « Message copié »', (
    tester,
  ) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(_app());

    _show(tester, 'Erreur détaillée', copyable: true);
    await tester.pump();
    await tester.tap(find.text('Erreur détaillée'));
    await tester.pump();
    await tester.pump();

    expect(clipboard, 'Erreur détaillée');
    expect(find.text('Message copié'), findsOneWidget);
    expect(find.text('Erreur détaillée'), findsNothing);
    AppSnackBar.controller.dismissCurrent();
    await tester.pumpAndSettle();
  });

  testWidgets('l\'action se déclenche et ferme le toast', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(_app());

    _show(
      tester,
      'Session expirée',
      action: AppToastAction(label: 'Reconnecter', onPressed: () => pressed++),
    );
    await tester.pump();
    await tester.tap(find.text('Reconnecter'));
    await tester.pumpAndSettle();

    expect(pressed, 1);
    expect(find.text('Session expirée'), findsNothing);
  });

  testWidgets('visible et cliquable au-dessus d\'une route modale', (
    tester,
  ) async {
    var pressed = 0;
    await tester.pumpWidget(
      _app(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(content: Text('Modale')),
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text('Modale'), findsOneWidget);

    _show(
      tester,
      'Au-dessus',
      action: AppToastAction(label: 'Ok', onPressed: () => pressed++),
    );
    await tester.pump();
    await tester.tap(find.text('Ok'));
    await tester.pumpAndSettle();

    // L'action a reçu le tap (et non la barrière) : la modale reste ouverte.
    expect(pressed, 1);
    expect(find.text('Modale'), findsOneWidget);
  });

  testWidgets('ne capte pas les taps hors de la carte', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      _app(
        home: Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => pressed++,
              child: const Text('dessous'),
            ),
          ),
        ),
      ),
    );

    _show(tester, 'Toast');
    await tester.pump();
    await tester.tap(find.text('dessous'));

    expect(pressed, 1);
    AppSnackBar.controller.dismissCurrent();
    await tester.pumpAndSettle();
  });

  testWidgets('disableAnimations : entrée et sortie instantanées', (
    tester,
  ) async {
    await tester.pumpWidget(_app(disableAnimations: true));

    _show(tester, 'Immédiat');
    await tester.pump();
    final opacity = tester.widget<FadeTransition>(
      find.ancestor(
        of: find.text('Immédiat'),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(opacity.opacity.value, 1.0);

    AppSnackBar.controller.dismissCurrent();
    await tester.pump();
    expect(find.text('Immédiat'), findsNothing);
  });

  testWidgets('le survol suspend le compte à rebours', (tester) async {
    await tester.pumpWidget(_app());

    _show(tester, 'Survolé', duration: const Duration(seconds: 2));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Survolé')));
    await tester.pump();

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Survolé'), findsOneWidget);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Survolé'), findsNothing);
  });
}
