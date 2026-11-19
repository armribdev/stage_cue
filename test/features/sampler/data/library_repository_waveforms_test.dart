import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/audio/waveform_extractor.dart';
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

class _MockDriveClient extends Mock implements DriveClient {}

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

/// Rattrapage et recalcul de waveforms (décision 0049) : lecture seule des
/// fichiers, jamais de téléchargement, jamais de gain écrit (décision 0048).
///
/// Le moteur SoLoud n'est pas initialisé sous `flutter test` : `extractWaveform`
/// répond « transitoire », ce qui exerce le chemin d'arrêt propre (rien n'est
/// écrit, la passe s'arrête). L'écriture elle-même est couverte par
/// `persistWaveformProbe` (`local_sound_datasource_test.dart`).
void main() {
  final skip = soloudNativeSkipReason();
  late db.AppDatabase database;
  late Directory cacheRoot;
  late LibraryRepository repository;
  late LocalSoundDataSource soundDataSource;
  late int libraryId;

  setUp(() async {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    cacheRoot = await Directory.systemTemp.createTemp('stagecue_wave_test');
    libraryId = await database
        .into(database.libraries)
        .insert(
          db.LibrariesCompanion.insert(
            name: 'Lib',
            localRootPath: cacheRoot.path,
            driveFolderId: const Value('root'),
          ),
        );
    soundDataSource = LocalSoundDataSource(database);
    repository = LibraryRepository(
      LocalLibraryDataSource(database),
      _FakeAuthenticator(_MockDriveClient()),
      LibrarySyncService(DriftSnapshotStore(database)),
      AudioCacheManager(
        availableDiskBytes: (_) async => 100 * 1024 * 1024 * 1024,
      ),
      soundDataSource,
    );
  });

  tearDown(() async {
    await database.close();
    if (await cacheRoot.exists()) await cacheRoot.delete(recursive: true);
  });

  Future<int> insertSound(
    String relativePath, {
    required bool present,
    int? generation,
    Uint8List? waveform,
    double gain = 1.0,
  }) async {
    if (present) {
      File(p.join(cacheRoot.path, relativePath))
        ..createSync(recursive: true)
        ..writeAsBytesSync(
          wavBytes(sampleRate: 44100, left: List.filled(44100, 1000)),
        );
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
            type: const Value(db_sounds.SoundType.music),
            gain: Value(gain),
            waveform: Value(waveform),
            waveformProbeGeneration: Value(generation),
          ),
        );
  }

  Future<db.Sound> reload(int id) => (database.select(
    database.sounds,
  )..where((s) => s.id.equals(id))).getSingle();

  test('soundsWithStaleWaveform : jamais sondé ou génération antérieure, '
      'pas la génération courante', () async {
    final never = await insertSound('never.wav', present: true);
    final old = await insertSound(
      'old.wav',
      present: true,
      generation: kWaveformProbeGeneration - 1,
      waveform: Uint8List.fromList([1]),
    );
    final current = await insertSound(
      'current.wav',
      present: true,
      generation: kWaveformProbeGeneration,
      waveform: Uint8List.fromList([1]),
    );

    final stale = repository.soundsWithStaleWaveform(
      await soundDataSource.getAllSounds(),
    );

    expect(stale.map((s) => s.id), unorderedEquals([never, old]));
    expect(stale.map((s) => s.id), isNot(contains(current)));
  });

  test('le rattrapage s\'arrête tout de suite si une raison s\'y oppose, sans '
      'rien écrire', () async {
    final id = await insertSound('a.wav', present: true);
    var asked = 0;

    final result = await repository.backfillStaleWaveforms(
      shouldStop: () {
        asked++;
        return 'Mode Spectacle';
      },
    );

    expect(result.cancelled, isTrue);
    expect(result.updated, 0);
    expect(asked, 1);
    expect((await reload(id)).waveformProbeGeneration, isNull);
  });

  // Interroger `SoLoud.instance.isInitialized` charge la bibliothèque native.
  test('moteur audio pas prêt : la passe s\'arrête, rien n\'est mémorisé, '
      'aucun gain écrit', () async {
    final id = await insertSound('a.wav', present: true);

    final result = await repository.backfillStaleWaveforms(
      shouldStop: () => null,
    );

    expect(result.cancelled, isTrue);
    final row = await reload(id);
    expect(row.waveform, isNull);
    expect(row.waveformProbeGeneration, isNull);
    expect(row.gain, 1.0);
    expect(row.gainMeasureGeneration, isNull);
  }, skip: skip);

  test('sans son à rattraper : rien à faire, pas d\'interruption', () async {
    await insertSound(
      'ok.wav',
      present: true,
      generation: kWaveformProbeGeneration,
      waveform: Uint8List.fromList([1]),
    );

    final result = await repository.backfillStaleWaveforms(
      shouldStop: () => null,
    );

    expect(result.cancelled, isFalse);
    expect(result.updated, 0);
  });

  test('recomputeWaveforms compte les fichiers absents sans rien écrire ni '
      'télécharger', () async {
    final absent = await insertSound('absent.wav', present: false);
    final progress = <(int, int)>[];

    final result = await repository.recomputeWaveforms(
      repository.soundsWithStaleWaveform(await soundDataSource.getAllSounds()),
      onProgress: (done, total) => progress.add((done, total)),
    );

    expect(result.unavailable, 1);
    expect(result.updated, 0);
    expect(result.cancelled, isFalse);
    expect(progress.last, (1, 1));
    expect((await reload(absent)).waveformProbeGeneration, isNull);
  });

  test('recomputeWaveforms respecte l\'annulation', () async {
    await insertSound('a.wav', present: true);
    await insertSound('b.wav', present: true);

    final result = await repository.recomputeWaveforms(
      await soundDataSource.getAllSounds(),
      isCancelled: () => true,
    );

    expect(result.cancelled, isTrue);
    expect(result.updated + result.unsupported + result.unavailable, 0);
  });
}
