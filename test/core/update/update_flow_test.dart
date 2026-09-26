import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stage_cue/core/theme/app_theme.dart';
import 'package:stage_cue/core/update/app_update_info.dart';
import 'package:stage_cue/core/update/app_update_installer.dart';
import 'package:stage_cue/core/update/update_flow.dart';

class _MockInstaller extends Mock implements AppUpdateInstaller {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const AppUpdateInfo(
        version: '0.0.0',
        downloadUrl: 'https://example.com/x.exe',
        assetName: 'x.exe',
      ),
    );
  });

  const info = AppUpdateInfo(
    version: '0.2.0',
    downloadUrl: 'https://example.com/StageCue-Setup.exe',
    assetName: 'StageCue-Setup.exe',
  );

  testWidgets('Plus tard annule sans télécharger', (tester) async {
    final installer = _MockInstaller();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => runUpdateFlow(context, info, installer: installer),
              child: const Text('check'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();

    expect(find.text('Mise à jour disponible'), findsOneWidget);
    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();

    verifyNever(() => installer.downloadInstaller(any()));
    verifyNever(() => installer.launchInstallerSilently(any()));
  });

  testWidgets('Installer télécharge puis lance silencieusement', (tester) async {
    final installer = _MockInstaller();
    when(
      () => installer.downloadInstaller(
        any(),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((_) async => r'C:\Temp\StageCue-Setup.exe');
    when(() => installer.launchInstallerSilently(any()))
        .thenAnswer((_) async {});

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => runUpdateFlow(context, info, installer: installer),
              child: const Text('check'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Installer'));
    await tester.pumpAndSettle();

    verify(
      () => installer.downloadInstaller(
        info,
        onProgress: any(named: 'onProgress'),
      ),
    ).called(1);
    verify(
      () => installer.launchInstallerSilently(r'C:\Temp\StageCue-Setup.exe'),
    ).called(1);
    expect(find.textContaining('Installation en cours'), findsOneWidget);

    // SnackBar de confirmation (6 s) — consommer le timer avant la fin du test.
    await tester.pump(const Duration(seconds: 6));
  });
}
