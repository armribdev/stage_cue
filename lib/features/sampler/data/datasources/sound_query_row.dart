import 'package:drift/drift.dart';

import '../../domain/entities/sound.dart' as domain;

/// Colonnes de `sounds` (alias `s`) que lit [soundFromQueryRow] : de quoi
/// construire un `Sound` jouable, sans les colonnes d'indexation ni de tri.
const String kPlayableSoundColumns =
    's.id, s.title, s.display_name, s.file_path, s.type, '
    's.color, s.gain, s.created_at, '
    's.library_id, s.relative_path, s.content_hash, s.waveform';

/// Convertit une ligne issue d'un `SELECT` sur [kPlayableSoundColumns].
domain.Sound soundFromQueryRow(QueryRow row) {
  final typeValue = row.read<int?>('type');
  return domain.Sound(
    id: row.read<int>('id'),
    title: row.read<String>('title'),
    displayName: row.read<String>('display_name'),
    filePath: row.read<String>('file_path'),
    type: switch (typeValue) {
      0 => domain.SoundType.soundEffect,
      1 => domain.SoundType.music,
      2 => domain.SoundType.ambiance,
      _ => null,
    },
    colorValue: row.read<int?>('color'),
    gain: row.read<double>('gain'),
    createdAt: row.read<DateTime>('created_at'),
    libraryId: row.read<int?>('library_id'),
    relativePath: row.read<String?>('relative_path'),
    contentHash: row.read<String?>('content_hash'),
    waveform: row.read<Uint8List?>('waveform'),
  );
}
