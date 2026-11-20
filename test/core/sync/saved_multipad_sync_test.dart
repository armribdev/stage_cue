// Synchro des multipads enregistrés (décision 0051) : ils voyagent dans le
// snapshot racine avec les boards, leurs sons par driveFileId (ids locaux
// décalés d'un appareil à l'autre), fusion par `multipad_key` « dernier
// écrivain gagnant », jamais de purge — sauf la suppression, qui voyage en
// pierre tombale.

import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:stage_cue/core/database/database.dart' as db;
import 'package:stage_cue/core/sync/library_snapshot_store.dart';
import 'package:stage_cue/features/sampler/data/datasources/local_sound_datasource.dart';

/// Un appareil : base en mémoire, une bibliothèque, trois sons `a`, `b`, `c`
/// (mêmes `driveFileId` partout). [shift] sons bidons les précèdent : les ids
/// locaux diffèrent donc d'un appareil à l'autre.
class _Device {
  final db.AppDatabase database;
  final int libraryId;
  final Map<String, int> soundIds;
  late final LocalSavedMultipadDataSource saved = LocalSavedMultipadDataSource(
    database,
  );
  late final LibrarySnapshotStore store = LibrarySnapshotStore(database);

  _Device(this.database, this.libraryId, this.soundIds);

  static Future<_Device> open(String root, {int shift = 0}) async {
    final database = db.AppDatabase.forTesting(NativeDatabase.memory());
    final lib = await database
        .into(database.libraries)
        .insert(db.LibrariesCompanion.insert(name: 'L', localRootPath: root));
    final folder = await database
        .into(database.libraryFolders)
        .insert(
          db.LibraryFoldersCompanion.insert(
            libraryId: lib,
            driveFolderId: 'F',
            relativePath: const Value(''),
          ),
        );
    for (var i = 0; i < shift; i++) {
      await database
          .into(database.sounds)
          .insert(
            db.SoundsCompanion.insert(
              title: 'bidon$i',
              displayName: 'bidon$i',
              filePath: '$root/bidon$i.mp3',
            ),
          );
    }
    final ids = <String, int>{};
    for (final name in ['a', 'b', 'c']) {
      ids[name] = await database
          .into(database.sounds)
          .insert(
            db.SoundsCompanion.insert(
              title: name,
              displayName: name,
              filePath: '$root/$name.mp3',
              libraryId: Value(lib),
              relativePath: Value('$name.mp3'),
              driveFileId: Value('DF$name'),
              folderId: Value(folder),
            ),
          );
    }
    return _Device(database, lib, ids);
  }

  Future<List<db.SavedMultipad>> models() =>
      database.select(database.savedMultipads).get();

  Future<db.SavedMultipad> modelNamed(String name) => (database.select(
    database.savedMultipads,
  )..where((m) => m.name.equals(name))).getSingle();

  /// Noms des sons d'un modèle, dans l'ordre.
  Future<List<String>> soundNames(int multipadId) async {
    final rows = await database
        .customSelect(
          'SELECT s.title FROM saved_multipad_sounds m '
          'INNER JOIN sounds s ON s.id = m.sound_id '
          'WHERE m.multipad_id = ? ORDER BY m.sort_order',
          variables: [Variable<int>(multipadId)],
        )
        .get();
    return [for (final r in rows) r.read<String>('title')];
  }

  /// Date de modification forcée (secondes, la précision de Drift).
  Future<void> setUpdatedAt(int multipadId, int seconds) =>
      database.customStatement(
        'UPDATE saved_multipads SET updated_at = ? WHERE id = ?',
        [seconds, multipadId],
      );

  Future<int> create(
    String name,
    List<String> sounds, {
    int? colorValue,
    bool synced = true,
  }) => saved.create(
    name: name,
    soundIds: [for (final s in sounds) soundIds[s]!],
    colorValue: colorValue,
    libraryId: synced ? libraryId : null,
  );

  Future<void> close() => database.close();
}

