import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/features/sampler/data/datasources/local_sound_datasource.dart';

/// Vérifie la déduplication par identité forte Drive (`driveFileId`) lors de
/// l'indexation d'un dossier Drive — le correctif central contre les doublons.
void main() {
  late db.AppDatabase database;
  late LocalSoundDataSource dataSource;

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    dataSource = LocalSoundDataSource(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<int> insertLibrary() => database.into(database.libraries).insert(
        db.LibrariesCompanion.insert(name: 'Lib', localRootPath: '/cache'),
      );

  Future<List<db.Sound>> soundsOf(int libraryId) =>
      (database.select(database.sounds)
            ..where((s) => s.libraryId.equals(libraryId)))
          .get();

  test('un fichier renommé/déplacé sur Drive (même ID) ne crée pas de doublon',
      () async {
    final libraryId = await insertLibrary();

    final created1 = await dataSource.syncLibrarySoundFromDriveIndex(
      libraryId: libraryId,
      relativePath: 'Portes/knock.mp3',
      localPath: '/cache/Portes/knock.mp3',
      driveFileId: 'F1',
    );
    expect(created1, isTrue);

    // Déplacement + renommage côté Drive, même ID de fichier.
    final created2 = await dataSource.syncLibrarySoundFromDriveIndex(
      libraryId: libraryId,
      relativePath: 'SFX/knock-2.mp3',
      localPath: '/cache/SFX/knock-2.mp3',
      driveFileId: 'F1',
    );
    expect(created2, isFalse);

    final sounds = await soundsOf(libraryId);
    expect(sounds, hasLength(1));
    expect(sounds.first.relativePath, 'SFX/knock-2.mp3');
    expect(sounds.first.filePath, '/cache/SFX/knock-2.mp3');
    expect(sounds.first.driveFileId, 'F1');
  });

  test('un son legacy (sans driveFileId) adopte l\'identité forte au rescan',
      () async {
    final libraryId = await insertLibrary();

    // Son indexé avant l'introduction de l'identité forte.
    await database.into(database.sounds).insert(
          db.SoundsCompanion.insert(
            title: 'knock',
            filePath: '/cache/knock.mp3',
            libraryId: Value(libraryId),
            relativePath: const Value('knock.mp3'),
          ),
        );

    final created = await dataSource.syncLibrarySoundFromDriveIndex(
      libraryId: libraryId,
      relativePath: 'knock.mp3',
      localPath: '/cache/knock.mp3',
      driveFileId: 'F1',
    );
    expect(created, isFalse);

    final sounds = await soundsOf(libraryId);
    expect(sounds, hasLength(1));
    expect(sounds.first.driveFileId, 'F1');
  });

  test('deux fichiers Drive distincts donnent deux sons', () async {
    final libraryId = await insertLibrary();

    await dataSource.syncLibrarySoundFromDriveIndex(
      libraryId: libraryId,
      relativePath: 'a.mp3',
      localPath: '/cache/a.mp3',
      driveFileId: 'F1',
    );
    await dataSource.syncLibrarySoundFromDriveIndex(
      libraryId: libraryId,
      relativePath: 'b.mp3',
      localPath: '/cache/b.mp3',
      driveFileId: 'F2',
    );

    expect(await soundsOf(libraryId), hasLength(2));
  });
}
