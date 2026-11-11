import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stage_cue/core/theme/app_theme.dart';
import 'package:stage_cue/core/update/app_update_info.dart';
import 'package:stage_cue/core/update/app_update_installer.dart';
import 'package:stage_cue/core/update/update_flow.dart';
import 'package:stage_cue/core/utils/app_toast_host.dart';

class _MockInstaller extends Mock implements AppUpdateInstaller {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const AppUpdateInfo(
        version: '0.0.0',
        downloadUrl: 'https://example.com/x.exe',
        assetName: 'x.exe',
        sha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
      ),
    );
  });

  const info = AppUpdateInfo(
    version: '0.2.0',
    downloadUrl: 'https://example.com/StageCue-Setup.exe',
    assetName: 'StageCue-Setup.exe',
    sha256: '0000000000000000000000000000000000000000000000000000000000000000',
  );

  testWidgets('Plus tard annule sans télécharger', (tester) async {
    final installer = _MockInstaller();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) => AppToastHost(child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  runUpdateFlow(context, info, installer: installer),
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

  Widget host(AppUpdateInstaller installer, Future<void> Function() quitApp) =>
      MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) => AppToastHost(child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => runUpdateFlow(
                context,
                info,
                installer: installer,
                quitApp: quitApp,
              ),
              child: const Text('check'),
            ),
          ),
        ),
      );

  const installerPath = r'C:\Temp\StageCue-Setup.exe';

  testWidgets(
    'Installer télécharge, lance, affiche l\'installation dans le dialogue puis quitte',
    (tester) async {
      final installer = _MockInstaller();
      var quit = 0;
      when(
        () => installer.downloadInstaller(
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => installerPath);
      when(
        () => installer.launchInstallerSilently(any()),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(host(installer, () async => quit++));
      await tester.tap(find.text('check'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Installer'));
      await tester.pump();
      await tester.pump();

      verify(
        () => installer.downloadInstaller(
          info,
          onProgress: any(named: 'onProgress'),
        ),
      ).called(1);
      verify(() => installer.launchInstallerSilently(installerPath)).called(1);
      // L'état d'installation vit dans le dialogue, pas dans un toast.
      expect(find.text('Installation en cours'), findsOneWidget);
      expect(quit, 0);

      await tester.pump(const Duration(seconds: 2));
      expect(quit, 1);
    },
  );

  testWidgets(
    'échec du téléchargement → erreur dans le dialogue, sans quitter',
    (tester) async {
      final installer = _MockInstaller();
      var quit = 0;
      when(
        () => installer.downloadInstaller(
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenThrow(Exception('réseau coupé'));

      await tester.pumpWidget(host(installer, () async => quit++));
      await tester.tap(find.text('check'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Installer'));
      await tester.pumpAndSettle();

      expect(find.text('Échec du téléchargement'), findsOneWidget);
      expect(find.textContaining('réseau coupé'), findsOneWidget);
      verifyNever(() => installer.launchInstallerSilently(any()));

      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(find.text('Échec du téléchargement'), findsNothing);
      expect(quit, 0);
    },
  );

  testWidgets('échec du lancement → erreur dans le dialogue, sans quitter', (
    tester,
  ) async {
    final installer = _MockInstaller();
    var quit = 0;
    when(
      () => installer.downloadInstaller(
        any(),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((_) async => installerPath);
    when(
      () => installer.launchInstallerSilently(any()),
    ).thenThrow(Exception('accès refusé'));

    await tester.pumpWidget(host(installer, () async => quit++));
    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Installer'));
    await tester.pumpAndSettle();

    expect(find.text('Échec de l\'installation'), findsOneWidget);
    expect(find.textContaining('accès refusé'), findsOneWidget);
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    expect(quit, 0);
  });
}