void main() {
  // Deux appareils = deux bases : voulu, pas une course sur un même exécuteur.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory tempDir;
  late _Device a;
  late _Device b;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('stage_cue_mp_sync_');
    a = await _Device.open('/A');
    b = await _Device.open('/B', shift: 3);
  });

  tearDown(() async {
    await a.close();
    await b.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// A publie son snapshot racine, B le fusionne.
  Future<String> push(_Device from, _Device to) async {
    final path = p.join(
      tempDir.path,
      'root-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    await from.store.exportLibrarySnapshot(from.libraryId, path);
    await to.store.mergeLibrarySnapshot(to.libraryId, path);
    return path;
  }

  test('un modèle voyage avec ses sons dans l\'ordre, recâblés par '
      'driveFileId malgré des ids locaux décalés', () async {
    await a.create('Porte', ['c', 'a', 'b'], colorValue: 0xFF123456);
    expect(a.soundIds['a'], isNot(b.soundIds['a']));

    await push(a, b);

    final model = await b.modelNamed('Porte');
    expect(model.color, 0xFF123456);
    expect(model.libraryId, b.libraryId);
    expect(await b.soundNames(model.id), ['c', 'a', 'b']);
    expect(
      model.multipadKey,
      (await a.modelNamed('Porte')).multipadKey,
      reason: 'même identité portable des deux côtés',
    );
  });

  test('un modèle local (sans bibliothèque) ne voyage pas', () async {
    await a.create('Privé', ['a'], synced: false);
    await a.create('Partagé', ['b']);

    await push(a, b);

    expect((await b.models()).map((m) => m.name), ['Partagé']);
  });

  test(
    'un modèle dont aucun son n\'existe ici est ignoré, sans erreur',
    () async {
      final onlyOnA = await a.database
          .into(a.database.sounds)
          .insert(
            db.SoundsCompanion.insert(
              title: 'exclusif',
              displayName: 'exclusif',
              filePath: '/A/x.mp3',
              libraryId: Value(a.libraryId),
              relativePath: const Value('x.mp3'),
              driveFileId: const Value('DFx'),
            ),
          );
      await a.saved.create(
        name: 'Orphelin',
        soundIds: [onlyOnA],
        libraryId: a.libraryId,
      );

      await push(a, b);

      expect(await b.models(), isEmpty);
    },
  );

  test('plus récent côté distant : nom, couleur et sons remplacés', () async {
    final id = await a.create('Porte', ['a', 'b']);
    await push(a, b);

    await a.saved.update(
      id,
      name: 'Porte qui grince',
      soundIds: [a.soundIds['c']!, a.soundIds['a']!],
    );
    await a.setUpdatedAt(id, 4102444800); // 2100 : sans équivoque plus récent
    await push(a, b);

    expect((await b.models()), hasLength(1));
    final model = (await b.models()).single;
    expect(model.name, 'Porte qui grince');
    expect(await b.soundNames(model.id), ['c', 'a']);
  });

  test('plus récent côté local : le local est conservé', () async {
    final id = await a.create('Porte', ['a']);
    await push(a, b);
    final local = await b.modelNamed('Porte');
    await b.saved.update(local.id, name: 'Version locale');
    await b.setUpdatedAt(local.id, 4102444800);
    await a.setUpdatedAt(id, 1000);

    await push(a, b);

    expect((await b.models()).single.name, 'Version locale');
  });

  test('union : un modèle seulement local reste après une fusion', () async {
    await a.create('Sur A', ['a']);
    await b.create('Sur B', ['b']);

    await push(a, b);

    expect((await b.models()).map((m) => m.name).toSet(), {'Sur A', 'Sur B'});
  });

  test('un snapshot d\'un appareil plus ancien (sans multipads) laisse les '
      'modèles locaux intacts', () async {
    await b.create('Sur B', ['b']);
    final path = p.join(tempDir.path, 'old.db');
    await a.store.exportLibrarySnapshot(a.libraryId, path);
    final escaped = path.replaceAll('\\', '/');
    await a.database.customStatement("ATTACH DATABASE '$escaped' AS old");
    await a.database.customStatement('DROP TABLE old.saved_multipads');
    await a.database.customStatement('DROP TABLE old.saved_multipad_sounds');
    await a.database.customStatement(
      'DROP TABLE old.saved_multipad_tombstones',
    );
    await a.database.customStatement('DETACH DATABASE old');

    await b.store.mergeLibrarySnapshot(b.libraryId, path);

    expect((await b.models()).map((m) => m.name), ['Sur B']);
  });

  test('un modèle local sans propriétaire est rattaché à la bibliothèque qui '
      'publie sa clé', () async {
    await a.create('Porte', ['a']);
    await push(a, b);
    final onB = await b.modelNamed('Porte');
    await b.database.customStatement(
      'UPDATE saved_multipads SET library_id = NULL WHERE id = ${onB.id}',
    );

    await push(a, b);

    expect((await b.modelNamed('Porte')).libraryId, b.libraryId);
  });

  group('suppression', () {
    test('supprimer un modèle synchronisé laisse une trace publiée, qui '
        'supprime le modèle de l\'autre appareil', () async {
      final id = await a.create('Porte', ['a']);
      await push(a, b);
      expect(await b.models(), hasLength(1));
      // Dans le passé : la suppression doit être postérieure à la dernière
      // modification sans dépendre de la finesse de l'horloge.
      await a.setUpdatedAt(id, 1000);
      await b.setUpdatedAt((await b.models()).single.id, 1000);

      await a.saved.delete(id);
      final tombstones = await a.database
          .select(a.database.savedMultipadTombstones)
          .get();
      expect(tombstones, hasLength(1));
      expect(tombstones.single.libraryId, a.libraryId);

      await push(a, b);

      expect(await b.models(), isEmpty);
      expect(
        await b.database.select(b.database.savedMultipadTombstones).get(),
        hasLength(1),
        reason: 'B garde la trace pour la republier à un troisième appareil',
      );
    });

    test(
      'un modèle supprimé ne revient pas depuis un appareil en retard',
      () async {
        final id = await a.create('Porte', ['a']);
        await push(a, b);
        await a.setUpdatedAt(id, 1000);
        await b.setUpdatedAt((await b.models()).single.id, 1000);

        await a.saved.delete(id);
        // B, pas encore à jour, republie son ancien snapshot vers A.
        await push(b, a);

        expect(await a.models(), isEmpty, reason: 'pas de résurrection');
      },
    );

    test('modifié après la suppression, le modèle survit à la trace', () async {
      final id = await a.create('Porte', ['a']);
      await push(a, b);
      final onB = (await b.models()).single;
      await a.setUpdatedAt(id, 1000);
      await a.saved.delete(id);
      // B modifie le modèle après la suppression (date très postérieure).
      await b.saved.update(onB.id, name: 'Porte modifiée');
      await b.setUpdatedAt(onB.id, 4102444800);

      await push(a, b);

      expect((await b.models()).single.name, 'Porte modifiée');
    });

    test('republié plus récent que la trace, le modèle revient et la trace '
        'tombe', () async {
      final id = await a.create('Porte', ['a']);
      await push(a, b);
      final onB = (await b.models()).single;
      await b.setUpdatedAt(onB.id, 1000);
      await b.saved.delete(onB.id);
      expect(
        await b.database.select(b.database.savedMultipadTombstones).get(),
        hasLength(1),
      );
      // A modifie après la suppression de B.
      await a.saved.update(id, name: 'Réécrit');
      await a.setUpdatedAt(id, 4102444800);

      await push(a, b);

      expect((await b.models()).single.name, 'Réécrit');
      expect(
        await b.database.select(b.database.savedMultipadTombstones).get(),
        isEmpty,
      );
    });

    test('un modèle local supprimé ne laisse aucune trace', () async {
      final id = await a.create('Privé', ['a'], synced: false);

      await a.saved.delete(id);

      expect(
        await a.database.select(a.database.savedMultipadTombstones).get(),
        isEmpty,
      );
    });
  });
}
