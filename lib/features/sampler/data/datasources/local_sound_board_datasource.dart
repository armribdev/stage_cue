import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/database.dart' as db;
import '../models/sound_board_model.dart';
import '../../domain/entities/sound_board.dart' as domain;

/// Source de données locale pour les soundboards
class LocalSoundBoardDataSource {
  final db.AppDatabase _database;

  LocalSoundBoardDataSource(this._database);

  /// Récupère toutes les soundboards
  Future<List<domain.SoundBoard>> getAllBoards() async {
    final boards = await (_database.select(
      _database.soundBoards,
    )..orderBy([(b) => OrderingTerm(expression: b.createdAt)])).get();
    return boards.map((b) => SoundBoardModel.toEntity(b)).toList();
  }

  /// Crée une soundboard. Génère une identité portable ([boardKey]) et un
  /// horodatage : indispensables à la fusion intelligente entre appareils.
  Future<int> createBoard(String name, {int? color, int? libraryId}) async {
    final now = DateTime.now();
    return await _database
        .into(_database.soundBoards)
        .insert(
          db.SoundBoardsCompanion.insert(
            name: name,
            color: Value(color),
            libraryId: Value(libraryId),
            createdAt: Value(now),
            boardKey: Value(const Uuid().v4()),
            updatedAt: Value(now),
          ),
        );
  }

  /// Renomme une soundboard (met à jour l'horodatage de fusion).
  Future<void> renameBoard(int boardId, String name) async {
    await (_database.update(
      _database.soundBoards,
    )..where((b) => b.id.equals(boardId))).write(
      db.SoundBoardsCompanion(
        name: Value(name),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Supprime une soundboard
  Future<void> deleteBoard(int boardId) async {
    await (_database.delete(
      _database.soundBoards,
    )..where((b) => b.id.equals(boardId))).go();
  }
}
