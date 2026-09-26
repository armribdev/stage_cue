import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/app/audio_engine_unavailable_screen.dart';
import 'package:stage_cue/core/theme/app_theme.dart';

void main() {
  testWidgets('affiche le message et déclenche le retry', (tester) async {
    var retries = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: AudioEngineUnavailableScreen(
          error: StateError('aucun périphérique de sortie'),
          onRetry: () => retries++,
        ),
      ),
    );

    expect(find.text('Moteur audio indisponible'), findsOneWidget);
    expect(find.textContaining('aucun périphérique de sortie'), findsOneWidget);

    await tester.tap(find.text('Réessayer'));
    await tester.pump();

    expect(retries, 1);
  });

  testWidgets('désactive le bouton pendant un retry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: AudioEngineUnavailableScreen(
          error: 'dll manquante',
          isRetrying: true,
          onRetry: () {},
        ),
      ),
    );

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
