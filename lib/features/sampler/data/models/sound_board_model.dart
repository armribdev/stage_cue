import '../../domain/entities/sound_board.dart' as domain;
import '../../../../core/database/database.dart' as db;

/// Modèle de données pour SoundBoard (mapping entre Drift et entité domain)
class SoundBoardModel {
  /// Convertit un SoundBoard de Drift vers une entité domain
  static domain.SoundBoard toEntity(db.SoundBoard board) {
    return domain.SoundBoard(
      id: board.id,
      name: board.name,
      createdAt: board.createdAt,
    );
  }
}
