import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import '../logging/app_log.dart';
import '../sync/library_sound_paths.dart';
import 'sounds.dart';

part 'database.g.dart';
part 'database_migrations.dart';
part 'database_tag_seed.dart';

@DriftDatabase(
  tables: [
    Libraries,
    LibraryFolders,
    FolderMemberships,
    Sounds,
    SoundBoards,
    WatchedPaths,
    Pads,
    PadSounds,
    TagCategories,
    TagItems,
    SoundTags,
    SoundAutoTags,
    TagAliases,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 47;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
        await _createGlobalIdentityIndexes();
        await _createBoardKeyIndex();
        await _seedDefaultTagsIfEmpty();
        await _ensureExtraTags();
      },
      onUpgrade: _withUpgradeLogging((m, from, to) => _upgrade(m, from, to)),
      beforeOpen: (details) async {
        await _applyJournalPragmas();
        _logSlowOpen();
        await _createCascadeTriggers();

        // Filet de sécurité pour les bases antérieures à v9 qui n'auraient pas
        // encore migré — sans effet sur les bases v10+ (table inexistante).
        if (details.versionBefore != null && details.versionBefore! < 9) {
          await _ensureBoardSoundSettingsTableExists();
        }
      },
    );
  }

  /// Émule les `onDelete: cascade` des tables dépendantes, que SQLite n'exécute
  /// pas sans `PRAGMA foreign_keys` (volontairement désactivé : un import de
  /// snapshot pose transitoirement des lignes qui référencent des absents).
  ///
  /// Un déclencheur couvre tous les chemins de suppression, y compris le SQL
  /// brut et la fusion de snapshots. Idempotent et rejoué à chaque ouverture :
  /// un `alterTable` futur qui recréerait une de ces tables emporterait ses
  /// déclencheurs, qui reviendraient ainsi à l'ouverture suivante.
  ///
  /// Retirer une bibliothèque rend ses scènes locales (`library_id` à null) au
  /// lieu de les supprimer.
  Future<void> _createCascadeTriggers() async {
    const cascades = <(String parent, String child, String column)>[
      ('sound_boards', 'pads', 'board_id'),
      ('pads', 'pad_sounds', 'pad_id'),
      ('sounds', 'pad_sounds', 'sound_id'),
      ('sounds', 'sound_tags', 'sound_id'),
      ('sounds', 'sound_auto_tags', 'sound_id'),
      ('tags', 'sound_tags', 'tag_id'),
      ('tags', 'sound_auto_tags', 'tag_id'),
      ('tags', 'tag_aliases', 'tag_id'),
      ('libraries', 'library_folders', 'library_id'),
      ('libraries', 'folder_memberships', 'library_id'),
      ('library_folders', 'folder_memberships', 'folder_id'),
    ];
    for (final (parent, child, column) in cascades) {
      await customStatement(
        'CREATE TRIGGER IF NOT EXISTS trg_${parent}_delete_$child '
        'AFTER DELETE ON $parent BEGIN '
        'DELETE FROM $child WHERE $column = OLD.id; END',
      );
    }
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS trg_libraries_detach_sound_boards '
      'AFTER DELETE ON libraries BEGIN '
      'UPDATE sound_boards SET library_id = NULL WHERE library_id = OLD.id; END',
    );
  }

  /// Supprime les lignes dont le parent n'existe plus (et détache les scènes
  /// d'une bibliothèque disparue), du haut vers le bas.
  Future<void> _purgeOrphans() async {
    const orphans = [
      'UPDATE sound_boards SET library_id = NULL '
          'WHERE library_id NOT IN (SELECT id FROM libraries)',
      'DELETE FROM library_folders '
          'WHERE library_id NOT IN (SELECT id FROM libraries)',
      'DELETE FROM folder_memberships '
          'WHERE library_id NOT IN (SELECT id FROM libraries) '
          'OR folder_id NOT IN (SELECT id FROM library_folders)',
      'DELETE FROM pads WHERE board_id NOT IN (SELECT id FROM sound_boards)',
      'DELETE FROM pad_sounds WHERE pad_id NOT IN (SELECT id FROM pads) '
          'OR sound_id NOT IN (SELECT id FROM sounds)',
      'DELETE FROM sound_tags WHERE sound_id NOT IN (SELECT id FROM sounds) '
          'OR tag_id NOT IN (SELECT id FROM tags)',
      'DELETE FROM sound_auto_tags '
          'WHERE sound_id NOT IN (SELECT id FROM sounds) '
          'OR tag_id NOT IN (SELECT id FROM tags)',
      'DELETE FROM tag_aliases WHERE tag_id NOT IN (SELECT id FROM tags)',
    ];
    for (final sql in orphans) {
      await customStatement(sql);
    }
  }

  /// Réglages de journalisation, appliqués à chaque ouverture.
  ///
  /// Par défaut SQLite tourne en `journal_mode = delete` + `synchronous = full` :
  /// chaque transaction crée puis supprime un journal de rollback et paie deux
  /// fsync. L'indexation Drive écrit des milliers de lignes par petites
  /// transactions implicites — c'est ce mode journal, et non le coût des
  /// requêtes, qui domine son temps d'exécution.
  ///
  /// - **WAL** : les écritures s'ajoutent en fin de journal au lieu de réécrire
  ///   les pages en place, et un lecteur ne bloque plus un écrivain (l'UI
  ///   continue de lire les boards pendant qu'une indexation écrit). Le réglage
  ///   est PERSISTANT (inscrit dans l'en-tête du fichier) : le rejouer à chaque
  ///   ouverture est sans effet et sans coût.
  /// - **synchronous = NORMAL** : compagnon usuel de WAL, à poser sur CHAQUE
  ///   connexion (contrairement au mode journal, il n'est pas persistant). La
  ///   base reste incorruptible en cas de crash ou de coupure ; seules les
  ///   toutes dernières transactions non encore checkpointées peuvent être
  ///   perdues.
  ///
  /// L'export de snapshot n'est pas concerné : il reconstruit une base neuve par
  /// `ATTACH` + `CREATE TABLE AS SELECT` (cf. `LibrarySnapshotStore`), il ne
  /// copie jamais le fichier brut — donc aucun risque de snapshot amputé du WAL.
  Future<void> _applyJournalPragmas() async {
    await customStatement('PRAGMA journal_mode = WAL');
    await customStatement('PRAGMA synchronous = NORMAL');
  }

  /// Index d'unicité GLOBALE de l'identité forte Drive : un fichier Drive
  /// (`drive_file_id`) et un dossier Drive (`drive_folder_id`) n'existent qu'une
  /// fois en base, toutes bibliothèques confondues. SQLite traite les NULL comme
  /// distincts → les sons locaux (sans `drive_file_id`) ne sont pas contraints.
  Future<void> _createGlobalIdentityIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_sounds_drive_file_id '
      'ON sounds (drive_file_id)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_library_folders_drive_folder_id '
      'ON library_folders (drive_folder_id)',
    );
  }

  /// Index d'unicité de l'identité portable des boards (`board_key`). SQLite
  /// traite les NULL comme distincts → les boards pas encore réconciliés (clé
  /// NULL) ne sont pas contraints.
  Future<void> _createBoardKeyIndex() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_sound_boards_board_key '
      'ON sound_boards (board_key)',
    );
  }
}

