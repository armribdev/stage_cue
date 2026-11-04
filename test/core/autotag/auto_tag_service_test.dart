import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/autotag/audio_stream_info.dart';
import 'package:stage_cue/core/autotag/auto_tag_embedder.dart';
import 'package:stage_cue/core/autotag/auto_tag_pack.dart';
import 'package:stage_cue/core/autotag/auto_tag_service.dart';
import 'package:stage_cue/core/autotag/mood_tagging.dart';
import 'package:stage_cue/core/autotag/muq_analyzer.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/core/database/sounds.dart' as db_types;
import 'package:stage_cue/features/sampler/data/datasources/local_autotag_datasource.dart';
import 'package:stage_cue/features/sampler/data/datasources/local_tag_datasource.dart';

/// Empreinte « identité » : score[m] = embedding[m] avec les vecteurs texte
/// ci-dessous. [spike] met l'ambiance [mood] à 1, le reste à 0.
Float32List spike(int? mood) {
  final e = Float32List(kMuqLatentSize);
  if (mood != null) e[mood] = 1;
  return e;
}

Float32List identityText() {
  final t = Float32List(kMoods.length * kMuqLatentSize);
  for (var m = 0; m < kMoods.length; m++) {
    t[m * kMuqLatentSize + m] = 1;
  }
  return t;
}

class FakeEmbedder implements AutoTagEmbedder {
  final Map<String, Float32List> byFile;
  final Map<String, Object> failures;
  final embedded = <String>[];
  bool closed = false;
  FakeEmbedder(this.byFile, {this.failures = const {}});

  @override
  Future<Float32List> embed(File file) async {
    final name = p.basename(file.path);
    embedded.add(name);
    final failure = failures[name];
    if (failure != null) throw failure;
    return byFile[name] ?? spike(null);
  }

  @override
  Future<void> close() async => closed = true;
}

