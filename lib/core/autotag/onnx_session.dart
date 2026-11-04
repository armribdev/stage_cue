import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Erreur renvoyée par ONNX Runtime (ou bibliothèque introuvable).
class OnnxRuntimeException implements Exception {
  final String message;
  const OnnxRuntimeException(this.message);

  @override
  String toString() => 'OnnxRuntimeException: $message';
}

typedef _Ptr = ffi.Pointer<ffi.Void>;
typedef _PtrOut = ffi.Pointer<ffi.Pointer<ffi.Void>>;

// Signatures de l'API C (`OrtStatus*` renvoyé : nul = succès).
typedef _CreateEnvN = _Ptr Function(ffi.Int32, ffi.Pointer<Utf8>, _PtrOut);
typedef _CreateEnvD = _Ptr Function(int, ffi.Pointer<Utf8>, _PtrOut);
typedef _OutOnlyN = _Ptr Function(_PtrOut);
typedef _OutOnlyD = _Ptr Function(_PtrOut);
typedef _SetIntNN = _Ptr Function(_Ptr, ffi.Int32);
typedef _SetIntD = _Ptr Function(_Ptr, int);
typedef _CreateSessionN = _Ptr Function(_Ptr, _Ptr, _Ptr, _PtrOut);
typedef _CreateSessionD = _Ptr Function(_Ptr, _Ptr, _Ptr, _PtrOut);
typedef _CreateMemInfoN = _Ptr Function(ffi.Int32, ffi.Int32, _PtrOut);
typedef _CreateMemInfoD = _Ptr Function(int, int, _PtrOut);
typedef _CreateTensorN =
    _Ptr Function(
      _Ptr,
      _Ptr,
      ffi.Size,
      ffi.Pointer<ffi.Int64>,
      ffi.Size,
      ffi.Int32,
      _PtrOut,
    );
typedef _CreateTensorD =
    _Ptr Function(_Ptr, _Ptr, int, ffi.Pointer<ffi.Int64>, int, int, _PtrOut);
typedef _RunN =
    _Ptr Function(
      _Ptr,
      _Ptr,
      ffi.Pointer<ffi.Pointer<Utf8>>,
      _PtrOut,
      ffi.Size,
      ffi.Pointer<ffi.Pointer<Utf8>>,
      ffi.Size,
      _PtrOut,
    );
typedef _RunD =
    _Ptr Function(
      _Ptr,
      _Ptr,
      ffi.Pointer<ffi.Pointer<Utf8>>,
      _PtrOut,
      int,
      ffi.Pointer<ffi.Pointer<Utf8>>,
      int,
      _PtrOut,
    );
typedef _InToOutN = _Ptr Function(_Ptr, _PtrOut);
typedef _InToOutD = _Ptr Function(_Ptr, _PtrOut);
typedef _ElementCountN = _Ptr Function(_Ptr, ffi.Pointer<ffi.Size>);
typedef _ElementCountD = _Ptr Function(_Ptr, ffi.Pointer<ffi.Size>);
typedef _ErrorMessageN = ffi.Pointer<Utf8> Function(_Ptr);
typedef _ErrorMessageD = ffi.Pointer<Utf8> Function(_Ptr);
typedef _ReleaseN = ffi.Void Function(_Ptr);
typedef _ReleaseD = void Function(_Ptr);

/// Fonctions de l'API C utilisées, liées une fois à l'ouverture.
///
/// Les numéros sont les rangs dans la table `OrtApi` de `onnxruntime_c_api.h`
/// (ORT 1.28). ONNX Runtime n'ajoute des entrées qu'à la fin de la table : on
/// demande une version d'API ancienne ([_apiVersion]) que toutes les
/// plateformes fournissent, et ces rangs y sont identiques.
final class _OrtFunctions {
  _OrtFunctions(_PtrOut api)
    : getErrorMessage = _at<_ErrorMessageN>(
        api,
        2,
      ).asFunction<_ErrorMessageD>(),
      createEnv = _at<_CreateEnvN>(api, 3).asFunction<_CreateEnvD>(),
      createSession = _at<_CreateSessionN>(
        api,
        7,
      ).asFunction<_CreateSessionD>(),
      run = _at<_RunN>(api, 9).asFunction<_RunD>(),
      createSessionOptions = _at<_OutOnlyN>(api, 10).asFunction<_OutOnlyD>(),
      setIntraOpNumThreads = _at<_SetIntNN>(api, 24).asFunction<_SetIntD>(),
      createTensorWithData = _at<_CreateTensorN>(
        api,
        49,
      ).asFunction<_CreateTensorD>(),
      getTensorMutableData = _at<_InToOutN>(api, 51).asFunction<_InToOutD>(),
      getTensorShapeElementCount = _at<_ElementCountN>(
        api,
        64,
      ).asFunction<_ElementCountD>(),
      getTensorTypeAndShape = _at<_InToOutN>(api, 65).asFunction<_InToOutD>(),
      createCpuMemoryInfo = _at<_CreateMemInfoN>(
        api,
        69,
      ).asFunction<_CreateMemInfoD>(),
      releaseEnv = _at<_ReleaseN>(api, 92).asFunction<_ReleaseD>(),
      releaseStatus = _at<_ReleaseN>(api, 93).asFunction<_ReleaseD>(),
      releaseMemoryInfo = _at<_ReleaseN>(api, 94).asFunction<_ReleaseD>(),
      releaseSession = _at<_ReleaseN>(api, 95).asFunction<_ReleaseD>(),
      releaseValue = _at<_ReleaseN>(api, 96).asFunction<_ReleaseD>(),
      releaseTensorTypeAndShapeInfo = _at<_ReleaseN>(
        api,
        99,
      ).asFunction<_ReleaseD>(),
      releaseSessionOptions = _at<_ReleaseN>(api, 100).asFunction<_ReleaseD>();

