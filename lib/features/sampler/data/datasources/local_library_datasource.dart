import 'package:drift/drift.dart';
import '../../../../core/database/database.dart' as db;
import '../../domain/entities/library.dart' as domain;
import '../models/library_model.dart';

/// Source de données locale pour les bibliothèques portables (table Libraries).
class LocalLibraryDataSource {
  final db.AppDatabase _database;

  LocalLibraryDataSource(this._database);

  Future<List<domain.Library>> getAllLibraries() async {
    final rows = await _database.select(_database.libraries).get();
    return rows.map(LibraryModel.toEntity).toList();
  }

  /// Renvoie (crée si besoin) le nœud dossier d'identité GLOBALE `driveFolderId`.
  /// Un dossier Drive = un seul nœud, toutes bibliothèques confondues : deux
  /// bibliothèques qui couvrent le même dossier (liens imbriqués) convergent
  /// vers ce nœud unique au lieu de dupliquer ses fichiers.
  ///
  /// Façade à une entrée sur [ensureFolders] — une seule implémentation des
  /// règles (lookup global, chemin réécrit pour le seul propriétaire).
  Future<int> ensureFolder({
    required int libraryId,
    required String driveFolderId,
    required String relativePath,
  }) async {
    final resolved = await ensureFolders(
      libraryId: libraryId,
      folders: [(driveFolderId: driveFolderId, relativePath: relativePath)],
    );
    final id = resolved[driveFolderId];
    if (id == null) {
      throw StateError('Nœud dossier non résolu pour $driveFolderId');
    }
    return id;
  }

  Future<domain.Library?> getLibraryById(int id) async {
    final row = await (_database.select(
      _database.libraries,
    )..where((l) => l.id.equals(id))).getSingleOrNull();
    return row != null ? LibraryModel.toEntity(row) : null;
  }

  /// Insère une bibliothèque et retourne l'entité créée (avec son id).
  Future<domain.Library> insertLibrary({
    required String name,
    required String localRootPath,
    String? driveFolderId,
    String? drivePath,
    String? ownerEmail,
    String? sharedDriveId,
    bool autoDownload = false,
  }) async {
    final id = await _database.into(_database.libraries).insert(
          LibraryModel.toInsertCompanion(
            name: name,
            localRootPath: localRootPath,
            driveFolderId: driveFolderId,
            drivePath: drivePath,
            ownerEmail: ownerEmail,
            sharedDriveId: sharedDriveId,
            autoDownload: autoDownload,
          ),
        );
    final created = await getLibraryById(id);
    return created!;
  }

  /// Met à jour l'état de synchronisation après un push/pull réussi.
  Future<void> updateSyncState({
    required int id,
    String? driveFolderId,
    bool updateDriveFolderId = false,
    int? lastSyncedRevision,
    DateTime? lastSyncedAt,
  }) async {
    final companion = db.LibrariesCompanion(
      driveFolderId:
          updateDriveFolderId ? Value(driveFolderId) : const Value.absent(),
      lastSyncedRevision: lastSyncedRevision != null
          ? Value(lastSyncedRevision)
          : const Value.absent(),
      lastSyncedAt:
          lastSyncedAt != null ? Value(lastSyncedAt) : const Value.absent(),
    );
    await (_database.update(
      _database.libraries,
    )..where((l) => l.id.equals(id))).write(companion);
  }

  Future<void> setAutoDownload(int id, {required bool value}) async {
    await (_database.update(_database.libraries)..where((l) => l.id.equals(id)))
        .write(db.LibrariesCompanion(autoDownload: Value(value)));
  }

  Future<void> updateOwnerEmail(int id, String ownerEmail) async {
    await (_database.update(_database.libraries)..where((l) => l.id.equals(id)))
        .write(db.LibrariesCompanion(ownerEmail: Value(ownerEmail)));
  }

  Future<void> deleteLibrary(int id) async {
    await (_database.delete(
      _database.libraries,
    )..where((l) => l.id.equals(id))).go();
  }

  /// Nœuds dossier POSSÉDÉS par une bibliothèque (home). Base de la synchro :
  /// seul le propriétaire pousse/tire le `.stagecue` d'un nœud. Un dossier
  /// simplement VU (recouvrement) n'apparaît pas ici — cf. [getMemberFolderIds].
  Future<List<db.LibraryFolder>> getFoldersForLibrary(int libraryId) {
    return (_database.select(_database.libraryFolders)
          ..where((f) => f.libraryId.equals(libraryId)))
        .get();
  }

