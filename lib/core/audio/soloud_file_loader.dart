import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path/path.dart' as p;

import 'audio_file_validation.dart';
import 'audio_load_log.dart';

export 'audio_load_log.dart' show isBenignSoLoudLoadSideEffect;

/// File d'attente globale : flutter_soloud est instable sous Windows quand
/// plusieurs [loadMem] partent en parallèle (même fichier ou non).
Future<void>? _loadMemChain;

Future<T> _enqueueLoadMemTask<T>(Future<T> Function() task) {
  _loadMemChain ??= Future<void>.value();
  final run = _loadMemChain!.then((_) => task());
  _loadMemChain = run.then((_) {}, onError: (_) {});
  return run;
}

/// Formats natifs de miniaudio (SoLoud) — AAC/M4A exclus.
const Set<String> supportedAudioExtensions = {
  '.mp3', '.wav', '.ogg', '.opus', '.flac',
};

/// Charge un fichier audio dans SoLoud via [loadMem].
///
/// Lit les octets côté Dart pour contourner les échecs d'ouverture C++ sur
/// Windows (chemins Unicode, accents, etc.) tout en conservant [LoadMode.memory].
/// Ne propage jamais d'exception SoLoud brute — uniquement [StateError] ou
/// [UnsupportedAudioFormatException] pour les formats non décodables.
Future<AudioSource> loadAudioSourceFromFile(File file) async {
  if (!await file.exists()) {
    throw StateError('Fichier audio introuvable : ${file.path}');
  }

  final path = p.normalize(file.absolute.path);
  final ext = p.extension(path).toLowerCase();
  if (!supportedAudioExtensions.contains(ext)) {
    throw UnsupportedAudioFormatException(ext, path);
  }

  if (isKnownUnloadablePath(path)) {
    throw StateError('Fichier audio déjà signalé illisible : $path');
  }

  final length = await file.length();
  if (length < kMinimumValidAudioFileBytes) {
    markPathUnloadable(path);
    throw StateError(
      'Fichier audio trop petit ou cache tronqué ($length o, '
      'min $kMinimumValidAudioFileBytes o) : $path',
    );
  }

  final Uint8List bytes = await file.readAsBytes();
  if (bytes.length < kMinimumValidAudioFileBytes) {
    markPathUnloadable(path);
    throw StateError('Fichier audio illisible : $path');
  }
  if (!hasPlausibleAudioHeader(bytes)) {
    markPathUnloadable(path);
    throw StateError(
      'Fichier audio invalide (contenu non audio) : $path',
    );
  }

  return _enqueueLoadMemTask(() async {
    try {
      if (!SoLoud.instance.isInitialized) {
        throw StateError('Moteur audio non initialisé : $path');
      }
      return await SoLoud.instance.loadMem(
        path,
        bytes,
        mode: LoadMode.memory,
      );
    } on SoLoudCppException catch (e, stack) {
      markPathUnloadable(path);
      AudioLoadLog.loadMemFailed(path: path, error: e, stackTrace: stack);
      throw StateError(
        'Fichier audio illisible ou corrompu : $path ($e)',
      );
    } on StateError {
      rethrow;
    } catch (e, stack) {
      markPathUnloadable(path);
      AudioLoadLog.loadMemFailed(path: path, error: e, stackTrace: stack);
      throw StateError(
        'Fichier audio illisible ou corrompu : $path ($e)',
      );
    }
  });
}
