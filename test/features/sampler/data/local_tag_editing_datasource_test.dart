import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/features/sampler/data/datasources/local_tag_editing_datasource.dart';
import 'package:stage_cue/features/sampler/domain/entities/tag_catalog_change.dart';

/// Éditeur de catalogue de développement (décision 0047) : chaque écriture
/// s'applique à la base et renvoie la modification à déclarer dans le code.
/// Le seed de test est le vrai catalogue (`onCreate`), d'où les tags utilisés.
void main() {
  late db.AppDatabase database;
  late LocalTagEditingDataSource editor;

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    editor = LocalTagEditingDataSource(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<int> categoryId(String name) async {
    final row = await database
        .customSelect(
          'SELECT id FROM tag_categories WHERE name = ?',
          variables: [Variable<String>(name)],
        )
        .getSingle();
    return row.read<int>('id');
  }

  Future<int?> tagId(String category, String name) async {
    final row = await database
        .customSelect(
          'SELECT t.id FROM tags t JOIN tag_categories c '
          'ON c.id = t.category_id WHERE c.name = ? AND t.name = ?',
          variables: [Variable<String>(category), Variable<String>(name)],
        )
        .getSingleOrNull();
    return row?.read<int>('id');
  }

  Future<int> tagUsage(int tagId) async {
    final row = await database
        .customSelect(
          'SELECT COUNT(*) AS n FROM sound_tags WHERE tag_id = ?',
          variables: [Variable<int>(tagId)],
        )
        .getSingle();
    return row.read<int>('n');
  }

  Future<List<String>> aliasesOf(int tagId) async {
    final rows = await database
        .customSelect(
          'SELECT alias FROM tag_aliases WHERE tag_id = ? ORDER BY alias',
          variables: [Variable<int>(tagId)],
        )
        .get();
    return [for (final r in rows) r.read<String>('alias')];
  }

  Future<void> tagOnSound(int tagId, String title) async {
    final soundId = await database
        .into(database.sounds)
        .insert(
          db.SoundsCompanion.insert(
            title: title,
            displayName: title,
            filePath: '/x/$title.mp3',
          ),
        );
    await database
        .into(database.soundTags)
        .insert(db.SoundTagsCompanion.insert(soundId: soundId, tagId: tagId));
  }

  group('createTag', () {
    test('crée le tag et ses alias, et le déclare', () async {
      final change = await editor.createTag(
        categoryId: await categoryId('AMBIANCE'),
        name: '  Cirque ',
        aliases: ['chapiteau', 'clown'],
      );

      final id = await tagId('AMBIANCE', 'Cirque');
      expect(id, isNotNull);
      expect(await aliasesOf(id!), ['chapiteau', 'clown']);
      expect(change, isA<TagCreated>());
      change as TagCreated;
      expect(change.category, 'AMBIANCE');
      expect(change.tag, 'Cirque');
      expect(change.aliases, ['chapiteau', 'clown']);
    });

    test('refuse un nom vide ou déjà pris dans la catégorie', () async {
      final ambiance = await categoryId('AMBIANCE');
      await expectLater(
        editor.createTag(categoryId: ambiance, name: '  '),
        throwsA(isA<TagEditException>()),
      );
      await expectLater(
        editor.createTag(categoryId: ambiance, name: 'nature'),
        throwsA(isA<TagEditException>()),
      );
    });

    test('un alias déjà porté annule toute la création', () async {
      // « pluie » est un alias de Météo : unique sur tout le catalogue.
      await expectLater(
        editor.createTag(
          categoryId: await categoryId('AMBIANCE'),
          name: 'Cirque',
          aliases: ['chapiteau', 'pluie'],
        ),
        throwsA(
          isA<TagEditException>().having(
            (e) => e.message,
            'message',
            contains('Météo'),
          ),
        ),
      );
      expect(await tagId('AMBIANCE', 'Cirque'), isNull);
    });

    test('le tag survit à la réconciliation du catalogue', () async {
      await editor.createTag(
        categoryId: await categoryId('AMBIANCE'),
        name: 'Cirque',
      );
      await database.reconcileTagCatalog();
      expect(await tagId('AMBIANCE', 'Cirque'), isNotNull);
    });
  });

  group('renameTag', () {
    test('garde les usages, et l\'ancien nom devient un alias', () async {
      final id = (await tagId('AMBIANCE', 'Urbain'))!;
      await tagOnSound(id, 'Rue');

      final change = await editor.renameTag(tagId: id, name: 'Ville');

      expect(await tagId('AMBIANCE', 'Urbain'), isNull);
      expect(await tagId('AMBIANCE', 'Ville'), id);
      expect(await tagUsage(id), 1);
      expect(await aliasesOf(id), contains('Urbain'));
      expect(change, isA<TagRenamed>());
      change as TagRenamed;
      expect((change.from, change.to), ('Urbain', 'Ville'));
    });

    test('refuse un nom déjà pris, inchangé ou vide', () async {
      final id = (await tagId('AMBIANCE', 'Urbain'))!;
      await expectLater(
        editor.renameTag(tagId: id, name: 'Nature'),
        throwsA(isA<TagEditException>()),
      );
      await expectLater(
        editor.renameTag(tagId: id, name: 'Urbain'),
        throwsA(isA<TagEditException>()),
      );
      await expectLater(
        editor.renameTag(tagId: id, name: ' '),
        throwsA(isA<TagEditException>()),
      );
    });

    test('une retouche de casse ne crée pas d\'alias', () async {
      final id = (await tagId('AMBIANCE', 'Urbain'))!;
      await editor.renameTag(tagId: id, name: 'URBAIN');
      expect(await aliasesOf(id), isNot(contains('Urbain')));
    });

    test('refuse une ambiance de l\'analyse automatique', () async {
      final id = (await tagId('EMOTION_STYLE', 'Triste'))!;
      await expectLater(
        editor.renameTag(tagId: id, name: 'Chagrin'),
        throwsA(isA<TagEditException>()),
      );
      expect(await tagId('EMOTION_STYLE', 'Triste'), id);
    });
  });

  group('mergeTag', () {
    test(
      'reporte les usages, les alias et le nom sur le tag d\'accueil',
      () async {
        final from = (await tagId('AMBIANCE', 'Urbain'))!;
        final into = (await tagId('AMBIANCE', 'Nature'))!;
        await tagOnSound(from, 'Klaxon');
        final usageBefore = await tagUsage(into);

        final change = await editor.mergeTag(fromId: from, intoId: into);

        expect(await tagId('AMBIANCE', 'Urbain'), isNull);
        expect(await tagUsage(into), usageBefore + 1);
        expect(await aliasesOf(into), containsAll(['Urbain', 'ville', 'rue']));
        expect(change, isA<TagMerged>());
        change as TagMerged;
        expect((change.from, change.into), ('Urbain', 'Nature'));
      },
    );

    test('refuse la fusion dans soi-même et d\'une ambiance', () async {
      final urbain = (await tagId('AMBIANCE', 'Urbain'))!;
      await expectLater(
        editor.mergeTag(fromId: urbain, intoId: urbain),
        throwsA(isA<TagEditException>()),
      );
      final triste = (await tagId('EMOTION_STYLE', 'Triste'))!;
      await expectLater(
        editor.mergeTag(fromId: triste, intoId: urbain),
        throwsA(isA<TagEditException>()),
      );
      expect(await tagId('EMOTION_STYLE', 'Triste'), triste);
    });
  });

  group('deleteTag', () {
    test('supprime le tag avec ses usages et ses alias', () async {
      final id = (await tagId('AMBIANCE', 'Urbain'))!;
      await tagOnSound(id, 'Klaxon');

      final change = await editor.deleteTag(id);

      expect(await tagId('AMBIANCE', 'Urbain'), isNull);
      expect(await tagUsage(id), 0);
      expect(await aliasesOf(id), isEmpty);
      expect(change, isA<TagDeleted>());
    });

    test('refuse une ambiance de l\'analyse automatique', () async {
      final id = (await tagId('EMOTION_STYLE', 'Triste'))!;
      await expectLater(editor.deleteTag(id), throwsA(isA<TagEditException>()));
      expect(await tagId('EMOTION_STYLE', 'Triste'), id);
    });
  });

  group('alias', () {
    test('ajouter puis retirer un alias, y compris sur une ambiance', () async {
      final id = (await tagId('EMOTION_STYLE', 'Triste'))!;

      final added = await editor.addAlias(tagId: id, alias: ' chagrin ');
      expect(added, isA<TagAliasAdded>());
      expect(await aliasesOf(id), contains('chagrin'));

      final aliasId = (await editor.load())
          .expand((c) => c.entries)
          .firstWhere((e) => e.tag.id == id)
          .aliases
          .firstWhere((a) => a.alias == 'chagrin')
          .id;
      final removed = await editor.removeAlias(aliasId);
      expect(removed, isA<TagAliasRemoved>());
      expect(await aliasesOf(id), isNot(contains('chagrin')));
    });

    test(
      'refuse un alias vide ou déjà porté, par n\'importe quel tag',
      () async {
        final id = (await tagId('AMBIANCE', 'Nature'))!;
        await expectLater(
          editor.addAlias(tagId: id, alias: ' '),
          throwsA(isA<TagEditException>()),
        );
        // « ville » appartient à Urbain.
        await expectLater(
          editor.addAlias(tagId: id, alias: 'Ville'),
          throwsA(isA<TagEditException>()),
        );
      },
    );
  });

  test('load donne les usages et les alias de chaque tag', () async {
    final id = (await tagId('AMBIANCE', 'Urbain'))!;
    await tagOnSound(id, 'Klaxon');

    final entry = (await editor.load())
        .expand((c) => c.entries)
        .firstWhere((e) => e.tag.id == id);

    expect(entry.usage, 1);
    expect(entry.aliases.map((a) => a.alias), containsAll(['ville', 'rue']));
  });
}
