import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/database.dart' as db;

/// Abstraction d'export/import d'un snapshot de la base, isolant la mécanique
/// SQLite du service de synchronisation (et la rendant mockable en test).
abstract class SnapshotStore {
  /// Version de schéma courante (inscrite dans le manifest).
  int get schemaVersion;

  /// Exporte un snapshot cohérent de la base vers [targetPath].
  /// Retourne la taille du fichier produit (octets).
  Future<int> exportSnapshot(String targetPath);

  /// Met un snapshot téléchargé en attente d'application. Le swap réel se fait
  /// au prochain démarrage, avant l'ouverture de la base (cf. _openConnection),
  /// pour ne jamais remplacer un `.sqlite` ouvert.
  Future<void> stageForImport(String sourcePath);
}

/// Implémentation adossée à la base Drift de l'application.
class DriftSnapshotStore implements SnapshotStore {
  final db.AppDatabase _database;

  DriftSnapshotStore(this._database);

  @override
  int get schemaVersion => _database.schemaVersion;

  @override
  Future<int> exportSnapshot(String targetPath) async {
    final target = File(targetPath);
    if (await target.exists()) {
      await target.delete();
    }
    await target.parent.create(recursive: true);
    // VACUUM INTO produit une copie compacte et cohérente même base ouverte.
    final escaped = targetPath.replaceAll("'", "''");
    await _database.customStatement("VACUUM INTO '$escaped'");
    return target.length();
  }

  @override
  Future<void> stageForImport(String sourcePath) async {
    final docs = await getApplicationDocumentsDirectory();
    final pendingPath = p.join(docs.path, db.kPendingDbFileName);
    await File(sourcePath).copy(pendingPath);
  }
}
