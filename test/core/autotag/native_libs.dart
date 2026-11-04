import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

/// Raison de sauter un test qui appelle le décodeur natif de flutter_soloud, ou
/// `null` s'il est utilisable.
///
/// `flutter test` ne construit pas la bibliothèque native du plugin : elle n'est
/// disponible qu'après un `flutter build windows` (ou `linux`). Sans elle, les
/// tests qui en dépendent sont sautés — c'est le cas en CI, qui ne la construit
/// pas.
String? soloudNativeSkipReason() {
  final dir = _builtPluginDir();
  if (Platform.isWindows && dir != null) {
    // Les dépendances (ogg.dll, vorbis.dll…) se résolvent par le PATH du processus.
    final name = 'PATH'.toNativeUtf16();
    final value = '$dir;${Platform.environment['PATH'] ?? ''}'.toNativeUtf16();
    try {
      win32.SetEnvironmentVariable(name, value);
    } finally {
      calloc.free(name);
      calloc.free(value);
    }
  }
  try {
    if (Platform.isWindows) {
      ffi.DynamicLibrary.open('flutter_soloud_plugin.dll');
    } else if (Platform.isLinux && dir != null) {
      ffi.DynamicLibrary.open('$dir/libflutter_soloud_plugin.so');
    } else if (Platform.isLinux) {
      ffi.DynamicLibrary.open('libflutter_soloud_plugin.so');
    } else {
      return 'bibliothèque native non chargeable hors application sur '
          '${Platform.operatingSystem}';
    }
    return null;
  } catch (_) {
    return 'bibliothèque native de flutter_soloud introuvable : lancer '
        '`flutter build windows --debug` (ou linux) une fois';
  }
}

String? _builtPluginDir() {
  final candidates = Platform.isWindows
      ? [
          for (final m in ['Debug', 'Release', 'Profile'])
            'build/windows/x64/runner/$m',
        ]
      : [
          for (final m in ['debug', 'release', 'profile'])
            'build/linux/x64/$m/bundle/lib',
        ];
  final lib = Platform.isWindows
      ? 'flutter_soloud_plugin.dll'
      : 'libflutter_soloud_plugin.so';
  for (final c in candidates) {
    if (File('$c/$lib').existsSync()) return Directory(c).absolute.path;
  }
  return null;
}

/// Chemin de la bibliothèque ONNX Runtime construite avec l'application, ou
/// `null` (tests sautés : voir [soloudNativeSkipReason] pour le principe).
String? onnxRuntimeLibraryPath() {
  final names = Platform.isWindows
      ? ['onnxruntime.dll']
      : ['libonnxruntime.so'];
  final dirs = Platform.isWindows
      ? [
          for (final m in ['Debug', 'Release', 'Profile'])
            'build/windows/x64/runner/$m',
        ]
      : [
          for (final m in ['debug', 'release', 'profile'])
            'build/linux/x64/$m/bundle/lib',
        ];
  for (final d in dirs) {
    for (final n in names) {
      final f = File('$d/$n');
      if (f.existsSync()) return f.absolute.path;
    }
  }
  return null;
}
