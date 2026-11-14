import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/core/sync/auto_sync_coordinator.dart'
    show LibraryPassOutcome, SyncPassStage;
import 'package:stage_cue/core/theme/app_icons.dart';
import 'package:stage_cue/core/utils/indexed_folder_labels.dart';
import 'package:stage_cue/features/sampler/data/models/indexing_progress.dart';
import 'package:stage_cue/features/sampler/data/repositories/library_repository.dart';
import 'package:stage_cue/features/sampler/domain/entities/library.dart'
    as domain;
import 'package:stage_cue/features/sampler/presentation/widgets/settings_indexed_folders_section.dart';

import '../../../../support/find_stroke_icon.dart';

class _MockLibraryRepository extends Mock implements LibraryRepository {}

domain.Library _library({
  int id = 1,
  String name = 'Spectacle',
  DateTime? lastSyncedAt,
  bool autoDownload = false,
}) => domain.Library(
  id: id,
  name: name,
  localRootPath: '/tmp/lib$id',
  driveFolderId: 'drive$id',
  drivePath: 'Mon Drive/Spectacle',
  lastSyncedAt: lastSyncedAt,
  createdAt: DateTime(2026, 1, 1),
  autoDownload: autoDownload,
);

IndexedFolderItem _localItem({int id = 1, String path = '/musique/jdr'}) =>
    IndexedFolderItem.local(
      db.WatchedPath(
        id: id,
        path: path,
        isDirectory: true,
        addedAt: DateTime(2026, 1, 1),
      ),
    );

IndexingProgress _idle(IndexedFolderItem item, {int total = 10}) =>
    IndexingProgress(path: 'p', current: total, total: total, isComplete: true);

/// Rappels reçus : un compteur par callback de la section.
class _Calls {
  int refresh = 0;
  int addFolder = 0;
  int databaseState = 0;
  final refreshLibrary = <int>[];
  final resolveConflict = <int>[];
  final removeLocal = <int>[];
  final removeDrive = <int>[];
  final downloadAll = <int>[];
  final toggleAuto = <int>[];
}