  static ffi.Pointer<ffi.NativeFunction<T>> _at<T extends Function>(
    _PtrOut api,
    int index,
  ) => ffi.Pointer<ffi.NativeFunction<T>>.fromAddress(api[index].address);

  final _ErrorMessageD getErrorMessage;
  final _CreateEnvD createEnv;
  final _CreateSessionD createSession;
  final _RunD run;
  final _OutOnlyD createSessionOptions;
  final _SetIntD setIntraOpNumThreads;
  final _CreateTensorD createTensorWithData;
  final _InToOutD getTensorMutableData;
  final _ElementCountD getTensorShapeElementCount;
  final _InToOutD getTensorTypeAndShape;
  final _CreateMemInfoD createCpuMemoryInfo;
  final _ReleaseD releaseEnv;
  final _ReleaseD releaseStatus;
  final _ReleaseD releaseMemoryInfo;
  final _ReleaseD releaseSession;
  final _ReleaseD releaseValue;
  final _ReleaseD releaseTensorTypeAndShapeInfo;
  final _ReleaseD releaseSessionOptions;

  /// Un `OrtStatus*` non nul est une erreur : on lit son message, on le libère
  /// et on le lève.
  void check(_Ptr status) {
    if (status == ffi.nullptr) return;
    final message = getErrorMessage(status).toDartString();
    releaseStatus(status);
    throw OnnxRuntimeException(message);
  }

  void release(_ReleaseD releaser, _Ptr object) {
    if (object != ffi.nullptr) releaser(object);
  }
}

/// Session ONNX Runtime appelée directement par FFI, **synchrone** : à utiliser
/// depuis un isolate de travail (`MuqAnalyzer`).
///
/// On n'utilise pas l'API Dart de `flutter_onnxruntime` : elle passe par un
/// canal de plateforme dont le gestionnaire exécute l'inférence sur le thread
/// de l'interface (Windows : threads plateforme et Dart fusionnés). Mesuré :
/// 410 ms de gel complet du thread Dart par clip de 10 s, 8 images rendues en
/// 2,4 s. Le paquet reste la source de la bibliothèque native, téléchargée et
/// embarquée à la compilation pour chaque plateforme (ADR 0029).
final class OnnxSession {
  OnnxSession._(
    this._f,
    this._env,
    this._session,
    this._memoryInfo,
    this._options,
  );

  /// Version d'API demandée (ORT 1.17).
  static const int _apiVersion = 17;
  static const int _loggingLevelError = 3;
  static const int _tensorFloat = 1;
  static const int _arenaAllocator = 1;
  static const int _memTypeDefault = 0;

  final _OrtFunctions _f;
  final _Ptr _env;
  final _Ptr _session;
  final _Ptr _memoryInfo;
  final _Ptr _options;
  bool _closed = false;

  /// Charge le modèle [modelPath]. [intraOpThreads] ≤ 0 : choix d'ONNX Runtime.
  /// [libraryPath] : bibliothèque à charger (tests) ; sinon celle de l'application.
  factory OnnxSession.open(
    String modelPath, {
    int intraOpThreads = 0,
    String? libraryPath,
  }) {
    final lib = _openLibrary(libraryPath);
    // OrtApiBase { const OrtApi* (*GetApi)(uint32_t); const char* (*GetVersionString)(void); }
    final getApiBase = lib.lookupFunction<_PtrOutFn, _PtrOutFn>(
      'OrtGetApiBase',
    );
    final getApi = getApiBase().value
        .cast<ffi.NativeFunction<_GetApiN>>()
        .asFunction<_GetApiD>();
    final api = getApi(_apiVersion);
    if (api == ffi.nullptr) {
      throw const OnnxRuntimeException(
        'bibliothèque ONNX Runtime trop ancienne pour l\'API demandée',
      );
    }
    final f = _OrtFunctions(api);

    final out = calloc<_Ptr>();
    final logId = 'stage_cue'.toNativeUtf8();
    final path = Platform.isWindows
        ? modelPath.toNativeUtf16().cast<ffi.Void>()
        : modelPath.toNativeUtf8().cast<ffi.Void>();
    _Ptr env = ffi.nullptr,
        options = ffi.nullptr,
        session = ffi.nullptr,
        memoryInfo = ffi.nullptr;
    try {
      f.check(f.createEnv(_loggingLevelError, logId, out));
      env = out.value;
      f.check(f.createSessionOptions(out));
      options = out.value;
      if (intraOpThreads > 0) {
        f.check(f.setIntraOpNumThreads(options, intraOpThreads));
      }
      f.check(f.createSession(env, path, options, out));
      session = out.value;
      f.check(f.createCpuMemoryInfo(_arenaAllocator, _memTypeDefault, out));
      memoryInfo = out.value;
      return OnnxSession._(f, env, session, memoryInfo, options);
    } catch (_) {
      f.release(f.releaseMemoryInfo, memoryInfo);
      f.release(f.releaseSession, session);
      f.release(f.releaseSessionOptions, options);
      f.release(f.releaseEnv, env);
      rethrow;
    } finally {
      calloc.free(out);
      calloc.free(logId);
      calloc.free(path);
    }
  }