  /// Rattache une bibliothèque à un nœud dossier (VUE PARTAGÉE). Idempotent :
  /// appelé à chaque indexation d'un dossier, y compris pour le propriétaire.
  /// Une bibliothèque « invitée » (dont un lien recouvre le dossier) voit alors
  /// ses sons sans les dupliquer ni en changer le propriétaire.
  ///
  /// Façade à une entrée sur [ensureMemberships].
  Future<void> ensureMembership({
    required int libraryId,
    required int folderId,
  }) {
    return ensureMemberships(libraryId: libraryId, folderIds: [folderId]);
  }

  /// Variante en masse d'[ensureFolder] : résout (ou crée) tous les nœuds
  /// dossier d'un scan en UNE transaction, et retourne `driveFolderId -> id`.
  ///
  /// L'indexation appelait la version unitaire une fois par FICHIER : sur une
  /// bibliothèque de plusieurs milliers de sons, cela faisait autant d'allers-
  /// retours (et de transactions implicites) que de fichiers pour ne toucher
  /// qu'une poignée de dossiers. Mêmes règles que la version unitaire, dont le
  /// lookup GLOBAL et la réécriture du chemin réservée au propriétaire.
  Future<Map<String, int>> ensureFolders({
    required int libraryId,
    required List<({String driveFolderId, String relativePath})> folders,
  }) async {
    if (folders.isEmpty) return const {};

    // Dédoublonne : le scan fournit une entrée par fichier, pas par dossier.
    final wanted = <String, String>{};
    for (final folder in folders) {
      wanted.putIfAbsent(folder.driveFolderId, () => folder.relativePath);
    }

    return _database.transaction(() async {
      // Lookup GLOBAL — l'index d'unicité `drive_folder_id` l'est aussi : un
      // dossier possédé par une AUTRE bibliothèque doit être retrouvé, jamais
      // recréé (sinon violation de contrainte).
      final existing = await _database.select(_database.libraryFolders).get();
      final byDriveId = {for (final row in existing) row.driveFolderId: row};

      final resolved = <String, int>{};
      for (final entry in wanted.entries) {
        final row = byDriveId[entry.key];
        if (row == null) {
          resolved[entry.key] = await _database.into(_database.libraryFolders).insert(
                db.LibraryFoldersCompanion.insert(
                  libraryId: libraryId,
                  driveFolderId: entry.key,
                  relativePath: Value(entry.value),
                ),
              );
          continue;
        }
        // `relativePath` est relatif à la racine de la bibliothèque
        // PROPRIÉTAIRE : une bibliothèque invitée verrait le dossier sous un
        // autre préfixe et corromprait son cadre de chemins.
        if (row.libraryId == libraryId && row.relativePath != entry.value) {
          await (_database.update(_database.libraryFolders)
                ..where((f) => f.id.equals(row.id)))
              .write(db.LibraryFoldersCompanion(
            relativePath: Value(entry.value),
          ));
        }
        resolved[entry.key] = row.id;
      }
      return resolved;
    });
  }

  /// Variante en masse d'[ensureMembership] — un seul batch (donc une seule
  /// transaction) au lieu d'un `INSERT OR IGNORE` par fichier indexé.
  Future<void> ensureMemberships({
    required int libraryId,
    required Iterable<int> folderIds,
  }) async {
    final ids = folderIds.toSet();
    if (ids.isEmpty) return;
    await _database.batch((batch) {
      for (final folderId in ids) {
        batch.insert(
          _database.folderMemberships,
          db.FolderMembershipsCompanion.insert(
            libraryId: libraryId,
            folderId: folderId,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  /// Ids des nœuds dossier VISIBLES par une bibliothèque (possédés OU vus via un
  /// recouvrement de liens). Sert à scoper l'affichage et le recâblage des boards.
  Future<Set<int>> getMemberFolderIds(int libraryId) async {
    final rows = await (_database.select(_database.folderMemberships)
          ..where((m) => m.libraryId.equals(libraryId)))
        .get();
    return {for (final row in rows) row.folderId};
  }

  Future<db.LibraryFolder?> getFolderById(int id) {
    return (_database.select(_database.libraryFolders)
          ..where((f) => f.id.equals(id)))
        .getSingleOrNull();
  }

  /// Met à jour la révision de snapshot connue pour un nœud dossier.
  Future<void> updateFolderSyncState({
    required int id,
    required int lastSyncedRevision,
    DateTime? lastSyncedAt,
  }) async {
    await (_database.update(_database.libraryFolders)
          ..where((f) => f.id.equals(id)))
        .write(db.LibraryFoldersCompanion(
      lastSyncedRevision: Value(lastSyncedRevision),
      lastSyncedAt:
          lastSyncedAt != null ? Value(lastSyncedAt) : const Value.absent(),
    ));
  }
}
