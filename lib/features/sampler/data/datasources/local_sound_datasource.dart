import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import '../../../../core/database/database.dart' as db;
import '../../../../core/database/sounds.dart' as db_sounds;
import 'package:path_provider/path_provider.dart';

import '../../../../core/platform/saf_directory_bridge.dart';
import '../../../../core/utils/file_utils.dart'
    show scanDirectoryForAudioFiles, computeQuickHash;
import '../../../../core/audio/soloud_file_loader.dart';
import '../../../../core/audio/audio_load_log.dart';
import '../../../../core/audio/audio_file_validation.dart';
import '../../../../core/audio/waveform_extractor.dart';
import '../models/sound_model.dart';
import '../models/indexing_progress.dart';
import '../../domain/entities/sound.dart' as domain;

// Point d'entrée stable : les sources de données voisines (plateaux, chemins
// surveillés, pads) vivent dans leur propre fichier mais restent importables
// via ce fichier.
export 'local_sound_board_datasource.dart';
export 'local_watched_path_datasource.dart';
export 'local_pad_datasource.dart';

part 'local_sound_crud.dart';
part 'local_sound_indexing.dart';
part 'local_sound_library_queries.dart';

/// Une ligne du scan Drive à refléter en base, telle que la produit
/// l'indexation. Le `folderId` est le nœud dossier local déjà résolu (cf.
/// `LocalLibraryDataSource.ensureFolders`).
class DriveIndexEntry {
  final String relativePath;
  final String localPath;
  final String? driveFileId;
  final String? driveMd5;
  final int? folderId;

  const DriveIndexEntry({
    required this.relativePath,
    required this.localPath,
    this.driveFileId,
    this.driveMd5,
    this.folderId,
  });
}

/// Source de données locale pour les sons (base de données)
class LocalSoundDataSource {
  final db.AppDatabase _database;
  static const Duration _musicThreshold = Duration(seconds: 30);

  LocalSoundDataSource(this._database);

  /// Résout les métadonnées d'un fichier audio local.
  /// Retourne `type: null` si le fichier est absent ou si le probe de durée échoue.
  /// La waveform est calculée pour tous les types (régie musique, éditeur du
  /// point d'entrée des bruitages et ambiances).
  Future<
    ({
      db_sounds.SoundType? type,
      String? contentHash,
      Uint8List? waveform,
      int? waveformProbeGeneration,
    })
  >
  _resolveMetadataForFile(File file) async {
    if (!await file.exists() || await file.length() <= 0) {
      return (
        type: null,
        contentHash: null,
        waveform: null,
        waveformProbeGeneration: null,
      );
    }
    final probeType = await _probeSoundTypeFromDuration(file);
    final contentHash = probeType != null ? await computeQuickHash(file) : null;
    final probe = probeType != null ? await extractWaveform(file.path) : null;
    return (
      type: probeType,
      contentHash: contentHash,
      waveform: probe?.waveformValue,
      waveformProbeGeneration: probe?.generationValue,
    );
  }

  /// Probe de type par durée SoLoud. Retourne null si le fichier est invalide
  /// ou si SoLoud ne peut pas le lire.
  Future<db_sounds.SoundType?> _probeSoundTypeFromDuration(File file) async {
    if (!await isPlausibleAudioFile(file)) {
      AudioLoadLog.metadataProbeFailed(
        path: file.path,
        error: StateError(
          'Fichier trop petit ou en-tête invalide '
          '(min $kMinimumValidAudioFileBytes o)',
        ),
      );
      return null;
    }

    final duration = await _readDurationViaSoLoud(file);
    if (duration == null) return null;
    return _typeFromDuration(duration);
  }

  db_sounds.SoundType _typeFromDuration(Duration duration) =>
      duration > _musicThreshold
      ? db_sounds.SoundType.music
      : db_sounds.SoundType.soundEffect;

  Future<Duration?> _readDurationViaSoLoud(File file) async {
    AudioSource? source;
    try {
      source = await loadAudioSourceFromFile(file);
      final duration = SoLoud.instance.getLength(source);
      if (duration <= Duration.zero) return null;
      return duration;
    } catch (e) {
      AudioLoadLog.metadataProbeFailed(path: file.path, error: e);
      return null;
    } finally {
      if (source != null) {
        try {
          SoLoud.instance.disposeSource(source);
        } catch (e) {
          debugPrint('Dispose SoLoud (probe durée) échoué: $e');
        }
      }
    }
  }
}
