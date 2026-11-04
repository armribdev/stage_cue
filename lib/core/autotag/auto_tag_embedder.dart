import 'dart:io';
import 'dart:typed_data';

import 'muq_analyzer.dart';
import 'pcm_decoder.dart';

/// Calcule l'empreinte audio d'un fichier. Lève `AudioNotAnalyzable` quand le
/// fichier ne peut pas être analysé (format, durée, silence…).
///
/// Abstraction minimale pour que `AutoTagService` se teste sans le modèle de
/// 480 Mo : la seule implémentation de production est [MuqEmbedder].
abstract interface class AutoTagEmbedder {
  Future<Float32List> embed(File file);

  Future<void> close();
}

/// [AutoTagEmbedder] de production : décodeur PCM puis MuQ-MuLan.
class MuqEmbedder implements AutoTagEmbedder {
  MuqEmbedder._(this._analyzer);

  final MuqAnalyzer _analyzer;

  /// Charge le modèle [modelPath] (≈ 0,6 s, ≈ 480 Mo de mémoire jusqu'à
  /// [close]). Les fils de calcul d'ONNX Runtime sont bornés à la moitié des
  /// cœurs : l'analyse dure des minutes en tâche de fond, la machine (et le
  /// son) doit rester fluide.
  static Future<MuqEmbedder> open(String modelPath) async {
    final threads = (Platform.numberOfProcessors ~/ 2).clamp(1, 8);
    return MuqEmbedder._(
      await MuqAnalyzer.start(modelPath, intraOpThreads: threads),
    );
  }

  @override
  Future<Float32List> embed(File file) async =>
      _analyzer.embed(await decodeAnalysisClips(file));

  @override
  Future<void> close() => _analyzer.dispose();
}

/// Sérialisation de l'empreinte en base : flottants 32 bits petit-boutistes
/// (toutes les plateformes cibles le sont).
Uint8List embeddingToBytes(Float32List embedding) => Uint8List.fromList(
  embedding.buffer.asUint8List(
    embedding.offsetInBytes,
    embedding.lengthInBytes,
  ),
);

/// Relit une empreinte, ou `null` si [bytes] n'a pas la taille attendue
/// (donnée illisible : ignorée par les statistiques et les décisions).
Float32List? embeddingFromBytes(Uint8List bytes) {
  if (bytes.length != kMuqLatentSize * 4) return null;
  // Copie alignée : le BLOB lu de SQLite n'est pas forcément aligné sur 4 octets.
  return Float32List.fromList(Uint8List.fromList(bytes).buffer.asFloat32List());
}
