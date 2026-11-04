import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'onnx_session.dart';

/// Taille du vecteur latent de MuQ-MuLan.
const int kMuqLatentSize = 512;

/// Calcule l'empreinte audio d'un morceau avec MuQ-MuLan (partie audio, int8).
///
/// La session ONNX (≈ 480 Mo, 0,6 s de chargement) vit dans un isolate de
/// travail : l'inférence (≈ 0,35 s par clip de 10 s) bloque son thread, jamais
/// l'interface ni le déclenchement des pads (cf. [OnnxSession]).
class MuqAnalyzer {
  MuqAnalyzer._(this._isolate, this._requests);

  final Isolate _isolate;
  final SendPort _requests;
  bool _disposed = false;

  /// Charge le modèle [modelPath] dans un nouvel isolate.
  ///
  /// [intraOpThreads] borne les fils de calcul d'ONNX Runtime (≤ 0 : tous) :
  /// la machine reste utilisable pendant l'analyse. Lève
  /// [OnnxRuntimeException] si le modèle ne se charge pas.
  static Future<MuqAnalyzer> start(
    String modelPath, {
    int intraOpThreads = 0,
    String? libraryPath,
  }) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(
      _worker,
      _Init(ready.sendPort, modelPath, intraOpThreads, libraryPath),
      errorsAreFatal: true,
    );
    final reply = await ready.first;
    ready.close();
    if (reply is SendPort) return MuqAnalyzer._(isolate, reply);
    isolate.kill(priority: Isolate.immediate);
    throw OnnxRuntimeException(reply as String);
  }

  /// Moyenne des latents des [clips] (mono, 24 kHz, 10 s), **sans**
  /// renormalisation : c'est ce qui a été validé contre la référence Python
  /// (ADR 0029). Les clips sont traités l'un après l'autre.
  Future<Float32List> embed(List<Float32List> clips) async {
    if (_disposed) throw const OnnxRuntimeException('analyseur arrêté');
    if (clips.isEmpty) throw ArgumentError('Aucun clip à analyser');
    final reply = ReceivePort();
    _requests.send(
      _Embed(reply.sendPort, [
        for (final c in clips) TransferableTypedData.fromList([c]),
      ]),
    );
    final result = await reply.first;
    reply.close();
    if (result is TransferableTypedData) {
      return result.materialize().asFloat32List();
    }
    throw OnnxRuntimeException(result as String);
  }

  /// Arrête l'isolate et libère le modèle. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final done = ReceivePort();
    _requests.send(_Close(done.sendPort));
    await done.first.timeout(const Duration(seconds: 5), onTimeout: () => null);
    done.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

class _Init {
  final SendPort reply;
  final String modelPath;
  final int intraOpThreads;
  final String? libraryPath;
  const _Init(
    this.reply,
    this.modelPath,
    this.intraOpThreads,
    this.libraryPath,
  );
}

class _Embed {
  final SendPort reply;
  final List<TransferableTypedData> clips;
  const _Embed(this.reply, this.clips);
}

class _Close {
  final SendPort reply;
  const _Close(this.reply);
}

void _worker(_Init init) {
  final OnnxSession session;
  try {
    session = OnnxSession.open(
      init.modelPath,
      intraOpThreads: init.intraOpThreads,
      libraryPath: init.libraryPath,
    );
  } catch (e) {
    init.reply.send(e is OnnxRuntimeException ? e.message : e.toString());
    return;
  }
  final inbox = ReceivePort();
  init.reply.send(inbox.sendPort);
  inbox.listen((message) {
    if (message is _Close) {
      session.close();
      inbox.close();
      message.reply.send(null);
    } else if (message is _Embed) {
      try {
        final sum = Float64List(kMuqLatentSize);
        for (final t in message.clips) {
          final clip = t.materialize().asFloat32List();
          final latent = session.runFloat(clip, [1, clip.length]);
          if (latent.length != kMuqLatentSize) {
            throw OnnxRuntimeException(
              'latent de ${latent.length} valeurs au lieu de $kMuqLatentSize',
            );
          }
          for (var i = 0; i < kMuqLatentSize; i++) {
            sum[i] += latent[i];
          }
        }
        final n = message.clips.length;
        final mean = Float32List(kMuqLatentSize);
        for (var i = 0; i < kMuqLatentSize; i++) {
          mean[i] = sum[i] / n;
        }
        message.reply.send(TransferableTypedData.fromList([mean]));
      } catch (e) {
        message.reply.send(
          e is OnnxRuntimeException ? e.message : e.toString(),
        );
      }
    }
  });
}
