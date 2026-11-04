import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Pack de modèles de l'analyse automatique, installé hors du binaire
/// (ADR 0029). Tant qu'il est absent, l'analyse ne fait rien : l'installer est
/// le consentement de l'utilisateur.
class AutoTagPack {
  /// Nom du modèle d'ambiance (MuQ-MuLan, partie audio, int8 sur les MatMul).
  static const String modelFileName = 'muq_audio_int8.onnx';

  final Directory root;
  const AutoTagPack(this.root);

  /// Dossier du pack sous le dossier de support de l'application.
  static Future<AutoTagPack> inSupportDirectory() async {
    final support = await getApplicationSupportDirectory();
    return AutoTagPack(Directory(p.join(support.path, 'autotag_pack')));
  }

  File get modelFile => File(p.join(root.path, modelFileName));

  /// Le téléchargement écrit en `.part` puis renomme : un fichier au nom final
  /// est donc toujours complet.
  Future<bool> get isInstalled => modelFile.exists();
}