void main() {
  late db.AppDatabase database;
  late Directory dir;
  late LocalAutoTagDataSource data;
  late FakeEmbedder embedder;
  var packInstalled = true;
  var opened = 0;

  setUp(() async {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    dir = Directory.systemTemp.createTempSync('auto_tag_');
    data = LocalAutoTagDataSource(database);
    embedder = FakeEmbedder({});
    packInstalled = true;
    opened = 0;
  });

  tearDown(() async {
    await database.close();
    dir.deleteSync(recursive: true);
  });

  /// Pack factice : le modèle existe ou non selon [packInstalled].
  AutoTagPack pack() {
    final root = Directory(p.join(dir.path, 'pack'))..createSync();
    final model = File(p.join(root.path, AutoTagPack.modelFileName));
    if (packInstalled) {
      model.writeAsBytesSync([1]);
    } else if (model.existsSync()) {
      model.deleteSync();
    }
    return AutoTagPack(root);
  }

  AutoTagService service({Set<String> missingFiles = const {}}) =>
      AutoTagService(
        data: data,
        pack: pack(),
        libraryRoots: () async => {},
        probeAvailable: (sounds) async => {
          for (final s in sounds)
            if (File(s.filePath).existsSync()) s.id,
        },
        loadScorer: () async => MoodScorer(identityText()),
        openEmbedder: (_) async {
          opened++;
          return embedder;
        },
        now: () => DateTime.utc(2026, 11, 4, 12),
      );

  /// Insère un son (fichier présent par défaut) et renvoie son id.
  Future<int> addSound(
    String name, {
    db_types.SoundType type = db_types.SoundType.music,
    bool processed = false,
    bool withFile = true,
  }) async {
    final path = p.join(dir.path, name);
    if (withFile) File(path).writeAsBytesSync([0]);
    return database
        .into(database.sounds)
        .insert(
          db.SoundsCompanion.insert(
            title: name,
            displayName: name,
            filePath: path,
            type: Value(type),
            isProcessed: Value(processed),
          ),
        );
  }

  /// 60 musiques « t0.mp3 »… dont 15 pointent une ambiance chacune (ids rendus).
  Future<List<int>> addLibrary({int count = 60}) async {
    final ids = <int>[];
    final byFile = <String, Float32List>{};
    for (var i = 0; i < count; i++) {
      final name = 't$i.mp3';
      ids.add(await addSound(name));
      // Les 15 premières portent chacune une ambiance différente.
      byFile[name] = spike(i < kMoods.length ? i : null);
    }
    embedder.byFile.addAll(byFile);
    return ids;
  }

  /// Tags de l'IA d'un son (masqués compris).
  Future<List<String>> tagNames(int soundId) async {
    final rows = await database
        .customSelect(
          'SELECT t.name AS name FROM sound_auto_tags st '
          'JOIN tags t ON t.id = st.tag_id WHERE st.sound_id = ? '
          'ORDER BY t.name',
          variables: [Variable<int>(soundId)],
        )
        .get();
    return [for (final r in rows) r.read<String>('name')];
  }

  /// Tags de l'utilisateur d'un son.
  Future<List<String>> userTagNames(int soundId) async {
    final rows = await database
        .customSelect(
          'SELECT t.name AS name FROM sound_tags st '
          'JOIN tags t ON t.id = st.tag_id WHERE st.sound_id = ? '
          'ORDER BY t.name',
          variables: [Variable<int>(soundId)],
        )
        .get();
    return [for (final r in rows) r.read<String>('name')];
  }

  Future<db.Sound> sound(int id) => (database.select(
    database.sounds,
  )..where((s) => s.id.equals(id))).getSingle();

  String? never() => null;

  test('pack absent : aucun modèle ouvert, rien écrit', () async {
    packInstalled = false;
    final ids = await addLibrary();
    final report = await service().run(stopReason: never);
    expect(opened, 0);
    expect(report.analyzed, 0);
    expect((await sound(ids.first)).autoEmbedding, isNull);
    expect((await sound(ids.first)).autoTaggedAt, isNull);
  });

  test('analyse puis pose les ambiances une fois 50 sons analysés', () async {
    final ids = await addLibrary();
    final report = await service().run(stopReason: never);

    expect(report.analyzed, 60);
    expect(embedder.closed, isTrue, reason: 'modèle libéré en fin de passage');
    // Sons i < 15 : l'ambiance i ressort loin devant les autres.
    expect(await tagNames(ids[4]), ['Angoisse']);
    expect(await tagNames(ids[8]), ['Calme']);
    // Merveilleux (9) → tag Magie ; Sensuel (14) → Romantique.
    expect(await tagNames(ids[9]), ['Magie']);
    expect(await tagNames(ids[14]), ['Romantique']);
    // Les autres sons, banals, n'ont aucun tag mais sont marqués décidés.
    expect(await tagNames(ids[40]), isEmpty);
    expect((await sound(ids[40])).autoTaggedAt, isNotNull);
    expect((await sound(ids[40])).autoEmbedding, isNotNull);
    expect(report.soundsTagged, 15);
    // Jamais « traité » : l'utilisateur valide lui-même.
    expect((await sound(ids[4])).isProcessed, isFalse);
  });

  test('moins de 50 sons analysés : empreintes gardées, aucun tag', () async {
    final ids = await addLibrary(count: 30);
    await service().run(stopReason: never);
    expect(await tagNames(ids[4]), isEmpty);
    expect((await sound(ids[4])).autoEmbedding, isNotNull);
    expect((await sound(ids[4])).autoTaggedAt, isNull, reason: 'pas décidé');

    // La bibliothèque grossit : les premiers sons reçoivent leurs tags sans
    // être ré-analysés.
    embedder.embedded.clear();
    final more = await addLibrary(count: 0);
    expect(more, isEmpty);
    for (var i = 30; i < 60; i++) {
      await addSound('t$i.mp3');
    }
    await service().run(stopReason: never);
    expect(embedder.embedded, isNot(contains('t4.mp3')));
    expect(await tagNames(ids[4]), ['Angoisse']);
  });

  test('un son traité ou d’un autre type reste intact', () async {
    final ids = await addLibrary();
    final processed = await addSound('traite.mp3', processed: true);
    final effect = await addSound(
      'bruit.mp3',
      type: db_types.SoundType.soundEffect,
    );
    final ambiance = await addSound(
      'ambiance.mp3',
      type: db_types.SoundType.ambiance,
    );
    for (final n in ['traite.mp3', 'bruit.mp3', 'ambiance.mp3']) {
      embedder.byFile[n] = spike(4);
    }

    await service().run(stopReason: never);

    for (final n in ['traite.mp3', 'bruit.mp3', 'ambiance.mp3']) {
      expect(embedder.embedded, isNot(contains(n)));
    }
    for (final id in [processed, effect, ambiance]) {
      expect(await tagNames(id), isEmpty);
      expect((await sound(id)).autoTaggedAt, isNull);
    }
    expect(await tagNames(ids[4]), ['Angoisse']);
  });

  test('un son déjà tagué à la main reçoit en plus les tags de l’IA, '
      'dans une couche séparée', () async {
    final ids = await addLibrary();
    final tagId =
        (await database
                .customSelect("SELECT id FROM tags WHERE name = 'Sombre'")
                .getSingle())
            .read<int>('id');
    await database
        .into(database.soundTags)
        .insert(db.SoundTagsCompanion.insert(soundId: ids[4], tagId: tagId));

    await service().run(stopReason: never);

    expect(await userTagNames(ids[4]), ['Sombre'], reason: 'tag manuel intact');
    expect(await tagNames(ids[4]), ['Angoisse'], reason: 'tag de l’IA à part');
  });

  test('éligibilité revérifiée à la décision', () async {
    final ids = await addLibrary(count: 30);
    await service().run(stopReason: never); // < 50 : pas de décision
    // Entre-temps, l’utilisateur traite l’un des sons.
    await (database.update(database.sounds)..where((s) => s.id.equals(ids[4])))
        .write(const db.SoundsCompanion(isProcessed: Value(true)));
    for (var i = 30; i < 60; i++) {
      await addSound('t$i.mp3');
    }

    await service().run(stopReason: never);

    expect(await tagNames(ids[4]), isEmpty, reason: 'traité entre-temps');
    expect((await sound(ids[4])).autoTaggedAt, isNotNull);
    expect(await tagNames(ids[9]), ['Magie'], reason: 'les autres suivent');
  });

  test(
    'un tag masqué reste en mémoire : jamais reposé, jamais supprimé',
    () async {
      final ids = await addLibrary();
      await service().run(stopReason: never);
      final angoisse =
          (await database
                  .customSelect("SELECT id FROM tags WHERE name = 'Angoisse'")
                  .getSingle())
              .read<int>('id');
      await LocalTagDataSource(
        database,
      ).setAutoTagHidden(ids[4], angoisse, hidden: true);

      // Décision rejouée (ex. marque remise à zéro) : la ligne masquée ne bouge pas.
      await (database.update(database.sounds)
            ..where((s) => s.id.equals(ids[4])))
          .write(const db.SoundsCompanion(autoTaggedAt: Value(null)));
      await service().run(stopReason: never);

      final rows = await database.select(database.soundAutoTags).get();
      final row = rows.singleWhere((r) => r.soundId == ids[4]);
      expect(row.tagId, angoisse);
      expect(row.hidden, isTrue);
      expect(await tagNames(ids[4]), ['Angoisse'], reason: 'toujours en base');
    },
  );

  test(
    'tags d’IA reçus d’un autre appareil : le son n’est pas recalculé',
    () async {
      final ids = await addLibrary();
      final tristeId =
          (await database
                  .customSelect("SELECT id FROM tags WHERE name = 'Triste'")
                  .getSingle())
              .read<int>('id');
      await database
          .into(database.soundAutoTags)
          .insert(
            db.SoundAutoTagsCompanion.insert(soundId: ids[4], tagId: tristeId),
          );

      await service().run(stopReason: never);

      expect(await tagNames(ids[4]), [
        'Triste',
      ], reason: 'celui du distant, rien ajouté');
      expect((await sound(ids[4])).autoTaggedAt, isNotNull);
    },
  );

  test('fichier non analysable : écarté pour de bon, sans empreinte', () async {
    final id = await addSound('opus.opus');
    embedder = FakeEmbedder(
      {},
      failures: {'opus.opus': const AudioNotAnalyzable('opus non géré')},
    );
    final report = await service().run(stopReason: never);
    expect(report.notAnalyzable, {'opus non géré': 1});
    expect((await sound(id)).autoTaggedAt, isNotNull);
    expect((await sound(id)).autoEmbedding, isNull);

    embedder.embedded.clear();
    await service().run(stopReason: never);
    expect(embedder.embedded, isEmpty, reason: 'jamais retenté');
  });

  test('échec inattendu : réessayé au passage suivant', () async {
    final id = await addSound('a.mp3');
    embedder = FakeEmbedder({}, failures: {'a.mp3': StateError('boum')});
    final report = await service().run(stopReason: never);
    expect(report.failed, 1);
    expect((await sound(id)).autoTaggedAt, isNull);

    embedder = FakeEmbedder({});
    await service().run(stopReason: never);
    expect((await sound(id)).autoEmbedding, isNotNull);
  });

  test('cinq échecs de suite : le passage s\'arrête', () async {
    for (var i = 0; i < 8; i++) {
      await addSound('f$i.mp3');
    }
    embedder = FakeEmbedder(
      {},
      failures: {for (var i = 0; i < 8; i++) 'f$i.mp3': StateError('modèle')},
    );
    final report = await service().run(stopReason: never);
    expect(report.failed, 5);
    expect(report.interruptedBy, contains('erreurs répétées'));
    expect(embedder.embedded.length, 5);
  });

  test('arrêt demandé : empreintes gardées, passage interrompu', () async {
    await addLibrary();
    var calls = 0;
    final report = await service().run(
      stopReason: () => ++calls > 10 ? 'Mode Spectacle' : null,
    );
    expect(report.interruptedBy, 'Mode Spectacle');
    expect(report.analyzed, 10);
    expect(embedder.closed, isTrue);
  });

  test('fichier pas encore téléchargé : ignoré, compté', () async {
    await addLibrary(count: 3);
    await addSound('absent.mp3', withFile: false);
    final report = await service().run(stopReason: never);
    expect(report.notDownloaded, 1);
    expect(report.analyzed, 3);
    expect(embedder.embedded, isNot(contains('absent.mp3')));
  });

  test('deux passages simultanés : le second ne fait rien', () async {
    await addLibrary(count: 5);
    final s = service();
    final first = s.run(stopReason: never);
    final second = await s.run(stopReason: never);
    expect(second.analyzed, 0);
    expect((await first).analyzed, 5);
    expect(s.isRunning, isFalse);
  });
}
