// Tags déduits du titre (décision 0041) sur la vraie seed de tags et une base
// en mémoire : lecture du vocabulaire, propositions pour l'action groupée et
// écriture additive réservée aux sons non traités.

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/core/utils/title_tag_matcher.dart';
import 'package:stage_cue/features/sampler/data/datasources/local_tag_datasource.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';
import 'package:stage_cue/features/sampler/domain/entities/tag_item.dart';
import 'package:stage_cue/features/sampler/presentation/utils/title_tag_proposals.dart';

void main() {
  late db.AppDatabase database;
  late LocalTagDataSource dataSource;
  late TitleTagMatcher matcher;

  setUp(() async {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    dataSource = LocalTagDataSource(database);
    matcher = TitleTagMatcher(await dataSource.getTagVocabulary());
  });

  tearDown(() => database.close());

  Future<int> tagId(String name) async =>
      (await database
              .customSelect(
                'SELECT id FROM tags WHERE name = ?',
                variables: [Variable<String>(name)],
              )
              .getSingle())
          .read<int>('id');

  Future<int> insertSound(String title, {bool processed = false}) => database
      .into(database.sounds)
      .insert(
        db.SoundsCompanion.insert(
          title: title,
          filePath: '/cache/$title.wav',
          displayName: title,
          isProcessed: processed ? const Value(true) : const Value.absent(),
        ),
      );

  Sound soundOf(int id, String title, {bool processed = false}) => Sound(
    id: id,
    title: title,
    filePath: '/cache/$title.wav',
    createdAt: DateTime(2026, 11, 18),
    isProcessed: processed,
  );

  Future<List<String>> namesFor(String title) async {
    final byId = {
      for (final row in await database.select(database.tagItems).get())
        row.id: row.name,
    };
    return [for (final m in matcher.suggest(title)) byId[m.tagId]!];
  }

  group('vocabulaire de la seed', () {
    test('chaque tag porte son nom parmi ses expressions', () async {
      final vocabulary = await dataSource.getTagVocabulary();
      final names = {
        for (final row in await database.select(database.tagItems).get())
          row.id: row.name,
      };
      expect(vocabulary, hasLength(names.length));
      for (final entry in vocabulary) {
        expect(entry.phrases, contains(names[entry.tagId]));
      }
    });

    test('un titre qui nomme des tags de la seed les déduit', () async {
      expect(
        await namesFor('Pluie sur la porte'),
        containsAll(['Pluie', 'Porte']),
      );
    });

    test('les faux positifs connus ne déduisent rien', () async {
      expect(await namesFor('Barbara - Ma plus belle histoire'), isEmpty);
      expect(await namesFor('Spring Waltz'), isEmpty);
      expect(await namesFor('Jacques Brel - Ne me quitte pas'), isEmpty);
    });
  });

  group('propositions pour l’action groupée', () {
    test('ignorent les sons traités et ceux sans correspondance', () async {
      final matching = soundOf(1, 'Pluie porte');
      final processed = soundOf(2, 'Pluie porte', processed: true);
      final nothing = soundOf(3, 'Barbara');

      final proposals = proposeTitleTags(
        sounds: [matching, processed, nothing],
        tagsBySound: const {},
        matcher: matcher,
      );

      expect(proposals.map((p) => p.sound.id), [1]);
    });

    test('excluent les tags déjà posés', () async {
      final pluie = await tagId('Pluie');
      final posed = TagItem(
        id: pluie,
        categoryId: 0,
        name: 'Pluie',
        normalizedName: 'pluie',
      );
      final proposals = proposeTitleTags(
        sounds: [soundOf(1, 'Pluie')],
        tagsBySound: {
          1: [posed],
        },
        matcher: matcher,
      );
      expect(proposals, isEmpty);
    });

    test('cherchent aussi dans le titre du fichier si le nom a changé', () {
      final renamed = Sound(
        id: 1,
        title: 'Pluie porte',
        displayName: 'Mon son 12',
        filePath: '/cache/x.wav',
        createdAt: DateTime(2026, 11, 18),
      );
      final proposals = proposeTitleTags(
        sounds: [renamed],
        tagsBySound: const {},
        matcher: matcher,
      );
      expect(proposals, hasLength(1));
    });
  });

  group('addTagsToUnprocessedSounds', () {
    Future<Set<int>> tagsOf(int soundId) async => {
      for (final r in await (database.select(
        database.soundTags,
      )..where((t) => t.soundId.equals(soundId))).get())
        r.tagId,
    };

    test('ajoute sans remplacer les tags existants', () async {
      final sound = await insertSound('Pluie');
      final porte = await tagId('Porte');
      final pluie = await tagId('Pluie');
      await dataSource.setTagsForSound(sound, [porte]);

      final result = await dataSource.addTagsToUnprocessedSounds({
        sound: {pluie},
      });

      expect(await tagsOf(sound), {porte, pluie});
      expect(result, (sounds: 1, tags: 1));
    });

    test('est idempotent : un tag déjà posé n’est pas recompté', () async {
      final sound = await insertSound('Pluie');
      final pluie = await tagId('Pluie');

      await dataSource.addTagsToUnprocessedSounds({
        sound: {pluie},
      });
      final again = await dataSource.addTagsToUnprocessedSounds({
        sound: {pluie},
      });

      expect(again, (sounds: 0, tags: 0));
      expect(await tagsOf(sound), {pluie});
    });

    test('ne touche jamais un son traité', () async {
      final fresh = await insertSound('Pluie');
      final frozen = await insertSound('Pluie 2', processed: true);
      final pluie = await tagId('Pluie');

      final result = await dataSource.addTagsToUnprocessedSounds({
        fresh: {pluie},
        frozen: {pluie},
      });

      expect(await tagsOf(frozen), isEmpty);
      expect(await tagsOf(fresh), {pluie});
      expect(result, (sounds: 1, tags: 1));
    });

    test('ne marque pas les sons traités', () async {
      final sound = await insertSound('Pluie');
      await dataSource.addTagsToUnprocessedSounds({
        sound: {await tagId('Pluie')},
      });
      final row = await (database.select(
        database.sounds,
      )..where((s) => s.id.equals(sound))).getSingle();
      expect(row.isProcessed, isFalse);
    });

    test('n’écrit rien parmi les suggestions de l’IA', () async {
      final sound = await insertSound('Pluie');
      await dataSource.addTagsToUnprocessedSounds({
        sound: {await tagId('Pluie')},
      });
      expect(await database.select(database.soundAutoTags).get(), isEmpty);
    });

    test('une demande vide est sans effet', () async {
      expect(await dataSource.addTagsToUnprocessedSounds(const {}), (
        sounds: 0,
        tags: 0,
      ));
    });
  });
}
