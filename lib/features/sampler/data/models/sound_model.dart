import 'package:drift/drift.dart' show Value;
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
      displayName: sound.displayName,
      filePath: sound.filePath,
      type: sound.type != null ? _mapSoundType(sound.type!) : null,
      colorValue: sound.color,
      volume: sound.volume,
      createdAt: sound.createdAt,
      libraryId: sound.libraryId,
      relativePath: sound.relativePath,
      driveFileId: sound.driveFileId,
      contentHash: sound.contentHash,
      isFavorite: sound.isFavorite,
      lastPlayedAt: sound.lastPlayedAt,
      waveform: sound.waveform,
      startOffsetMs: sound.startOffsetMs,
    );
  }

  /// Convertit une entité domain vers un Companion Drift pour insertion
  static db.SoundsCompanion toCompanion(domain.Sound sound) {
    return db.SoundsCompanion.insert(
      title: sound.title,
      displayName: Value(sound.displayName),
      filePath: sound.filePath,
      type: Value(sound.type != null ? _mapSoundTypeToDb(sound.type!) : null),
      color: Value(sound.colorValue),
      volume: Value(sound.volume),
      libraryId: Value(sound.libraryId),
      relativePath: Value(sound.relativePath),
      driveFileId: Value(sound.driveFileId),
      contentHash: Value(sound.contentHash),
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

