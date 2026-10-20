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
