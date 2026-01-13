import '../../domain/entities/sound.dart' as domain;
import '../../../../core/database/sounds.dart' as db_types;
import '../../../../core/database/database.dart' as db;

/// Modèle de données pour Sound (mapping entre Drift et entité domain)
class SoundModel {
  /// Convertit un Sound de Drift vers une entité domain
  static domain.Sound toEntity(db.Sound sound) {
    return domain.Sound(
      id: sound.id,
      title: sound.title,
      filePath: sound.filePath,
      type: _mapSoundType(sound.type),
      createdAt: sound.createdAt,
    );
  }

  /// Convertit une entité domain vers un Companion Drift pour insertion
  static db.SoundsCompanion toCompanion(domain.Sound sound) {
    return db.SoundsCompanion.insert(
      title: sound.title,
      filePath: sound.filePath,
      type: _mapSoundTypeToDb(sound.type),
    );
  }

  static domain.SoundType _mapSoundType(db_types.SoundType dbType) {
    return switch (dbType) {
      db_types.SoundType.soundEffect => domain.SoundType.soundEffect,
      db_types.SoundType.music => domain.SoundType.music,
      db_types.SoundType.ambiance => domain.SoundType.ambiance,
    };
  }

  static db_types.SoundType _mapSoundTypeToDb(domain.SoundType type) {
    return switch (type) {
      domain.SoundType.soundEffect => db_types.SoundType.soundEffect,
      domain.SoundType.music => db_types.SoundType.music,
      domain.SoundType.ambiance => db_types.SoundType.ambiance,
    };
  }
}

