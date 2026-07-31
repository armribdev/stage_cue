import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/core/database/sounds.dart' show SoundType;
import 'package:stage_cue/core/sync/drive_client.dart';
import 'package:stage_cue/core/sync/drive_models.dart';
import 'package:stage_cue/features/sampler/data/repositories/library_repository.dart';
import 'package:stage_cue/features/sampler/domain/entities/library.dart';

class MockDriveClient extends Mock implements DriveClient {}

/// Vérifie que l'épinglage anti-éviction est réellement **branché** par
/// `LibraryRepository.fromDatabase`.
///
/// `audio_cache_manager_test.dart` couvre déjà le comportement de l'éviction,
/// mais toujours avec un callback `pinnedPaths` que le test fournit lui-même.
/// Ce fichier couvre l'angle mort que la [décision 0010] désigne comme « le mode
/// de régression le plus probable » : que le callback ne soit pas fourni du tout
/// à la construction — auquel cas l'éviction redevient purement LRU **sans
/// aucun avertissement**, et un son disparaît du cache en pleine représentation.
///
/// On monte donc la vraie chaîne (base Drift → repository → cache) et on
/// provoque une éviction sur un disque simulé.
void main() {
  const capacity = 1000000;
  const fileSize = 80;
  // Marge telle que le 3e fichier écrit déclenche l'éviction.
  const budget = 100;

  late MockDriveClient client;
  late db.AppDatabase database;
  late Directory rootDir;
  late Library library;

  setUpAll(() {
    registerFallbackValue(const Stream<List<int>>.empty());
  });

  setUp(() {
    client = MockDriveClient();
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    rootDir = Directory.systemTemp.createTempSync('pin_wiring_');
    library = Library(
      id: 1,
      name: 'Lib',
      localRootPath: rootDir.path,
      driveFolderId: 'folder-root',
      createdAt: DateTime.now(),
    );
  });

  tearDown(() async {
    await database.close();
    if (rootDir.existsSync()) rootDir.deleteSync(recursive: true);
  });

  /// Espace libre simulé : capacité moins les octets audio réellement écrits.
  Future<int?> simulatedDisk(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return capacity;
    var used = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && p.basename(entity.path) != '.cache_access.json') {
        used += await entity.length();
      }
    }
    return capacity - used;
  }

  void stubDownload() {
    when(() => client.findInFolder(
          parentId: any(named: 'parentId'),
          name: any(named: 'name'),
        )).thenAnswer((_) async => const DriveFile(id: 'remote', name: 'x'));
    when(() => client.downloadToFile(
          fileId: any(named: 'fileId'),
          destinationPath: any(named: 'destinationPath'),
        )).thenAnswer((invocation) async {
      final dest = invocation.namedArguments[#destinationPath] as String;
      final file = File(dest);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(List.filled(fileSize, 1));
    });
  }

  /// Repository réel, avec un disque simulé pour rendre l'éviction atteignable.
  LibraryRepository buildRepository() {
    var tick = 0;
    return LibraryRepository.fromDatabase(
      database,
      minFreeDiskBytes: capacity - budget,
      availableDiskBytes: simulatedDisk,
      clock: () => ++tick,
    );
  }

  Future<int> insertLibraryRow() =>
      database.into(database.libraries).insert(
            db.LibrariesCompanion.insert(
              name: 'Lib',
              localRootPath: rootDir.path,
            ),
          );

  Future<int> insertSound(
    int libraryId,
    String relativePath, {
    bool isFavorite = false,
  }) {
    return database.into(database.sounds).insert(
          db.SoundsCompanion.insert(
            title: relativePath,
            filePath: p.join(rootDir.path, relativePath),
            type: const Value(SoundType.soundEffect),
            libraryId: Value(libraryId),
            relativePath: Value(relativePath),
            isFavorite: Value(isFavorite),
          ),
        );
  }

  /// Plateau contenant [soundId], via un pad — c'est la jointure que lit
  /// `getBoardRelativePaths`.
  Future<int> insertBoardWithSound(int soundId) async {
    final boardId = await database.into(database.soundBoards).insert(
          db.SoundBoardsCompanion.insert(name: 'Scène 1'),
        );
    final padId = await database.into(database.pads).insert(
          db.PadsCompanion.insert(boardId: boardId),
        );
    await database.into(database.padSounds).insert(
          db.PadSoundsCompanion.insert(padId: padId, soundId: soundId),
        );
    return boardId;
  }

  Future<void> cache(LibraryRepository repository, String relativePath) async {
    await repository.cacheManager.ensureCached(
      client: client,
      library: library,
      relativePath: relativePath,
    );
  }

  bool existsInCache(String relativePath) =>
      File(p.join(rootDir.path, relativePath)).existsSync();

  test(
    'un son du PLATEAU ACTIF survit à l éviction, même le moins récent',
    () async {
      stubDownload();
      final repository = buildRepository();
      final libraryId = await insertLibraryRow();
      final onBoardSoundId = await insertSound(libraryId, 'plateau.wav');
      final boardId = await insertBoardWithSound(onBoardSoundId);
      await insertSound(libraryId, 'banal.wav');
      await insertSound(libraryId, 'recent.wav');

      // C'est ce que fait `SamplerNotifier` à chaque changement de scène.
      repository.activeBoardId = boardId;

      // `plateau.wav` est mis en cache en premier : c'est donc le plus ancien,
      // celui qu'un LRU sans épinglage sacrifierait d'abord — exactement le
      // scénario du téléchargement de masse décrit par la décision 0010.
      await cache(repository, 'plateau.wav');
      await cache(repository, 'banal.wav');
      await cache(repository, 'recent.wav');

      expect(
        existsInCache('plateau.wav'),
        isTrue,
        reason: 'son du plateau actif : épinglé, jamais évincé',
      );
      expect(
        existsInCache('banal.wav'),
        isFalse,
        reason: 'ni favori ni sur le plateau : c est lui qui doit partir',
      );
      expect(existsInCache('recent.wav'), isTrue);
    },
  );

  test('un FAVORI survit à l éviction, même le moins récent', () async {
    stubDownload();
    final repository = buildRepository();
    final libraryId = await insertLibraryRow();
    await insertSound(libraryId, 'favori.wav', isFavorite: true);
    await insertSound(libraryId, 'banal.wav');
    await insertSound(libraryId, 'recent.wav');

    await cache(repository, 'favori.wav');
    await cache(repository, 'banal.wav');
    await cache(repository, 'recent.wav');

    expect(existsInCache('favori.wav'), isTrue);
    expect(existsInCache('banal.wav'), isFalse);
    expect(existsInCache('recent.wav'), isTrue);
  });

  test(
    'sans plateau actif, seuls les favoris sont épinglés',
    () async {
      stubDownload();
      final repository = buildRepository();
      final libraryId = await insertLibraryRow();
      final onBoardSoundId = await insertSound(libraryId, 'plateau.wav');
      await insertBoardWithSound(onBoardSoundId);
      await insertSound(libraryId, 'banal.wav');
      await insertSound(libraryId, 'recent.wav');

      // activeBoardId laissé à null : aucune scène ouverte.
      await cache(repository, 'plateau.wav');
      await cache(repository, 'banal.wav');
      await cache(repository, 'recent.wav');

      expect(
        existsInCache('plateau.wav'),
        isFalse,
        reason: 'aucune scène active : rien ne protège ce son du LRU',
      );
    },
  );
}
