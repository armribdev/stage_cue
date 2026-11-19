import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/audio/loudness_analyzer.dart'
    show kGainMeasureGeneration;
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

/// Recalcul en masse du gain « auto » (décisions 0036, 0044 et 0045) : ne mesure
/// que ce qui est déjà sur l'appareil, écrit le gain au fil de l'eau, s'arrête
/// proprement.
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
    required double gain,
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
            gain: Value(gain),
          ),
        );
  }

  Future<double> gainOf(int id) async => (await (database.select(
    database.sounds,
  )..where((s) => s.id.equals(id))).getSingle()).gain;

  test('le plan sépare les sons présents des absents et compte les gains '
      'déjà réglés', () async {
    await insertSound('a.wav', gain: 0.8, present: true);
    await insertSound('b.wav', gain: 1.0, present: true);
    await insertSound('absent.wav', gain: 0.3, present: false);

    final plan = await repository.planAutoVolumeRecompute();

    expect(plan.sounds, hasLength(2));
    expect(plan.unavailable, 1);
    expect(plan.customized, 1);
  });

  test('écrit le gain mesuré selon le type, sans toucher aux absents', () async {
    final music = await insertSound('m.wav', gain: 0.8, present: true);
    final ambiance = await insertSound(
      'amb.wav',
      gain: 1.0,
      present: true,
      type: db_sounds.SoundType.ambiance,
    );
    final absent = await insertSound('x.wav', gain: 0.3, present: false);

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
    expect(await gainOf(music), closeTo(math.pow(10, (-20 + 9.03) / 20), 0.03));
    expect(await gainOf(ambiance), lessThan(await gainOf(music)));
    expect(await gainOf(absent), 0.3);
  }, skip: skip);

  test('relève un son doux au pic bas au-delà de 1.0, sans jamais dépasser le '
      'plafond de pic', () async {
    // 1 kHz à 0,05 : ≈ −29 LUFS, pic −26 dBFS ; cible musique −20 → +9 dB
    // voulus, et la marge de pic (23 dB) ne les limite pas.
    const rate = 44100;
    final samples = [
      for (var i = 0; i < rate * 3; i++)
        (0.05 * math.sin(2 * math.pi * 1000 * i / rate) * 32767).round(),
    ];
    File(p.join(cacheRoot.path, 'soft.wav'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(wavBytes(sampleRate: rate, left: samples));
    final id = await database
        .into(database.sounds)
        .insert(
          db.SoundsCompanion.insert(
            title: 'soft',
            displayName: 'soft',
            filePath: p.join(cacheRoot.path, 'soft.wav'),
            libraryId: Value(libraryId),
            relativePath: const Value('soft.wav'),
            type: const Value(db_sounds.SoundType.music),
          ),
        );

    final plan = await repository.planAutoVolumeRecompute();
    await repository.recomputeAutoVolumes(plan);

    final gain = await gainOf(id);
    expect(gain, greaterThan(1.0));
    expect(gain, closeTo(math.pow(10, 9 / 20), 0.15));
    // Après relèvement, le pic reste sous le plafond de −3 dBFS.
    expect(0.05 * gain, lessThanOrEqualTo(math.pow(10, -3 / 20)));
  }, skip: skip);

  Future<int?> generationOf(int id) async => (await (database.select(
    database.sounds,
  )..where((s) => s.id.equals(id))).getSingle()).gainMeasureGeneration;

  test('le plan distingue les jamais mesurés des gains réglés, et '
      'onlyUnmeasured ne touche pas à ces derniers', () async {
    final untouched = await insertSound('u.wav', gain: 1.0, present: true);
    await insertSound('t.wav', gain: 0.8, present: true);
    // 1.0 déjà mesuré : ne compte plus comme « jamais mesuré ».
    final measured = await insertSound('m.wav', gain: 1.0, present: true);
    await (database.update(
      database.sounds,
    )..where((s) => s.id.equals(measured))).write(
      const db.SoundsCompanion(
        gainMeasureGeneration: Value(kGainMeasureGeneration),
      ),
    );

    final plan = await repository.planAutoVolumeRecompute();

    expect(plan.sounds, hasLength(3));
    expect(plan.unmeasured, 1);
    final restricted = plan.onlyUnmeasured();
    expect(restricted.sounds.map((s) => s.id), [untouched]);
    expect(restricted.customized, 0);
  });

  test('le recalcul marque chaque son mesuré, et un son qui échoue reste non '
      'mesuré', () async {
    final id = await insertSound('m.wav', gain: 1.0, present: true);
    final junk = await insertSound('junk.wav', gain: 1.0, present: false);
    File(
      p.join(cacheRoot.path, 'junk.wav'),
    ).writeAsBytesSync(List.filled(64, 7));
    expect(await generationOf(id), isNull);

    final plan = await repository.planAutoVolumeRecompute();
    await repository.recomputeAutoVolumes(plan.onlyUnmeasured());

    expect(await generationOf(id), kGainMeasureGeneration);
    expect(await generationOf(junk), isNull);
    final after = await repository.planAutoVolumeRecompute();
    expect(
      after.onlyUnmeasured().sounds.map((s) => s.id),
      isNot(contains(id)),
      reason: 'le son mesuré n\'est plus proposé',
    );
  }, skip: skip);

  test('annulée : s\'arrête sans rien écrire de plus', () async {
    final id = await insertSound('m.wav', gain: 0.8, present: true);

    final plan = await repository.planAutoVolumeRecompute();
    final result = await repository.recomputeAutoVolumes(
      plan,
      isCancelled: () => true,
    );

    expect(result.cancelled, isTrue);
    expect(result.updated, 0);
    expect(await gainOf(id), 0.8);
  }, skip: skip);

  test('un fichier illisible garde son gain et est compté', () async {
    final id = await insertSound('junk.wav', gain: 0.6, present: false);
    File(
      p.join(cacheRoot.path, 'junk.wav'),
    ).writeAsBytesSync(List.filled(64, 7));

    final plan = await repository.planAutoVolumeRecompute();
    final result = await repository.recomputeAutoVolumes(plan);

    expect(result.updated, 0);
    // Selon que la validation d'en-tête le rejette (ignoré) ou que la mesure
    // échoue (non mesurable) : dans les deux cas il est compté, jamais écrit.
    expect(result.unmeasurable + result.skipped, 1);
    expect(await gainOf(id), 0.6);
  }, skip: skip);
}
