// Vérifie les chemins d'UPGRADE de schéma.
//
// Le projet n'a pas de schémas Drift versionnés : à défaut, on fabrique une base
// à l'état v35 en retirant la colonne d'une base fraîche, puis on rouvre par
// `AppDatabase` pour que `onUpgrade` s'exécute pour de vrai. Une migration qui
// ne s'applique pas ne casse aucun test fonctionnel (les bases de test sont
// toujours fraîches) — elle ne casse que les bases des utilisateurs existants.

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/database/database.dart' as db;

void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('stagecue_migration_test');
    file = File('${dir.path}/test.sqlite');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('une base v35 gagne manifest_probe_token sans perdre ses données', () async {
    // 1. Base au schéma courant, avec une bibliothèque et un nœud dossier.
    var database = db.AppDatabase.forTesting(NativeDatabase(file));
    final libraryId = await database
        .into(database.libraries)
        .insert(
          db.LibrariesCompanion.insert(name: 'Lib', localRootPath: '/cache'),
        );
    await database
        .into(database.libraryFolders)
        .insert(
          db.LibraryFoldersCompanion.insert(
            libraryId: libraryId,
            driveFolderId: 'drive-1',
            relativePath: const Value('Portes'),
            lastSyncedRevision: const Value(7),
          ),
        );

    // 2. Rétrograde à l'état v35 : colonne retirée, user_version rembobinée.
    await database.customStatement(
      'ALTER TABLE library_folders '
      'DROP COLUMN manifest_probe_token',
    );
    await database.customStatement('PRAGMA user_version = 35');
    await database.close();

    // 3. Réouverture : `onUpgrade` doit rattraper la colonne manquante.
    database = db.AppDatabase.forTesting(NativeDatabase(file));
    final folders = await database.select(database.libraryFolders).get();

    expect(folders, hasLength(1), reason: 'les données doivent survivre');
    expect(folders.single.driveFolderId, 'drive-1');
    expect(folders.single.relativePath, 'Portes');
    expect(folders.single.lastSyncedRevision, 7);
    // Backfill implicite : null = jamais sondé → le premier pull resonde.
    expect(folders.single.manifestProbeToken, isNull);

    // La colonne doit être écrivable, pas seulement présente — et le jeton doit
    // ressortir au bit près. C'est tout l'intérêt de le stocker en TEXTE : une
    // colonne `dateTime()` perdrait les millisecondes (Drift stocke en secondes
    // epoch) et relirait en heure locale, si bien que la comparaison du pull
    // échouerait toujours et que le cache ne servirait jamais, en silence.
    const probeToken = '2026-07-30T12:00:00.456Z';
    await (database.update(
      database.libraryFolders,
    )..where((f) => f.id.equals(folders.single.id))).write(
      const db.LibraryFoldersCompanion(manifestProbeToken: Value(probeToken)),
    );
    final updated = await database.select(database.libraryFolders).getSingle();
    expect(updated.manifestProbeToken, probeToken);

    await database.close();
  });

  test('une base v36 gagne le suivi du parcours incrémental', () async {
    var database = db.AppDatabase.forTesting(NativeDatabase(file));
    final libraryId = await database
        .into(database.libraries)
        .insert(
          db.LibrariesCompanion.insert(name: 'Lib', localRootPath: '/cache'),
        );

    await database.customStatement(
      'ALTER TABLE libraries DROP COLUMN drive_change_token',
    );
    await database.customStatement(
      'ALTER TABLE libraries DROP COLUMN last_full_scan_at',
    );
    await database.customStatement('PRAGMA user_version = 36');
    await database.close();

    database = db.AppDatabase.forTesting(NativeDatabase(file));
    final row = await (database.select(
      database.libraries,
    )..where((l) => l.id.equals(libraryId))).getSingle();

    expect(row.name, 'Lib', reason: 'les données doivent survivre');
    // Les deux à null : la première passe après migration est donc un scan
    // COMPLET, qui pose le jeton. Un jeton hérité de nulle part ferait démarrer
    // le parcours incrémental sans point de référence.
    expect(row.driveChangeToken, isNull);
    expect(row.lastFullScanAt, isNull);

    await database.close();
  });

  test(
    'une base v37 gagne is_processed, à false pour les sons existants',
    () async {
      var database = db.AppDatabase.forTesting(NativeDatabase(file));
      final soundId = await database
          .into(database.sounds)
          .insert(
            db.SoundsCompanion.insert(
              title: 'porte',
              displayName: 'porte',
              filePath: '/cache/porte.wav',
            ),
          );

      await database.customStatement(
        'ALTER TABLE sounds DROP COLUMN is_processed',
      );
      await database.customStatement('PRAGMA user_version = 37');
      await database.close();

      database = db.AppDatabase.forTesting(NativeDatabase(file));
      final row = await (database.select(
        database.sounds,
      )..where((s) => s.id.equals(soundId))).getSingle();

      expect(row.title, 'porte', reason: 'les données doivent survivre');
      // Tous les sons existants démarrent « à traiter ».
      expect(row.isProcessed, isFalse);

      await (database.update(database.sounds)
            ..where((s) => s.id.equals(soundId)))
          .write(const db.SoundsCompanion(isProcessed: Value(true)));
      final updated = await database.select(database.sounds).getSingle();
      expect(updated.isProcessed, isTrue);

      await database.close();
    },
  );

  // `display_name` est NOT NULL depuis v40. Pour fabriquer une base d'AVANT, on
  // relâche la contrainte dans le schéma stocké (SQLite ne sait pas la retirer
  // autrement), puis on rouvre pour que `onUpgrade` tourne pour de vrai.
  Future<void> allowNullDisplayName(db.AppDatabase database) async {
    await database.customStatement('PRAGMA writable_schema = ON');
    await database.customStatement(
      "UPDATE sqlite_master SET sql = replace(sql, "
      "'\"display_name\" TEXT NOT NULL', '\"display_name\" TEXT NULL') "
      "WHERE type = 'table' AND name = 'sounds'",
    );
    await database.customStatement('PRAGMA writable_schema = OFF');
  }

  for (final fromVersion in [38, 39]) {
    test(
      'une base v$fromVersion passe display_name en NOT NULL : titre du '
      'fichier aux noms nuls/vides, noms personnalisés et liens conservés',
      () async {
        var database = db.AppDatabase.forTesting(NativeDatabase(file));
        await database.customStatement('SELECT 1');
        await allowNullDisplayName(database);
        await database.close();

        // Réouverture à la version courante : le schéma relâché est rechargé, sans
        // migration. Insertions SQL brutes (la Companion exige désormais un nom).
        database = db.AppDatabase.forTesting(NativeDatabase(file));
        Future<int> insert(String title, String? displayName) async {
          await database.customStatement(
            'INSERT INTO sounds (title, file_path, display_name) VALUES (?, ?, ?)',
            [title, '/cache/$title.wav', displayName],
          );
          final row = await database
              .customSelect(
                'SELECT id FROM sounds WHERE title = ?',
                variables: [Variable<String>(title)],
              )
              .getSingle();
          return row.read<int>('id');
        }

        final nullId = await insert('porte', null);
        final blankId = await insert('vent', '   ');
        final customId = await insert('pluie', 'Averse');

        // Données liées : la recréation de `sounds` ne doit pas les cascader.
        final boardId = await database
            .into(database.soundBoards)
            .insert(db.SoundBoardsCompanion.insert(name: 'Scène'));
        final padId = await database
            .into(database.pads)
            .insert(db.PadsCompanion.insert(boardId: boardId));
        await database
            .into(database.padSounds)
            .insert(
              db.PadSoundsCompanion.insert(padId: padId, soundId: customId),
            );

        await database.customStatement('PRAGMA user_version = $fromVersion');
        await database.close();

        database = db.AppDatabase.forTesting(NativeDatabase(file));
        Future<String> nameOf(int id) async => (await (database.select(
          database.sounds,
        )..where((s) => s.id.equals(id))).getSingle()).displayName;

        expect(await nameOf(nullId), 'porte');
        expect(await nameOf(blankId), 'vent');
        expect(await nameOf(customId), 'Averse');

        // Garde-fou de données : les clés étrangères sont désactivées dans l'app
        // (donc ici aussi), ce test ne prouve PAS la tenue sous FK activées.
        expect(
          await database.select(database.padSounds).get(),
          hasLength(1),
          reason: 'les liens pad_sounds doivent survivre à la recréation',
        );

        // La contrainte est bien posée, et l'index d'unicité recréé à la main
        // n'a pas été emporté avec l'ancienne table.
        await expectLater(
          database.customStatement(
            'INSERT INTO sounds (title, file_path, display_name) '
            "VALUES ('x', '/x.wav', NULL)",
          ),
          throwsA(anything),
        );
        final indexes = await database
            .customSelect(
              "SELECT name FROM sqlite_master "
              "WHERE type = 'index' AND name = 'idx_sounds_drive_file_id'",
            )
            .get();
        expect(indexes, hasLength(1));

        await database.close();
      },
    );
  }

  /// Crée la catégorie MUSIQUE telle que les versions 32 à 47 la portaient, avec
  /// ses tags, pour rejouer les migrations qui la traversent.
  Future<int> createLegacyMusicCategory(
    db.AppDatabase database,
    List<String> tags,
  ) async {
    await database.customStatement(
      'INSERT INTO tag_categories (name, color, sort_order, description) '
      "VALUES ('MUSIQUE', 4278238420, 6, '')",
    );
    final id =
        (await database
                .customSelect(
                  "SELECT id FROM tag_categories WHERE name = 'MUSIQUE'",
                )
                .getSingle())
            .read<int>('id');
    for (final tag in tags) {
      await database.customStatement(
        'INSERT INTO tags (category_id, name, normalized_name) VALUES (?, ?, ?)',
        [id, tag, tag.toLowerCase()],
      );
    }
    return id;
  }

  test("une base v40 reçoit les tags d'ambiance et voit MUSIQUE dissoute, "
      'sans perte', () async {
    var database = db.AppDatabase.forTesting(NativeDatabase(file));
    final categoriesBefore = await database
        .customSelect('SELECT COUNT(*) AS c FROM tag_categories')
        .getSingle();

    // Une base fraîche a déjà le catalogue ; on la ramène à l'état v40 : MUSIQUE
    // n'a que « Musique d'ambiance », et les tags d'ambiance ajoutés en v42 (et
    // leurs alias) disparaissent.
    const added =
        "('chant','instrumental','lent','rythme','joyeux','energique',"
        "'nostalgique','angoisse','calme')";
    await database.customStatement(
      'DELETE FROM tag_aliases WHERE tag_id IN '
      '(SELECT id FROM tags WHERE normalized_name IN $added)',
    );
    await database.customStatement(
      'DELETE FROM tags WHERE normalized_name IN $added',
    );
    await database.customStatement(
      "DELETE FROM tag_aliases WHERE normalized_alias IN "
      "('merveilleux','amour','sensuel')",
    );
    await createLegacyMusicCategory(database, ["Musique d'ambiance"]);
    await database.customStatement('PRAGMA user_version = 40');
    await database.close();

    database = db.AppDatabase.forTesting(NativeDatabase(file));
    Future<Set<String>> tagNames(String category) async {
      final rows = await database
          .customSelect(
            'SELECT t.name AS name FROM tags t JOIN tag_categories c '
            'ON c.id = t.category_id WHERE c.name = ?',
            variables: [Variable<String>(category)],
          )
          .get();
      return rows.map((r) => r.read<String>('name')).toSet();
    }

    // MUSIQUE n'existe plus (v48) : voix et tempo vivent dans EMOTION_STYLE.
    expect(await tagNames('MUSIQUE'), isEmpty);
    final emotion = await tagNames('EMOTION_STYLE');
    expect(
      emotion,
      containsAll([
        'Chant',
        'Instrumental',
        'Lent',
        'Rythmé',
        'Joyeux',
        'Énergique',
        'Nostalgique',
        'Angoisse',
        'Calme',
        'Magie',
        'Romantique',
      ]),
    );
    // Plus d'instrumentation : ce n'est pas ce qu'on cherche en musique.
    expect(emotion, isNot(contains('Piano')));

    // Même nombre de catégories qu'une base fraîche, tag d'origine conservé
    // (même id : les tags déjà posés sur des sons restent valides), et les
    // alias sont bien cherchables, y compris ceux ajoutés à un tag qui existait
    // déjà.
    final categoriesAfter = await database
        .customSelect('SELECT COUNT(*) AS c FROM tag_categories')
        .getSingle();
    expect(categoriesAfter.read<int>('c'), categoriesBefore.read<int>('c'));
    // « Musique d'ambiance » n'était posé sur aucun son : supprimé, avec ses alias.
    expect(
      await database
          .customSelect(
            "SELECT id FROM tags WHERE normalized_name = 'musique d''ambiance'",
          )
          .get(),
      isEmpty,
    );
    Future<String> aliasTarget(String alias) async {
      final row = await database
          .customSelect(
            'SELECT t.name AS name FROM tag_aliases a JOIN tags t '
            'ON t.id = a.tag_id WHERE a.normalized_alias = ?',
            variables: [Variable<String>(alias)],
          )
          .getSingle();
      return row.read<String>('name');
    }

    expect(await aliasTarget('voix'), 'Chant');
    expect(await aliasTarget('merveilleux'), 'Magie');
    expect(await aliasTarget('sensuel'), 'Romantique');

    await database.close();
  });

  test('la v42 retire les instruments de la v41 inutilisés et garde ceux '
      'posés sur un son', () async {
    var database = db.AppDatabase.forTesting(NativeDatabase(file));
    // État v41 : Piano et Cordes existent, avec un alias ; Cordes est posé sur
    // un son.
    final music = await createLegacyMusicCategory(database, []);
    for (final entry in {'Piano': 'pianiste', 'Cordes': 'violon'}.entries) {
      await database.customStatement(
        'INSERT INTO tags (category_id, name, normalized_name) '
        "VALUES ($music, '${entry.key}', '${entry.key.toLowerCase()}')",
      );
      await database.customStatement(
        'INSERT INTO tag_aliases (tag_id, alias, normalized_alias) VALUES '
        "((SELECT id FROM tags WHERE normalized_name = '${entry.key.toLowerCase()}'),"
        " '${entry.value}', '${entry.value}')",
      );
    }
    await database.customStatement(
      "INSERT INTO sounds (title, file_path, display_name) "
      "VALUES ('s', '/s.wav', 's')",
    );
    await database.customStatement(
      'INSERT INTO sound_tags (sound_id, tag_id) VALUES '
      "((SELECT id FROM sounds LIMIT 1), "
      "(SELECT id FROM tags WHERE normalized_name = 'cordes'))",
    );
    await database.customStatement('PRAGMA user_version = 41');
    await database.close();

    database = db.AppDatabase.forTesting(NativeDatabase(file));
    Future<int> count(String sql) async =>
        (await database.customSelect(sql).getSingle()).read<int>('c');

    expect(
      await count(
        "SELECT COUNT(*) AS c FROM tags WHERE normalized_name = 'piano'",
      ),
      0,
      reason: 'instrument inutilisé : retiré',
    );
    expect(
      await count(
        "SELECT COUNT(*) AS c FROM tag_aliases WHERE normalized_alias = 'pianiste'",
      ),
      0,
      reason: 'son alias part avec lui (pas de cascade, FK désactivées)',
    );
    expect(
      await count(
        "SELECT COUNT(*) AS c FROM tags WHERE normalized_name = 'cordes'",
      ),
      1,
      reason: 'posé sur un son : conservé',
    );
    expect(
      await count(
        "SELECT COUNT(*) AS c FROM tag_aliases WHERE normalized_alias = 'violon'",
      ),
      1,
    );
    expect(await count('SELECT COUNT(*) AS c FROM sound_tags'), 1);

    await database.close();
  });

  test('la v48 dissout MUSIQUE : tags déplacés avec leurs usages, doublons '
      'fusionnés, catalogue générique ajouté', () async {
    var database = db.AppDatabase.forTesting(NativeDatabase(file));
    Future<int> tagId(String normalized, {String? category}) async =>
        (await database
                .customSelect(
                  'SELECT t.id AS id FROM tags t JOIN tag_categories c '
                  'ON c.id = t.category_id WHERE t.normalized_name = ?'
                  "${category == null ? '' : " AND c.name = '$category'"}",
                  variables: [Variable<String>(normalized)],
                )
                .getSingle())
            .read<int>('id');

    // État v47 : MUSIQUE porte « Chant » (utilisé, avec un alias propre), un
    // « Lent » en doublon de celui d'EMOTION_STYLE (utilisé aussi), et
    // « Musique d'ambiance » ; les nouveaux tags n'existent pas encore.
    await database.customStatement(
      "DELETE FROM tag_aliases WHERE tag_id IN (SELECT id FROM tags "
      "WHERE normalized_name IN ('chant','lent'))",
    );
    await database.customStatement(
      "DELETE FROM tags WHERE normalized_name = 'chant'",
    );
    final music = await createLegacyMusicCategory(database, [
      'Chant',
      'Lent',
      "Musique d'ambiance",
    ]);
    final chantId = await tagId('chant');
    final lentLegacy = await tagId('lent', category: 'MUSIQUE');
    final lentTwin = await tagId('lent', category: 'EMOTION_STYLE');
    await database.customStatement(
      'INSERT INTO tag_aliases (tag_id, alias, normalized_alias) '
      "VALUES ($chantId, 'voix', 'voix'), ($lentLegacy, 'slow', 'slow')",
    );
    await database.customStatement(
      "INSERT INTO sounds (title, file_path, display_name) "
      "VALUES ('s', '/s.wav', 's')",
    );
    await database.customStatement(
      'INSERT INTO sound_tags (sound_id, tag_id) VALUES '
      '((SELECT id FROM sounds LIMIT 1), $chantId),'
      '((SELECT id FROM sounds LIMIT 1), $lentLegacy),'
      '((SELECT id FROM sounds LIMIT 1), '
      "(SELECT id FROM tags WHERE normalized_name = 'musique d''ambiance'))",
    );
    await database.customStatement(
      'INSERT INTO sound_auto_tags (sound_id, tag_id, score) VALUES '
      '((SELECT id FROM sounds LIMIT 1), $lentLegacy, 0.4)',
    );
    await database.customStatement(
      "DELETE FROM tag_aliases WHERE normalized_alias IN ('train','connu')",
    );
    await database.customStatement(
      "DELETE FROM tags WHERE normalized_name IN ('remix','kitsch','vehicule')",
    );
    await database.customStatement('PRAGMA user_version = 47');
    await database.close();

    database = db.AppDatabase.forTesting(NativeDatabase(file));
    Future<int> count(String sql) async =>
        (await database.customSelect(sql).getSingle()).read<int>('c');
    Future<String> aliasTarget(String alias) async =>
        (await database
                .customSelect(
                  'SELECT t.name AS name FROM tag_aliases a JOIN tags t '
                  'ON t.id = a.tag_id WHERE a.normalized_alias = ?',
                  variables: [Variable<String>(alias)],
                )
                .getSingle())
            .read<String>('name');

    expect(
      await count("SELECT COUNT(*) AS c FROM tag_categories WHERE id = $music"),
      0,
      reason: 'MUSIQUE n’existe plus',
    );
    // Déplacé sans changer d'id : l'usage sur le son reste valide.
    expect(await tagId('chant', category: 'EMOTION_STYLE'), chantId);
    expect(await aliasTarget('voix'), 'Chant');
    // Doublon fusionné sur le jumeau d'EMOTION_STYLE : usage, suggestion et
    // alias suivent, l'ancien tag disparaît.
    expect(
      await count(
        "SELECT COUNT(*) AS c FROM tags WHERE normalized_name = 'lent'",
      ),
      1,
    );
    expect(
      await count(
        'SELECT COUNT(*) AS c FROM sound_tags WHERE tag_id = $lentTwin',
      ),
      1,
    );
    expect(
      await count(
        'SELECT COUNT(*) AS c FROM sound_auto_tags WHERE tag_id = $lentTwin',
      ),
      1,
    );
    expect(await aliasTarget('slow'), 'Lent');
    expect(await count('SELECT COUNT(*) AS c FROM sound_tags'), 3);
    expect(
      await count(
        "SELECT COUNT(*) AS c FROM tags WHERE normalized_name = "
        "'musique d''ambiance'",
      ),
      1,
      reason: 'posé sur un son : conservé, dans EMOTION_STYLE',
    );
    // Catalogue générique : familles en tag, noms précis en alias.
    expect(await aliasTarget('train'), 'Véhicule');
    expect(await aliasTarget('connu'), 'Célèbre');
    expect(await aliasTarget('cheesy'), 'Kitsch');
    // Alias tirés des titres (analyse des mots) : anglais, fautes courantes.
    expect(await aliasTarget('tristesse'), 'Triste');
    expect(await aliasTarget('rain'), 'Pluie');
    expect(await aliasTarget('sonette'), 'Sonnerie');
    expect(await aliasTarget('cochon'), 'Animal');
    expect(await aliasTarget('ost'), 'BO');
    expect(await aliasTarget('cover'), 'Reprise');
    expect(await aliasTarget('soiree'), 'Fête');
    expect(await aliasTarget('thirties'), 'Années 30');
    expect(await aliasTarget('sixties'), 'Années 60');
    expect(await tagId('remix', category: 'EMOTION_STYLE'), isPositive);
    expect(
      await count(
        "SELECT COUNT(*) AS c FROM tags WHERE normalized_name = 'train'",
      ),
      0,
      reason: 'un nom précis est un alias, pas un tag',
    );

    await database.close();
  });

  test('la v48 absorbe les tags trop précis dans leur famille, sans perdre '
      'un usage', () async {
    var database = db.AppDatabase.forTesting(NativeDatabase(file));
    // État v47 : tags précis de l'ancien seed (une base neuve ne les crée plus).
    final objet =
        (await database
                .customSelect(
                  "SELECT id FROM tag_categories WHERE name = 'OBJET'",
                )
                .getSingle())
            .read<int>('id');
    for (final tag in ['Voiture', 'Chaise', 'Livre', 'Clés', 'Verre']) {
      await database.customStatement(
        'INSERT INTO tags (category_id, name, normalized_name) VALUES (?, ?, ?)',
        [objet, tag, tag.toLowerCase().replaceAll('é', 'e')],
      );
    }
    // Une base neuve porte déjà « bagnole » sur Véhicule : on rejoue l'état v47,
    // où l'alias appartenait à Voiture.
    await database.customStatement(
      "DELETE FROM tag_aliases WHERE normalized_alias = 'bagnole'",
    );
    await database.customStatement(
      'INSERT INTO tag_aliases (tag_id, alias, normalized_alias) VALUES '
      "((SELECT id FROM tags WHERE name = 'Voiture' AND category_id = $objet), "
      "'bagnole', 'bagnole')",
    );
    await database.customStatement(
      "INSERT INTO sounds (title, file_path, display_name) "
      "VALUES ('s', '/s.wav', 's')",
    );
    await database.customStatement(
      'INSERT INTO sound_tags (sound_id, tag_id) VALUES '
      "((SELECT id FROM sounds LIMIT 1), (SELECT id FROM tags WHERE name = 'Voiture')),"
      "((SELECT id FROM sounds LIMIT 1), (SELECT id FROM tags WHERE name = 'Clés'))",
    );
    await database.customStatement('PRAGMA user_version = 47');
    await database.close();

    database = db.AppDatabase.forTesting(NativeDatabase(file));
    Future<int> count(String sql) async =>
        (await database.customSelect(sql).getSingle()).read<int>('c');
    Future<int> tags(String name) =>
        count("SELECT COUNT(*) AS c FROM tags WHERE name = '$name'");

    // Fusionnés : plus de tag, l'usage et l'alias sont passés à la famille.
    expect(await tags('Voiture'), 0);
    expect(await tags('Chaise'), 0);
    final vehicle = await database
        .customSelect(
          'SELECT st.tag_id AS id FROM sound_tags st JOIN tags t '
          "ON t.id = st.tag_id WHERE t.name = 'Véhicule'",
        )
        .getSingle();
    expect(vehicle.read<int>('id'), isPositive, reason: 'usage reporté');
    final alias = await database
        .customSelect(
          'SELECT t.name AS name FROM tag_aliases a JOIN tags t ON '
          "t.id = a.tag_id WHERE a.normalized_alias = 'bagnole'",
        )
        .getSingle();
    expect(alias.read<String>('name'), 'Véhicule');
    // Doublon OBJET/MATIERE : il ne reste qu'un « Verre ».
    expect(await tags('Verre'), 1);
    // Sans famille : supprimé si inutilisé, conservé s'il est posé sur un son.
    expect(await tags('Livre'), 0);
    expect(await tags('Clés'), 1);
    expect(await count('SELECT COUNT(*) AS c FROM sound_tags'), 2);

    await database.close();
  });

  test('la v48 généralise les voix, déplacements et lieux trop précis : '
      'usages reportés, noms conservés comme alias', () async {
    var database = db.AppDatabase.forTesting(NativeDatabase(file));
    Future<int> count(String sql) async =>
        (await database.customSelect(sql).getSingle()).read<int>('c');
    Future<int> tags(String name) =>
        count("SELECT COUNT(*) AS c FROM tags WHERE name = '$name'");

    // Une base neuve ne crée plus les tags généralisés ni les gestes supprimés…
    for (final name in [
      'Applaudir',
      'Rire',
      'Marcher',
      'Frapper',
      'Exploser',
      'Casser',
      'Claquer',
      'Ouvrir',
      'Fermer',
      'Forêt',
      'Foule',
      'Verser',
      'Secouer',
      'Déchirer',
      'Frotter',
    ]) {
      expect(await tags(name), 0, reason: '$name n’est pas un tag');
    }
    // … et garde à part les actions et les matières.
    for (final name in [
      'Ouvrir/Fermer',
      'Lancer',
      'Actionner',
      'Gravier',
      'Glace',
      'Cuir',
    ]) {
      expect(await tags(name), 1, reason: '$name reste un tag');
    }
    expect(
      await count(
        "SELECT COUNT(*) AS c FROM tag_aliases a JOIN tags t ON t.id = a.tag_id "
        "WHERE t.name = 'Voix' AND a.normalized_alias = 'applaudissements'",
      ),
      1,
    );

    // État v47 : les anciens tags précis, avec leur alias propre et un usage.
    const old = [
      ('ACTION', 'Rire', 'rire'),
      ('ACTION', 'Marcher', 'pas'),
      ('ACTION', 'Exploser', 'explosion'),
      ('ACTION', 'Casser', 'briser'),
      ('ACTION', 'Ouvrir', null),
      ('ACTION', 'Fermer', null),
      ('AMBIANCE', 'Forêt', 'forêt'),
      ('AMBIANCE', 'Foule', null),
      // Supprimés : l'un posé sur un son (conservé), l'autre non.
      ('ACTION', 'Verser', 'renverser'),
      ('ACTION', 'Secouer', null),
    ];
    for (final (category, name, alias) in old) {
      final normalized = name.toLowerCase().replaceAll('ê', 'e');
      await database.customStatement(
        'INSERT INTO tags (category_id, name, normalized_name) VALUES '
        "((SELECT id FROM tag_categories WHERE name = '$category'), ?, ?)",
        [name, normalized],
      );
      if (alias != null) {
        final normalizedAlias = alias.replaceAll('ê', 'e');
        await database.customStatement(
          'DELETE FROM tag_aliases WHERE normalized_alias = ?',
          [normalizedAlias],
        );
        await database.customStatement(
          'INSERT INTO tag_aliases (tag_id, alias, normalized_alias) VALUES '
          '((SELECT id FROM tags WHERE name = ?), ?, ?)',
          [name, alias, normalizedAlias],
        );
      }
    }
    await database.customStatement(
      "INSERT INTO sounds (title, file_path, display_name) "
      "VALUES ('s', '/s.wav', 's')",
    );
    await database.customStatement(
      'INSERT INTO sound_tags (sound_id, tag_id) VALUES '
      "((SELECT id FROM sounds LIMIT 1), (SELECT id FROM tags WHERE name = 'Rire')),"
      "((SELECT id FROM sounds LIMIT 1), (SELECT id FROM tags WHERE name = 'Forêt')),"
      "((SELECT id FROM sounds LIMIT 1), (SELECT id FROM tags WHERE name = 'Verser'))",
    );
    await database.customStatement('PRAGMA user_version = 47');
    await database.close();

    database = db.AppDatabase.forTesting(NativeDatabase(file));
    for (final name in [
      'Rire',
      'Marcher',
      'Exploser',
      'Casser',
      'Ouvrir',
      'Fermer',
      'Forêt',
      'Foule',
      'Secouer',
    ]) {
      expect(await tags(name), 0, reason: '$name doit disparaître');
    }
    expect(await tags('Verser'), 1, reason: 'posé sur un son : conservé');
    final used = await database
        .customSelect(
          'SELECT t.name AS name FROM sound_tags st JOIN tags t '
          'ON t.id = st.tag_id ORDER BY t.name',
        )
        .get();
    expect(used.map((r) => r.read<String>('name')), [
      'Nature',
      'Verser',
      'Voix',
    ]);

    Future<String> aliasTarget(String alias) async =>
        (await database
                .customSelect(
                  'SELECT t.name AS name FROM tag_aliases a JOIN tags t ON '
                  't.id = a.tag_id WHERE a.normalized_alias = ?',
                  variables: [Variable<String>(alias)],
                )
                .getSingle())
            .read<String>('name');
    expect(await aliasTarget('rire'), 'Voix');
    expect(await aliasTarget('pas'), 'Déplacement');
    expect(await aliasTarget('explosion'), 'Impact');
    expect(await aliasTarget('briser'), 'Impact');
    expect(await aliasTarget('ouvrir'), 'Ouvrir/Fermer');
    expect(await aliasTarget('fermer'), 'Ouvrir/Fermer');
    expect(await aliasTarget('foret'), 'Nature');
    expect(await aliasTarget('foule'), 'Public');

    await database.close();
  });

  test('une installation neuve n’a pas de catégorie MUSIQUE', () async {
    final database = db.AppDatabase.forTesting(NativeDatabase(file));
    final rows = await database
        .customSelect('SELECT name FROM tag_categories ORDER BY sort_order')
        .get();
    expect(rows.map((r) => r.read<String>('name')), [
      'ACTION',
      'OBJET',
      'MATIERE',
      'AMBIANCE',
      'EMOTION_STYLE',
    ]);
    await database.close();
  });

  test(
    'une base v42 gagne auto_tagged_at, null pour les sons existants',
    () async {
      var database = db.AppDatabase.forTesting(NativeDatabase(file));
      await database.customStatement(
        "INSERT INTO sounds (title, file_path, display_name, is_processed) "
        "VALUES ('s', '/s.wav', 's', 1)",
      );
      await database.customStatement(
        'ALTER TABLE sounds DROP COLUMN auto_tagged_at',
      );
      await database.customStatement('PRAGMA user_version = 42');
      await database.close();

      database = db.AppDatabase.forTesting(NativeDatabase(file));
      final sound = await database.select(database.sounds).getSingle();
      expect(sound.title, 's', reason: 'les données doivent survivre');
      expect(sound.isProcessed, isTrue);
      // Null = jamais analysé : tous les sons existants deviennent candidats.
      expect(sound.autoTaggedAt, isNull);

      // La colonne doit être écrivable, et la date ressortir à la seconde près.
      final when = DateTime.utc(2026, 11, 4, 9, 30, 15);
      await (database.update(database.sounds)
            ..where((s) => s.id.equals(sound.id)))
          .write(db.SoundsCompanion(autoTaggedAt: Value(when)));
      final updated = await database.select(database.sounds).getSingle();
      expect(updated.autoTaggedAt?.toUtc(), when);

      await database.close();
    },
  );

  test(
    'une base v43 gagne auto_embedding, null pour les sons existants',
    () async {
      var database = db.AppDatabase.forTesting(NativeDatabase(file));
      await database.customStatement(
        "INSERT INTO sounds (title, file_path, display_name, auto_tagged_at) "
        "VALUES ('s', '/s.wav', 's', 1700000000)",
      );
      await database.customStatement(
        'ALTER TABLE sounds DROP COLUMN auto_embedding',
      );
      await database.customStatement('PRAGMA user_version = 43');
      await database.close();

      database = db.AppDatabase.forTesting(NativeDatabase(file));
      final sound = await database.select(database.sounds).getSingle();
      expect(sound.title, 's', reason: 'les données doivent survivre');
      expect(sound.autoTaggedAt, isNotNull, reason: 'la v43 est conservée');
      expect(sound.autoEmbedding, isNull);

      // Le BLOB doit faire l'aller-retour octet pour octet.
      final bytes = Uint8List.fromList(List.generate(2048, (i) => i % 251));
      await (database.update(database.sounds)
            ..where((s) => s.id.equals(sound.id)))
          .write(db.SoundsCompanion(autoEmbedding: Value(bytes)));
      final updated = await database.select(database.sounds).getSingle();
      expect(updated.autoEmbedding, orderedEquals(bytes));

      await database.close();
    },
  );

  test(
    'une base v44 gagne sound_auto_tags (avec score), vide, sans toucher aux '
    'tags',
    () async {
      var database = db.AppDatabase.forTesting(NativeDatabase(file));
      await database.customStatement(
        "INSERT INTO sounds (title, file_path, display_name) "
        "VALUES ('s', '/s.wav', 's')",
      );
      await database.customStatement(
        'INSERT INTO sound_tags (sound_id, tag_id) '
        'VALUES (1, (SELECT id FROM tags LIMIT 1))',
      );
      await database.customStatement('DROP TABLE sound_auto_tags');
      await database.customStatement('PRAGMA user_version = 44');
      await database.close();

      database = db.AppDatabase.forTesting(NativeDatabase(file));
      final auto = await database.select(database.soundAutoTags).get();
      expect(auto, isEmpty);
      expect(
        (await database.select(database.soundTags).get()),
        hasLength(1),
        reason: 'les tags de l’utilisateur ne bougent pas',
      );

      // Écriture avec son score, et clé primaire (soundId, tagId) unique.
      final tagId = (await database.select(database.tagItems).get()).first.id;
      await database
          .into(database.soundAutoTags)
          .insert(
            db.SoundAutoTagsCompanion.insert(
              soundId: 1,
              tagId: tagId,
              score: 0.5,
            ),
          );
      final row = await database.select(database.soundAutoTags).getSingle();
      expect(row.score, 0.5);
      expect(row.updatedAt, isNotNull);
      await expectLater(
        database
            .into(database.soundAutoTags)
            .insert(
              db.SoundAutoTagsCompanion.insert(
                soundId: 1,
                tagId: tagId,
                score: 0.1,
              ),
            ),
        throwsA(anything),
      );

      await database.close();
    },
  );

  test(
    'une base v45 recrée sound_auto_tags avec score et rouvre la décision des '
    'sons déjà empreints (sans toucher aux écartés)',
    () async {
      var database = db.AppDatabase.forTesting(NativeDatabase(file));
      await database.customStatement(
        "INSERT INTO sounds (title, file_path, display_name, auto_tagged_at, "
        "auto_embedding) VALUES ('analysé', '/a.wav', 'a', 1000, X'00')",
      );
      await database.customStatement(
        "INSERT INTO sounds (title, file_path, display_name, auto_tagged_at) "
        "VALUES ('écarté', '/b.wav', 'b', 1000)",
      );
      // Forme v45 : `hidden`, pas de `score`.
      await database.customStatement('DROP TABLE sound_auto_tags');
      await database.customStatement('''
        CREATE TABLE sound_auto_tags (
          sound_id INTEGER NOT NULL, tag_id INTEGER NOT NULL,
          hidden INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (sound_id, tag_id)
        )
      ''');
      await database.customStatement(
        'INSERT INTO sound_auto_tags (sound_id, tag_id) '
        'VALUES (1, (SELECT id FROM tags LIMIT 1))',
      );
      await database.customStatement('PRAGMA user_version = 45');
      await database.close();

      database = db.AppDatabase.forTesting(NativeDatabase(file));
      expect(await database.select(database.soundAutoTags).get(), isEmpty);
      final sounds = {
        for (final s in await database.select(database.sounds).get())
          s.title: s,
      };
      expect(sounds['analysé']!.autoTaggedAt, isNull, reason: 'à re-décider');
      expect(sounds['analysé']!.autoEmbedding, isNotNull, reason: 'gardée');
      expect(sounds['écarté']!.autoTaggedAt, isNotNull);

      final columns = await database
          .customSelect('PRAGMA table_info(sound_auto_tags)')
          .get();
      final names = columns.map((c) => c.read<String>('name')).toSet();
      expect(names, containsAll(['score', 'updated_at']));
      expect(names, isNot(contains('hidden')));

      await database.close();
    },
  );

  test('une base v46 perd board_sounds et ses lignes orphelines', () async {
    var database = db.AppDatabase.forTesting(NativeDatabase(file));
    await database.customStatement(
      "INSERT INTO sounds (title, file_path, display_name) "
      "VALUES ('a', '/a.wav', 'a')",
    );
    await database.customStatement(
      "INSERT INTO sound_boards (name) VALUES ('Scène')",
    );
    await database.customStatement('INSERT INTO pads (board_id) VALUES (1)');
    await database.customStatement(
      'INSERT INTO pad_sounds (pad_id, sound_id) VALUES (1, 1), (99, 1), (1, 98)',
    );
    // Pad dont la scène a disparu, avec son pad_sounds.
    await database.customStatement('INSERT INTO pads (board_id) VALUES (97)');
    await database.customStatement(
      'INSERT INTO pad_sounds (pad_id, sound_id) VALUES (2, 1)',
    );
    await database.customStatement(
      'INSERT INTO sound_tags (sound_id, tag_id) '
      'VALUES (1, (SELECT id FROM tags LIMIT 1)), (96, 1)',
    );
    // Scène et dossiers d'une bibliothèque déjà retirée.
    await database.customStatement(
      "INSERT INTO libraries (name, local_root_path) VALUES ('L', '/l')",
    );
    await database.customStatement(
      "UPDATE sound_boards SET library_id = 95 WHERE id = 1",
    );
    await database.customStatement(
      "INSERT INTO library_folders (library_id, drive_folder_id) "
      "VALUES (1, 'ok'), (95, 'mort')",
    );
    await database.customStatement(
      'INSERT INTO folder_memberships (library_id, folder_id) '
      'VALUES (1, 1), (95, 1), (1, 2)',
    );
    await database.customStatement(
      'CREATE TABLE board_sounds (board_id INTEGER, sound_id INTEGER)',
    );
    await database.customStatement('PRAGMA user_version = 46');
    await database.close();

    database = db.AppDatabase.forTesting(NativeDatabase(file));
    final tables = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    expect(
      tables.map((r) => r.read<String>('name')),
      isNot(contains('board_sounds')),
    );
    final pads = await database.select(database.pads).get();
    expect(pads.map((r) => r.id), [1]);
    final padSounds = await database.select(database.padSounds).get();
    expect(padSounds.map((r) => (r.padId, r.soundId)), [(1, 1)]);
    final soundTags = await database.select(database.soundTags).get();
    expect(soundTags.map((r) => r.soundId), [1]);
    final boards = await database.select(database.soundBoards).get();
    expect(boards.single.libraryId, isNull, reason: 'scène détachée, gardée');
    final folders = await database.select(database.libraryFolders).get();
    expect(folders.map((r) => r.driveFolderId), ['ok']);
    final memberships = await database.select(database.folderMemberships).get();
    expect(memberships.map((r) => (r.libraryId, r.folderId)), [(1, 1)]);

    await database.close();
  });

  test('la migration est idempotente : une base à jour rembobinée en v35 '
      'passe sans erreur', () async {
    var database = db.AppDatabase.forTesting(NativeDatabase(file));
    await database.customStatement('SELECT 1');
    // Colonne CONSERVÉE, version rembobinée : le cas d'un upgrade multi-versions
    // où une étape antérieure a déjà recréé les tables au schéma courant. Sans
    // le garde-fou `_columnExists`, `addColumn` échouerait ici.
    await database.customStatement('PRAGMA user_version = 35');
    await database.close();

    database = db.AppDatabase.forTesting(NativeDatabase(file));
    await expectLater(
      database.select(database.libraryFolders).get(),
      completion(isEmpty),
    );
    await database.close();
  });
}
