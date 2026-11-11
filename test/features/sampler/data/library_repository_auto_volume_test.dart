import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/core/database/sounds.dart' as db_sounds;
import 'package:stage_cue/core/sync/audio_cache_manager.dart';
import 'package:stage_cue/core/sync/drive_account_profile.dart';
import 'package:stage_cue/core/sync/drive_client.dart';
import 'package:stage_cue/core/sync/library_sync_service.dart';
import 'package:stage_cue/core/sync/snapshot_store.dart';
import 'package:stage_cue/features/sampler/data/datasources/local_library_datasource.dart';
import 'package:stage_cue/features/sampler/data/datasources/local_sound_datasource.dart';
import 'package:stage_cue/features/sampler/data/repositories/library_repository.dart';

import '../../../core/autotag/audio_stream_info_test.dart' show wavBytes;
import '../../../core/autotag/native_libs.dart';

class MockDriveClient extends Mock implements DriveClient {}

class _FakeAuthenticator implements DriveAuthenticator {
  final DriveClient? client;
  _FakeAuthenticator(this.client);

  @override
  Future<DriveClient?> connectSilently() async => client;

  @override
  Future<DriveClient?> connect() async => client;

  @override
  Future<void> restoreAccountProfile() async {}

  @override
  Future<void> refreshAccountProfile() async {}

  @override
  Future<void> signOut() async {}

  @override
  String? get accountEmail => 'test@example.com';

  @override
  DriveAccountProfile? get accountProfile => null;
}

/// Recalcul en masse du volume « auto » (décision 0036) : ne mesure que ce qui
/// est déjà sur l'appareil, écrit au fil de l'eau, s'arrête proprement.
void main() {
  final skip = soloudNativeSkipReason();
  late db.AppDatabase database;
  late Directory cacheRoot;
  late LibraryRepository repository;
  late int libraryId;

  setUp(() async {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    cacheRoot = await Directory.systemTemp.createTemp('stagecue_autovol_test');
    libraryId = await database
        .into(database.libraries)
        .insert(
          db.LibrariesCompanion.insert(
            name: 'Lib',
            localRootPath: cacheRoot.path,
            driveFolderId: const Value('root'),
          ),
        );
    repository = LibraryRepository(
      LocalLibraryDataSource(database),
      _FakeAuthenticator(MockDriveClient()),
      LibrarySyncService(DriftSnapshotStore(database)),
      AudioCacheManager(
        availableDiskBytes: (_) async => 100 * 1024 * 1024 * 1024,
      ),
      LocalSoundDataSource(database),
    );
  });

  tearDown(() async {
    await database.close();
    if (await cacheRoot.exists()) await cacheRoot.delete(recursive: true);
  });

  /// Insère un son ; [present] écrit un sinus de 1 kHz (amplitude 0,5, ≈ −9 LUFS)
  /// à son emplacement de cache.
  Future<int> insertSound(
    String relativePath, {
    required double volume,
    required bool present,
    db_sounds.SoundType type = db_sounds.SoundType.music,
  }) async {
    if (present) {
      const rate = 44100;
      final samples = [
        for (var i = 0; i < rate * 3; i++)
          (0.5 * math.sin(2 * math.pi * 1000 * i / rate) * 32767).round(),
      ];
      File(p.join(cacheRoot.path, relativePath))
        ..createSync(recursive: true)
        ..writeAsBytesSync(wavBytes(sampleRate: rate, left: samples));
    }
    return database
        .into(database.sounds)
        .insert(
          db.SoundsCompanion.insert(
            title: relativePath,
            displayName: relativePath,
            filePath: p.join(cacheRoot.path, relativePath),
            libraryId: Value(libraryId),
            relativePath: Value(relativePath),
            type: Value(type),
            volume: Value(volume),
          ),
        );
  }

  Future<double> volumeOf(int id) async => (await (database.select(
    database.sounds,
  )..where((s) => s.id.equals(id))).getSingle()).volume;

  test('le plan sépare les sons présents des absents et compte les volumes '
      'déjà réglés', () async {
    await insertSound('a.wav', volume: 0.8, present: true);
    await insertSound('b.wav', volume: 1.0, present: true);
    await insertSound('absent.wav', volume: 0.3, present: false);

    final plan = await repository.planAutoVolumeRecompute();

    expect(plan.sounds, hasLength(2));
    expect(plan.unavailable, 1);
    expect(plan.customized, 1);
  });

  test(
    'écrit le volume mesuré selon le type, sans toucher aux absents',
    () async {
      final music = await insertSound('m.wav', volume: 0.8, present: true);
      final ambiance = await insertSound(
        'amb.wav',
        volume: 1.0,
        present: true,
        type: db_sounds.SoundType.ambiance,
      );
      final absent = await insertSound('x.wav', volume: 0.3, present: false);

      final plan = await repository.planAutoVolumeRecompute();
      final progress = <(int, int)>[];
      final result = await repository.recomputeAutoVolumes(
        plan,
        onProgress: (done, total) => progress.add((done, total)),
      );

      expect(result.updated, 2);
      expect(result.cancelled, isFalse);
      expect(progress.last, (2, 2));
      // ≈ −9 LUFS : musique ramenée vers −20, ambiance vers −26 (donc plus bas).
      expect(
        await volumeOf(music),
        closeTo(math.pow(10, (-20 + 9.03) / 20), 0.03),
      );
      expect(await volumeOf(ambiance), lessThan(await volumeOf(music)));
      expect(await volumeOf(absent), 0.3);
    },
    skip: skip,
  );

  test('annulée : s\'arrête sans rien écrire de plus', () async {
    final id = await insertSound('m.wav', volume: 0.8, present: true);

    final plan = await repository.planAutoVolumeRecompute();
    final result = await repository.recomputeAutoVolumes(
      plan,
      isCancelled: () => true,
    );

    expect(result.cancelled, isTrue);
    expect(result.updated, 0);
    expect(await volumeOf(id), 0.8);
  }, skip: skip);

  test('un fichier illisible garde son volume et est compté', () async {
    final id = await insertSound('junk.wav', volume: 0.6, present: false);
    File(
      p.join(cacheRoot.path, 'junk.wav'),
    ).writeAsBytesSync(List.filled(64, 7));

    final plan = await repository.planAutoVolumeRecompute();
    final result = await repository.recomputeAutoVolumes(plan);

    expect(result.updated, 0);
    // Selon que la validation d'en-tête le rejette (ignoré) ou que la mesure
    // échoue (non mesurable) : dans les deux cas il est compté, jamais écrit.
    expect(result.unmeasurable + result.skipped, 1);
    expect(await volumeOf(id), 0.6);
  }, skip: skip);
}