const String kDbFileName = 'db.sqlite';

/// Résout le fichier de la base principale.
///
/// La base vit dans le dossier de support de l'app (masqué de l'utilisateur,
/// hors du dossier Documents partagé/visible). Unique source de vérité pour
/// l'emplacement de la DB — ne pas reconstruire ce chemin ailleurs.
Future<File> resolveDatabaseFile() async {
  final dbFolder = await getApplicationSupportDirectory();
  return File(p.join(dbFolder.path, kDbFileName));
}

/// Chrono d'ouverture : démarre quand la connexion paresseuse s'ouvre, s'arrête
/// à la fin de `beforeOpen` (migration comprise).
Stopwatch? _openWatch;

/// Au-delà, une ouverture lente mérite une ligne : c'est le symptôme du blocage
/// à froid décrit par l'ADR 0013, ou d'une migration lourde.
const Duration _slowOpenThreshold = Duration(seconds: 2);

void _logSlowOpen() {
  final watch = _openWatch;
  _openWatch = null;
  if (watch == null) return;
  watch.stop();
  if (watch.elapsed >= _slowOpenThreshold) {
    AppLog.warn(
      'Ouverture de la base lente : ${watch.elapsedMilliseconds} ms '
      '(migration comprise).',
    );
  }
}

/// Journalise début, fin et durée d'une migration, et tout échec en `severe`
/// (l'exception est relancée : Drift doit toujours la voir).
OnUpgrade _withUpgradeLogging(OnUpgrade upgrade) {
  return (m, from, to) async {
    final watch = Stopwatch()..start();
    AppLog.info('Migration de la base : v$from → v$to.');
    try {
      await upgrade(m, from, to);
    } catch (e, stack) {
      AppLog.severe(
        'Migration de la base v$from → v$to échouée après '
        '${watch.elapsedMilliseconds} ms.',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
    AppLog.info(
      'Migration de la base v$from → v$to terminée '
      '(${watch.elapsedMilliseconds} ms).',
    );
  };
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    _openWatch = Stopwatch()..start();
    // Initialiser les bibliothèques natives SQLite sur Android/iOS
    if (Platform.isAndroid || Platform.isIOS) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }

    final file = await resolveDatabaseFile();
    // Ouverture sur l'isolate principal (et non `createInBackground`) : au cold
    // start Windows, le spawn de l'isolate de fond se bloque avant que la 1re
    // requête ne revienne (le natif sqlite3 n'y est pas prêt), laissant les
    // boards jamais chargés jusqu'à un hot restart. Les requêtes de cette app
    // sont légères → l'exécution sur l'isolate UI est sans impact perceptible.
    return NativeDatabase(file);
  });
}