Future<_Calls> _pump(
  WidgetTester tester, {
  required List<IndexedFolderItem> items,
  required LibraryRepository repository,
  IndexingProgress Function(IndexedFolderItem item)? progressForItem,
  Map<int, ({int available, int total})> offlineCounts = const {},
  int soundCount = 12,
  String dbSizeLabel = '4,2 Mo',
  bool networkAllowed = true,
  bool autoSyncPaused = false,
  Set<int> refreshingLibraryIds = const {},
  Map<int, LibraryPassOutcome> passOutcomes = const {},
  Map<int, SyncPassStage> passStages = const {},
  int? conflictLibraryId,
}) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final calls = _Calls();
  await tester.pumpWidget(
    MaterialApp(
      // La police de test (Ahem) a des glyphes carrés bien plus larges que
      // Manrope : sans ça, les libellés du menu ⋮ débordent de sa largeur.
      theme: ThemeData(
        popupMenuTheme: const PopupMenuThemeData(
          textStyle: TextStyle(fontSize: 7),
          labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 7)),
        ),
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SettingsIndexedFoldersSection(
            items: items,
            labelsForItem: (item) => item.isLocal
                ? IndexedFolderLabels.forWatchedPath(
                    path: item.watchedPath!.path,
                  )
                : IndexedFolderLabels.forLibrary(
                    name: item.library!.name,
                    drivePath: item.library!.drivePath,
                  ),
            progressForItem: progressForItem ?? _idle,
            offlineCounts: offlineCounts,
            libraryRepository: repository,
            soundCount: soundCount,
            dbSizeLabel: dbSizeLabel,
            networkAllowed: networkAllowed,
            autoSyncPaused: autoSyncPaused,
            refreshingLibraryIds: refreshingLibraryIds,
            passOutcomes: passOutcomes,
            passStages: passStages,
            conflictLibraryId: conflictLibraryId,
            onRefresh: () => calls.refresh++,
            onRefreshLibrary: (library) => calls.refreshLibrary.add(library.id),
            onResolveConflict: (library) =>
                calls.resolveConflict.add(library.id),
            onAddFolder: () => calls.addFolder++,
            onShowDatabaseState: () => calls.databaseState++,
            onRemoveLocal: (path) => calls.removeLocal.add(path.id),
            onRemoveDrive: (library) => calls.removeDrive.add(library.id),
            onDownloadAll: (library) => calls.downloadAll.add(library.id),
            onToggleAutoDownload: (library) => calls.toggleAuto.add(library.id),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return calls;
}

void main() {
  late _MockLibraryRepository repository;

  setUp(() {
    repository = _MockLibraryRepository();
    // Aucun téléchargement en cours par défaut.
    when(() => repository.libraryDownloadProgress(any())).thenReturn(null);
  });

  group('liste vide', () {
    testWidgets('invite à ajouter un dossier, sans bouton d\'actualisation', (
      tester,
    ) async {
      final calls = await _pump(tester, items: [], repository: repository);

      expect(find.text('Aucun dossier indexé'), findsOneWidget);
      expect(find.byTooltip('Actualiser depuis Drive'), findsNothing);

      await tester.tap(find.byTooltip('Ajouter un dossier'));
      expect(calls.addFolder, 1);
    });

    testWidgets('pied de base : pluriel et tap vers le détail', (tester) async {
      final calls = await _pump(
        tester,
        items: [],
        repository: repository,
        soundCount: 1,
      );
      expect(find.text('1 son · 4,2 Mo'), findsOneWidget);

      await tester.tap(find.text('1 son · 4,2 Mo'));
      expect(calls.databaseState, 1);

      await _pump(tester, items: [], repository: repository, soundCount: 12);
      expect(find.text('12 sons · 4,2 Mo'), findsOneWidget);
    });
  });

  group('actualisation', () {
    final drive = IndexedFolderItem.drive(_library());

    testWidgets('le bouton n\'existe que s\'il y a une bibliothèque Drive', (
      tester,
    ) async {
      await _pump(tester, items: [_localItem()], repository: repository);
      expect(find.byTooltip('Actualiser depuis Drive'), findsNothing);

      final calls = await _pump(
        tester,
        items: [_localItem(), drive],
        repository: repository,
      );
      await tester.tap(find.byTooltip('Actualiser depuis Drive'));
      expect(calls.refresh, 1);
    });

    testWidgets('hors ligne : grisé, avec la raison en infobulle et en ligne', (
      tester,
    ) async {
      final calls = await _pump(
        tester,
        items: [drive],
        repository: repository,
        networkAllowed: false,
      );

      expect(
        find.byTooltip(
          'Mode hors ligne — passez en mode Connecté pour actualiser',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Mode hors ligne · synchronisation désactivée'),
        findsOneWidget,
      );

      await tester.tap(
        find.byTooltip(
          'Mode hors ligne — passez en mode Connecté pour actualiser',
        ),
        warnIfMissed: false,
      );
      expect(calls.refresh, 0);
    });

    testWidgets('Mode Spectacle : la synchro automatique est dite suspendue, '
        'l\'actualisation manuelle reste possible', (tester) async {
      final calls = await _pump(
        tester,
        items: [drive],
        repository: repository,
        autoSyncPaused: true,
      );

      expect(
        find.text('Mode Spectacle · synchronisation automatique suspendue'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Actualiser depuis Drive'));
      expect(calls.refresh, 1);
    });

    testWidgets('aucune ligne de suspension sans bibliothèque Drive', (
      tester,
    ) async {
      await _pump(
        tester,
        items: [_localItem()],
        repository: repository,
        networkAllowed: false,
        autoSyncPaused: true,
      );

      expect(find.textContaining('synchronisation'), findsNothing);
    });

    testWidgets('pendant une passe : pas de seconde actualisation', (
      tester,
    ) async {
      final calls = await _pump(
        tester,
        items: [drive],
        repository: repository,
        refreshingLibraryIds: {1},
      );

      await tester.tap(
        find.byTooltip('Actualiser depuis Drive'),
        warnIfMissed: false,
      );
      expect(calls.refresh, 0);
    });

    testWidgets('l\'étape de la passe se lit sur la ligne de la bibliothèque', (
      tester,
    ) async {
      for (final (stage, label) in [
        (null, 'Synchronisation…'),
        (SyncPassStage.detecting, 'Recherche des changements…'),
        (SyncPassStage.scanning, 'Analyse complète de Drive…'),
        (SyncPassStage.pulling, 'Récupération des scènes…'),
      ]) {
        await _pump(
          tester,
          items: [drive],
          repository: repository,
          refreshingLibraryIds: {1},
          passStages: {1: ?stage},
        );
        expect(find.text(label), findsOneWidget, reason: '$stage');
      }
    });
  });

  group('état d\'une ligne', () {
    testWidgets('titres et sous-titres des dossiers local et Drive', (
      tester,
    ) async {
      await _pump(
        tester,
        items: [_localItem(), IndexedFolderItem.drive(_library())],
        repository: repository,
      );

      expect(find.text('jdr'), findsOneWidget);
      expect(find.text('/musique/jdr'), findsOneWidget);
      expect(find.text('Spectacle'), findsOneWidget);
      expect(find.text('Mon Drive/Spectacle'), findsOneWidget);
      expect(find.text('10 fichiers'), findsNWidgets(2));
    });

    testWidgets('jamais synchronisée, puis synchronisée il y a quelques min', (
      tester,
    ) async {
      await _pump(
        tester,
        items: [IndexedFolderItem.drive(_library())],
        repository: repository,
      );
      expect(find.text('Pas encore synchronisé'), findsOneWidget);

      await _pump(
        tester,
        items: [
          IndexedFolderItem.drive(
            _library(
              lastSyncedAt: DateTime.now().subtract(const Duration(minutes: 5)),
            ),
          ),
        ],
        repository: repository,
      );
      expect(find.text('Synchronisé il y a 5 min'), findsOneWidget);
      expect(find.text('Pas encore synchronisé'), findsNothing);
    });

    testWidgets('un clic sur la date relance cette bibliothèque seule', (
      tester,
    ) async {
      final calls = await _pump(
        tester,
        items: [
          IndexedFolderItem.drive(
            _library(id: 7, lastSyncedAt: DateTime.now()),
          ),
        ],
        repository: repository,
      );

      await tester.tap(find.text('Synchronisé à l\'instant'));
      expect(calls.refreshLibrary, [7]);
    });

    testWidgets('« Tout télécharger » depuis le décompte hors ligne', (
      tester,
    ) async {
      final calls = await _pump(
        tester,
        items: [IndexedFolderItem.drive(_library(id: 3))],
        repository: repository,
        offlineCounts: {3: (available: 2, total: 5)},
      );

      expect(find.text('2/5 téléchargés'), findsOneWidget);
      await tester.tap(find.text('2/5 téléchargés'));
      expect(calls.downloadAll, [3]);
    });

    testWidgets('tout téléchargé : le décompte n\'est plus cliquable', (
      tester,
    ) async {
      final calls = await _pump(
        tester,
        items: [IndexedFolderItem.drive(_library(id: 3))],
        repository: repository,
        offlineCounts: {3: (available: 5, total: 5)},
      );

      expect(find.text('5/5 téléchargés'), findsOneWidget);
      expect(findStrokeIcon(AppIcons.downloadDone), findsOneWidget);
      await tester.tap(find.text('5/5 téléchargés'));
      expect(calls.downloadAll, isEmpty);
    });
  });

  group('activité (une seule barre à la fois)', () {
    final drive = IndexedFolderItem.drive(_library(id: 1));

    testWidgets('indexation en cours : progression chiffrée', (tester) async {
      await _pump(
        tester,
        items: [drive],
        repository: repository,
        progressForItem: (_) =>
            IndexingProgress(path: 'p', current: 3, total: 10),
      );

      expect(find.text('Indexation 3/10'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('total inconnu : barre indéterminée et « … »', (tester) async {
      await _pump(
        tester,
        items: [drive],
        repository: repository,
        progressForItem: (_) =>
            IndexingProgress(path: 'p', current: 3, total: 0),
      );

      expect(find.text('Indexation 3/…'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );
    });

    testWidgets('erreur d\'indexation : libellé seul, sans barre', (
      tester,
    ) async {
      await _pump(
        tester,
        items: [drive],
        repository: repository,
        progressForItem: (_) => IndexingProgress(
          path: 'p',
          current: 1,
          total: 10,
          isComplete: true,
          error: 'quota',
        ),
      );

      expect(find.text('Erreur : quota'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('l\'indexation prime sur le téléchargement', (tester) async {
      when(
        () => repository.libraryDownloadProgress(1),
      ).thenReturn(IndexingProgress(path: 'p', current: 2, total: 5));
      await _pump(
        tester,
        items: [drive],
        repository: repository,
        progressForItem: (_) =>
            IndexingProgress(path: 'p', current: 3, total: 10),
      );

      expect(find.text('Indexation 3/10'), findsOneWidget);
      expect(find.textContaining('Téléchargement'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('téléchargement en cours : annulable', (tester) async {
      when(
        () => repository.libraryDownloadProgress(1),
      ).thenReturn(IndexingProgress(path: 'p', current: 2, total: 5));
      await _pump(tester, items: [drive], repository: repository);

      expect(find.text('Téléchargement 2/5'), findsOneWidget);
      await tester.tap(findStrokeIcon(AppIcons.close));
      verify(() => repository.cancelLibraryDownload(1)).called(1);
    });

    testWidgets('erreur de téléchargement : libellé d\'erreur', (tester) async {
      when(() => repository.libraryDownloadProgress(1)).thenReturn(
        IndexingProgress(
          path: 'p',
          current: 2,
          total: 5,
          isComplete: true,
          error: 'disque plein',
        ),
      );
      await _pump(tester, items: [drive], repository: repository);

      expect(find.text('Erreur : disque plein'), findsOneWidget);
    });
  });

  group('conflit et bilan de passe', () {
    final drive = IndexedFolderItem.drive(_library(id: 4));

    testWidgets('conflit : seul état cliquable, prime sur le bilan', (
      tester,
    ) async {
      final calls = await _pump(
        tester,
        items: [drive],
        repository: repository,
        conflictLibraryId: 4,
        passOutcomes: {4: const LibraryPassOutcome(added: 2)},
      );

      expect(
        find.text('Conflit de synchronisation · Résoudre'),
        findsOneWidget,
      );
      expect(find.textContaining('ajoutés'), findsNothing);
      await tester.tap(find.text('Conflit de synchronisation · Résoudre'));
      expect(calls.resolveConflict, [4]);
    });

    testWidgets('le conflit d\'une autre bibliothèque ne s\'affiche pas ici', (
      tester,
    ) async {
      await _pump(
        tester,
        items: [drive],
        repository: repository,
        conflictLibraryId: 99,
      );

      expect(find.textContaining('Conflit'), findsNothing);
    });

    testWidgets('échec : « Réessayer » relance cette bibliothèque', (
      tester,
    ) async {
      final calls = await _pump(
        tester,
        items: [drive],
        repository: repository,
        passOutcomes: {4: const LibraryPassOutcome(error: 'réseau')},
      );

      await tester.tap(find.text('Non actualisé · Réessayer'));
      expect(calls.refreshLibrary, [4]);
    });

    testWidgets('échec hors ligne : « Réessayer » ne fait rien', (
      tester,
    ) async {
      final calls = await _pump(
        tester,
        items: [drive],
        repository: repository,
        networkAllowed: false,
        passOutcomes: {4: const LibraryPassOutcome(error: 'réseau')},
      );

      await tester.tap(find.text('Non actualisé · Réessayer'));
      expect(calls.refreshLibrary, isEmpty);
    });

    testWidgets('session expirée : se règle ailleurs, pas de relance', (
      tester,
    ) async {
      final calls = await _pump(
        tester,
        items: [drive],
        repository: repository,
        passOutcomes: {
          4: const LibraryPassOutcome(error: 'auth', authExpired: true),
        },
      );

      expect(
        find.text('Session Google expirée · Renouveler ci-dessus'),
        findsOneWidget,
      );
      await tester.tap(
        find.text('Session Google expirée · Renouveler ci-dessus'),
      );
      expect(calls.refreshLibrary, isEmpty);
    });

    testWidgets('changements : singulier, pluriel et séparateur', (
      tester,
    ) async {
      for (final (outcome, label) in [
        (const LibraryPassOutcome(added: 1), '1 ajouté ou modifié'),
        (const LibraryPassOutcome(removed: 1), '1 retiré'),
        (
          const LibraryPassOutcome(added: 3, removed: 2),
          '3 ajoutés ou modifiés · 2 retirés',
        ),
      ]) {
        await _pump(
          tester,
          items: [drive],
          repository: repository,
          passOutcomes: {4: outcome},
        );
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('passe sans changement : retombe sur la ligne de synchro', (
      tester,
    ) async {
      await _pump(
        tester,
        items: [drive],
        repository: repository,
        passOutcomes: {4: const LibraryPassOutcome()},
      );

      expect(find.text('Pas encore synchronisé'), findsOneWidget);
    });
  });

  group('menu ⋮', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Options'));
      await tester.pumpAndSettle();
    }

    testWidgets('dossier local : une seule entrée, « Retirer »', (
      tester,
    ) async {
      final calls = await _pump(
        tester,
        items: [_localItem(id: 9)],
        repository: repository,
      );

      await openMenu(tester);
      expect(find.text('Tout télécharger'), findsNothing);
      expect(find.text('Téléchargement auto'), findsNothing);

      await tester.tap(find.text('Retirer'));
      await tester.pumpAndSettle();
      expect(calls.removeLocal, [9]);
    });

    testWidgets('bibliothèque Drive : tout télécharger, auto, retirer', (
      tester,
    ) async {
      final calls = await _pump(
        tester,
        items: [IndexedFolderItem.drive(_library(id: 5))],
        repository: repository,
        offlineCounts: {5: (available: 1, total: 4)},
      );

      await openMenu(tester);
      await tester.tap(find.text('Tout télécharger').last);
      await tester.pumpAndSettle();
      expect(calls.downloadAll, [5]);

      await openMenu(tester);
      await tester.tap(find.text('Téléchargement auto'));
      await tester.pumpAndSettle();
      expect(calls.toggleAuto, [5]);

      await openMenu(tester);
      await tester.tap(find.text('Retirer'));
      await tester.pumpAndSettle();
      expect(calls.removeDrive, [5]);
    });

    testWidgets(
      'tout est hors ligne : l\'entrée « Tout télécharger » disparaît',
      (tester) async {
        await _pump(
          tester,
          items: [IndexedFolderItem.drive(_library(id: 5))],
          repository: repository,
          offlineCounts: {5: (available: 4, total: 4)},
        );

        await openMenu(tester);
        expect(find.text('Tout télécharger'), findsNothing);
        expect(find.text('Téléchargement auto'), findsOneWidget);
      },
    );

    testWidgets('téléchargement en cours : entrée grisée', (tester) async {
      when(
        () => repository.libraryDownloadProgress(5),
      ).thenReturn(IndexingProgress(path: 'p', current: 1, total: 4));
      final calls = await _pump(
        tester,
        items: [IndexedFolderItem.drive(_library(id: 5))],
        repository: repository,
        offlineCounts: {5: (available: 1, total: 4)},
      );

      await openMenu(tester);
      expect(find.text('Téléchargement en cours…'), findsOneWidget);
      await tester.tap(find.text('Téléchargement en cours…'));
      await tester.pumpAndSettle();
      expect(calls.downloadAll, isEmpty);
    });

    testWidgets('l\'état de « Téléchargement auto » se lit sur sa case', (
      tester,
    ) async {
      for (final (auto, icon) in [
        (true, AppIcons.checkboxOn),
        (false, AppIcons.checkboxOff),
      ]) {
        await _pump(
          tester,
          items: [IndexedFolderItem.drive(_library(id: 5, autoDownload: auto))],
          repository: repository,
        );
        await openMenu(tester);
        expect(findStrokeIcon(icon), findsOneWidget, reason: 'auto=$auto');
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();
      }
    });
  });
}
