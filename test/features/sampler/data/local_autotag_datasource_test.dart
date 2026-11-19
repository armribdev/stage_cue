import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/core/database/sounds.dart' as db_types;
import 'package:stage_cue/features/sampler/data/datasources/local_autotag_datasource.dart';

/// Réouverture de l'analyse de tags pour le recalcul de maintenance
/// (décision 0049) : ne touche que les musiques non traitées, jamais les tags de
/// l'utilisateur.
void main() {
  late db.AppDatabase database;
  late LocalAutoTagDataSource dataSource;
  final decidedAt = DateTime(2026, 11, 19);
  final embedding = Uint8List.fromList([1, 2, 3, 4]);

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    dataSource = LocalAutoTagDataSource(database);
  });
  tearDown(() => database.close());

  Future<int> insertSound(
    String title, {
    db_types.SoundType type = db_types.SoundType.music,
    bool processed = false,
    bool withEmbedding = true,
    bool decided = true,
  }) async {
    final id = await database
        .into(database.sounds)
        .insert(
          db.SoundsCompanion.insert(
            title: title,
            displayName: title,
            filePath: '/cache/$title.mp3',
            type: Value(type),
            isProcessed: Value(processed),
            autoEmbedding: Value(withEmbedding ? embedding : null),
            autoTaggedAt: Value(decided ? decidedAt : null),
          ),
        );
    await database
        .into(database.soundAutoTags)
        .insert(
          db.SoundAutoTagsCompanion.insert(
            soundId: id,
            tagId: 1,
            score: 0.5,
            updatedAt: Value(decidedAt),
          ),
        );
    return id;
  }

  Future<db.Sound> sound(int id) => (database.select(
    database.sounds,
  )..where((s) => s.id.equals(id))).getSingle();

  Future<int> suggestionsOf(int id) async => (await (database.select(
    database.soundAutoTags,
  )..where((t) => t.soundId.equals(id))).get()).length;

  test('suggestions seules : rouvre la décision, garde l\'empreinte', () async {
    final id = await insertSound('a');

    final reopened = await dataSource.reopenAnalysis([
      id,
    ], dropEmbeddings: false);

    expect(reopened, 1);
    final row = await sound(id);
    expect(row.autoTaggedAt, isNull);
    expect(row.autoEmbedding, embedding);
    expect(await suggestionsOf(id), 0);
  });

  test('avec empreintes : efface aussi l\'empreinte', () async {
    final id = await insertSound('a');

    await dataSource.reopenAnalysis([id], dropEmbeddings: true);

    final row = await sound(id);
    expect(row.autoTaggedAt, isNull);
    expect(row.autoEmbedding, isNull);
    // Prêt pour un nouveau passage : candidat de l'analyse.
    expect((await dataSource.soundsToAnalyze()).map((s) => s.id), [id]);
  });

  test('ne touche jamais un son traité, ni un autre type', () async {
    final processed = await insertSound('p', processed: true);
    final effect = await insertSound('e', type: db_types.SoundType.soundEffect);

    final reopened = await dataSource.reopenAnalysis([
      processed,
      effect,
    ], dropEmbeddings: true);

    expect(reopened, 0);
    for (final id in [processed, effect]) {
      final row = await sound(id);
      expect(row.autoTaggedAt, decidedAt);
      expect(row.autoEmbedding, embedding);
      expect(await suggestionsOf(id), 1);
    }
  });

  test('suggestions seules : un son écarté (sans empreinte) n\'est pas '
      'rouvert', () async {
    final skipped = await insertSound('s', withEmbedding: false);

    final reopened = await dataSource.reopenAnalysis([
      skipped,
    ], dropEmbeddings: false);

    expect(reopened, 0);
    expect((await sound(skipped)).autoTaggedAt, decidedAt);
  });

  test('ne rouvre que les sons demandés', () async {
    final asked = await insertSound('asked');
    final other = await insertSound('other');

    await dataSource.reopenAnalysis([asked], dropEmbeddings: false);

    expect((await sound(other)).autoTaggedAt, decidedAt);
    expect(await suggestionsOf(other), 1);
  });

  test('traite un lot plus grand que la limite de variables SQLite', () async {
    final ids = [for (var i = 0; i < 1200; i++) await insertSound('s$i')];

    final reopened = await dataSource.reopenAnalysis(
      ids,
      dropEmbeddings: false,
    );

    expect(reopened, 1200);
  });
}
