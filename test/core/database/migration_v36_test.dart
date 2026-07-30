// Vérifie le chemin d'UPGRADE vers v36 (colonne `manifest_probe_token`).
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

  test('une base v35 gagne manifest_probe_token sans perdre ses données',
      () async {
    // 1. Base au schéma courant, avec une bibliothèque et un nœud dossier.
    var database = db.AppDatabase.forTesting(NativeDatabase(file));
    final libraryId = await database.into(database.libraries).insert(
          db.LibrariesCompanion.insert(name: 'Lib', localRootPath: '/cache'),
        );
    await database.into(database.libraryFolders).insert(
          db.LibraryFoldersCompanion.insert(
            libraryId: libraryId,
            driveFolderId: 'drive-1',
            relativePath: const Value('Portes'),
            lastSyncedRevision: const Value(7),
          ),
        );

    // 2. Rétrograde à l'état v35 : colonne retirée, user_version rembobinée.
    await database
        .customStatement('ALTER TABLE library_folders '
            'DROP COLUMN manifest_probe_token');
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
    await (database.update(database.libraryFolders)
          ..where((f) => f.id.equals(folders.single.id)))
        .write(const db.LibraryFoldersCompanion(
      manifestProbeToken: Value(probeToken),
    ));
    final updated = await database.select(database.libraryFolders).getSingle();
    expect(updated.manifestProbeToken, probeToken);

    await database.close();
  });

  test('la migration est idempotente : une base déjà v36 rembobinée en v35 '
      'passe sans erreur', () async {
    var database = db.AppDatabase.forTesting(NativeDatabase(file));
    await database.customStatement('SELECT 1');
    // Colonne CONSERVÉE, version rembobinée : le cas d'un upgrade multi-versions
    // où une étape antérieure a déjà recréé les tables au schéma courant. Sans
    // le garde-fou `_columnExists`, `addColumn` échouerait ici.
    await database.customStatement('PRAGMA user_version = 35');
    await database.close();

    database = db.AppDatabase.forTesting(NativeDatabase(file));
    await expectLater(database.select(database.libraryFolders).get(),
        completion(isEmpty));
    await database.close();
  });
}
