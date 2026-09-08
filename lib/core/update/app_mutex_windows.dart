import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Nom du mutex nommé Windows utilisé pour détecter l'instance en cours —
/// doit correspondre exactement à `AppMutex` dans `windows/installer/stage_cue.iss`.
const String kAppMutexName = 'StageCueAppMutex';

typedef _CreateMutexWNative = Pointer<Void> Function(
  Pointer<Void> lpMutexAttributes,
  Int32 bInitialOwner,
  Pointer<Utf16> lpName,
);
typedef _CreateMutexWDart = Pointer<Void> Function(
  Pointer<Void> lpMutexAttributes,
  int bInitialOwner,
  Pointer<Utf16> lpName,
);

/// `CreateMutexW` n'est pas exposé par le package `win32` (surface API
/// curatée depuis la v5) — appel direct à `kernel32.dll` via FFI.
final _createMutexW = DynamicLibrary.open('kernel32.dll')
    .lookupFunction<_CreateMutexWNative, _CreateMutexWDart>('CreateMutexW');

/// Ouvre (et maintient ouvert) un mutex nommé Windows pour toute la durée du
/// process : c'est le mécanisme standard qu'utilise Inno Setup (`AppMutex`)
/// pour repérer l'instance en cours au moment d'une mise à jour silencieuse,
/// la fermer proprement, puis la relancer après installation.
///
/// Le handle est volontairement **jamais libéré** — le tenir ouvert est ce
/// qui signale « en cours d'exécution » à Inno Setup ; il est récupéré par
/// Windows à la fin du process.
void holdAppMutexForUpdateDetection() {
  if (!Platform.isWindows) return;
  final namePtr = kAppMutexName.toNativeUtf16();
  try {
    _createMutexW(nullptr, 0, namePtr);
  } finally {
    calloc.free(namePtr);
  }
}
