import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Pack de modèles de l'analyse automatique, installé hors du binaire
/// (ADR 0029). Tant qu'il est absent, l'analyse ne fait rien : l'installer est
/// le consentement de l'utilisateur.
class AutoTagPack {
  /// Nom du modèle d'ambiance (MuQ-MuLan, partie audio, int8 sur les MatMul).
  static const String modelFileName = 'muq_audio_int8.onnx';

  final Future<Directory> Function() _resolveRoot;

  /// Pack dans un dossier connu (tests).
  AutoTagPack(Directory root) : _resolveRoot = (() async => root);

  /// Pack sous le dossier de support de l'application, résolu à la demande
  /// (`path_provider` est asynchrone).
  AutoTagPack.inSupportDirectory()
    : _resolveRoot = (() async {
        final support = await getApplicationSupportDirectory();
        return Directory(p.join(support.path, 'autotag_pack'));
      });

  Future<Directory> root() => _resolveRoot();

  Future<File> modelFile() async =>
      File(p.join((await root()).path, modelFileName));

  /// Le téléchargement écrit en `.part` puis renomme : un fichier au nom final
  /// est donc toujours complet.
  Future<bool> isInstalled() async => (await modelFile()).exists();
}
