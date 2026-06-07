import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path/path.dart' as p;

/// Charge un fichier audio dans SoLoud via [loadMem].
///
/// Lit les octets côté Dart pour contourner les échecs d'ouverture C++ sur
/// Windows (chemins Unicode, accents, etc.) tout en conservant [LoadMode.memory].
Future<AudioSource> loadAudioSourceFromFile(File file) async {
  if (!await file.exists()) {
    throw StateError('Fichier audio introuvable : ${file.path}');
  }

  final path = p.normalize(file.absolute.path);
  final length = await file.length();
  if (length <= 0) {
    throw StateError('Fichier audio vide : $path');
  }

  final Uint8List bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    throw StateError('Fichier audio illisible : $path');
  }

  try {
    return await SoLoud.instance.loadMem(
      path,
      bytes,
      mode: LoadMode.memory,
    );
  } catch (e, stack) {
    debugPrint('Échec loadMem pour $path: $e\n$stack');
    rethrow;
  }
}

/// Erreurs SoLoud émises en double par le listener interne de flutter_soloud
/// (completeError sur le Future + throw dans le stream).
bool isBenignSoLoudLoadSideEffect(Object error) {
  return error is SoLoudFileNotFoundException ||
      error is SoLoudFileLoadFailedException;
}
