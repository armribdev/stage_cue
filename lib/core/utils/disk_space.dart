import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

/// Octets disponibles sur le volume contenant [path], ou `null` si la mesure
/// est indisponible (plateforme non supportée, chemin invalide, échec de
/// l'appel système). `null` doit être traité comme « espace inconnu » — ne
/// jamais en déduire que le disque est plein.
Future<int?> availableDiskBytes(String path) async {
  if (!await Directory(path).exists()) return null;
  if (Platform.isWindows) return _availableDiskBytesWindows(path);
  if (Platform.isLinux || Platform.isMacOS) {
    return _availableDiskBytesPosix(path);
  }
  return null;
}

int? _availableDiskBytesWindows(String path) {
  final pathPtr = path.toNativeUtf16();
  final freeBytesAvailable = calloc<Uint64>();
  try {
    final ok = win32.GetDiskFreeSpaceEx(
      pathPtr,
      freeBytesAvailable,
      nullptr,
      nullptr,
    );
    if (ok == 0) return null;
    return freeBytesAvailable.value;
  } finally {
    calloc.free(pathPtr);
    calloc.free(freeBytesAvailable);
  }
}

Future<int?> _availableDiskBytesPosix(String path) async {
  try {
    final result = await Process.run('df', ['-Pk', path]);
    if (result.exitCode != 0) return null;
    final lines = (result.stdout as String).trim().split('\n');
    if (lines.length < 2) return null;
    final fields = lines.last.trim().split(RegExp(r'\s+'));
    if (fields.length < 4) return null;
    final availableKb = int.tryParse(fields[3]);
    if (availableKb == null) return null;
    return availableKb * 1024;
  } catch (_) {
    return null;
  }
}