  /// Exécute le modèle sur un tenseur flottant [input] de forme [shape] et
  /// renvoie la sortie [outputName] (copiée, indépendante de la session).
  Float32List runFloat(
    Float32List input,
    List<int> shape, {
    String inputName = 'wav',
    String outputName = 'latent',
  }) {
    if (_closed) throw const OnnxRuntimeException('session fermée');
    var count = 1;
    for (final d in shape) {
      count *= d;
    }
    if (count != input.length) {
      throw ArgumentError(
        'Forme $shape (= $count éléments) incompatible avec '
        '${input.length} valeurs',
      );
    }

    final f = _f;
    final data = calloc<ffi.Float>(input.length);
    final dims = calloc<ffi.Int64>(shape.length);
    final inNames = calloc<ffi.Pointer<Utf8>>();
    final outNames = calloc<ffi.Pointer<Utf8>>();
    final inValues = calloc<_Ptr>();
    final outValues = calloc<_Ptr>();
    final scratch = calloc<_Ptr>();
    final elementCount = calloc<ffi.Size>();
    final inName = inputName.toNativeUtf8();
    final outName = outputName.toNativeUtf8();
    _Ptr inTensor = ffi.nullptr;
    try {
      data.asTypedList(input.length).setAll(0, input);
      for (var i = 0; i < shape.length; i++) {
        dims[i] = shape[i];
      }
      f.check(
        f.createTensorWithData(
          _memoryInfo,
          data.cast(),
          input.length * 4,
          dims,
          shape.length,
          _tensorFloat,
          inValues,
        ),
      );
      inTensor = inValues.value;
      inNames.value = inName;
      outNames.value = outName;
      outValues.value = ffi.nullptr;

      f.check(
        f.run(
          _session,
          ffi.nullptr,
          inNames,
          inValues,
          1,
          outNames,
          1,
          outValues,
        ),
      );
      final outTensor = outValues.value;
      try {
        f.check(f.getTensorTypeAndShape(outTensor, scratch));
        final info = scratch.value;
        try {
          f.check(f.getTensorShapeElementCount(info, elementCount));
        } finally {
          f.release(f.releaseTensorTypeAndShapeInfo, info);
        }
        f.check(f.getTensorMutableData(outTensor, scratch));
        return Float32List.fromList(
          scratch.value.cast<ffi.Float>().asTypedList(elementCount.value),
        );
      } finally {
        f.release(f.releaseValue, outTensor);
      }
    } finally {
      f.release(f.releaseValue, inTensor);
      calloc.free(data);
      calloc.free(dims);
      calloc.free(inNames);
      calloc.free(outNames);
      calloc.free(inValues);
      calloc.free(outValues);
      calloc.free(scratch);
      calloc.free(elementCount);
      calloc.free(inName);
      calloc.free(outName);
    }
  }

  /// Libère la session et ses ressources natives. Idempotent.
  void close() {
    if (_closed) return;
    _closed = true;
    _f.release(_f.releaseMemoryInfo, _memoryInfo);
    _f.release(_f.releaseSession, _session);
    _f.release(_f.releaseSessionOptions, _options);
    _f.release(_f.releaseEnv, _env);
  }

  static ffi.DynamicLibrary _openLibrary(String? explicit) {
    final candidates = explicit != null ? [explicit] : _defaultLibraryPaths();
    Object? last;
    for (final c in candidates) {
      try {
        return ffi.DynamicLibrary.open(c);
      } catch (e) {
        last = e;
      }
    }
    throw OnnxRuntimeException('ONNX Runtime introuvable ($last)');
  }

  static List<String> _defaultLibraryPaths() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isWindows) return ['$exeDir\\onnxruntime.dll'];
    if (Platform.isLinux) {
      return ['$exeDir/lib/libonnxruntime.so', 'libonnxruntime.so'];
    }
    return ['libonnxruntime.dylib'];
  }
}

typedef _PtrOutFn = _PtrOut Function();
typedef _GetApiN = _PtrOut Function(ffi.Uint32);
typedef _GetApiD = _PtrOut Function(int);
