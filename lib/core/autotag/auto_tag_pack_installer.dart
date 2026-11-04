import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../logging/app_log.dart';
import 'auto_tag_pack.dart';

/// Pack de modèles que cette version de l'app accepte : adresse, taille et
/// empreinte SHA-256 sont **dans le binaire**. L'app ne fait confiance à aucune
/// métadonnée du serveur — une release altérée ne passe pas (cf. 0026, dont
/// cette garde est plus stricte : l'empreinte attendue ne vient pas de GitHub).
///
/// Changer de modèle = publier un nouveau pack (`autotag-pack-N`) et une
/// nouvelle version de l'app qui pointe dessus ; `tool/autotag/README.md`
/// décrit la publication.
class AutoTagPackRelease {
  final String url;
  final String sha256;
  final int sizeBytes;
  const AutoTagPackRelease({
    required this.url,
    required this.sha256,
    required this.sizeBytes,
  });

  /// MuQ-MuLan (partie audio) int8, produit par `tool/autotag/`.
  static const AutoTagPackRelease current = AutoTagPackRelease(
    url:
        'https://github.com/armribdev/stage_cue/releases/download/autotag-pack-1/muq_audio_int8.onnx',
    sha256: '07551cf238af72eee52778f6b8e665efab9f2ad128b3602b635cf215260f6a2a',
    sizeBytes: 480184553,
  );
}

/// L'utilisateur a annulé le téléchargement.
class AutoTagPackCancelled implements Exception {
  const AutoTagPackCancelled();

  @override
  String toString() => 'Téléchargement annulé';
}

/// Drapeau d'annulation partagé avec un téléchargement en cours.
class AutoTagPackCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Télécharge le pack dans un `.part`, vérifie taille et SHA-256 au fil du flux,
/// puis le renomme : le fichier au nom final est toujours complet et conforme
/// (même discipline que 0006 et 0026).
class AutoTagPackInstaller {
  final AutoTagPack _pack;
  final AutoTagPackRelease _release;
  final http.Client? _httpClient;

  AutoTagPackInstaller(
    this._pack, {
    AutoTagPackRelease release = AutoTagPackRelease.current,
    http.Client? httpClient,
  }) : _release = release,
       _httpClient = httpClient;

  AutoTagPackRelease get release => _release;

  /// Installe le pack. Lève [AutoTagPackCancelled] si [cancel] est levé, une
  /// exception explicite sur toute autre erreur ; dans tous les cas le `.part`
  /// est supprimé et un pack déjà installé n'est jamais touché avant la fin.
  Future<void> install({
    void Function(int received, int total)? onProgress,
    AutoTagPackCancelToken? cancel,
  }) async {
    final root = await _pack.root();
    if (!await root.exists()) await root.create(recursive: true);
    final target = await _pack.modelFile();
    final part = File('${target.path}.part');
    if (await part.exists()) await part.delete();

    AppLog.info('Pack d\'analyse : téléchargement démarré (${_release.url}).');
    final ownedClient = _httpClient == null;
    final client = _httpClient ?? http.Client();
    try {
      final response = await client.send(
        http.Request('GET', Uri.parse(_release.url)),
      );
      if (response.statusCode != 200) {
        throw Exception('Téléchargement refusé (HTTP ${response.statusCode})');
      }

      final sink = part.openWrite();
      final digestSink = _DigestCapture();
      final hasher = sha256.startChunkedConversion(digestSink);
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          if (cancel?.isCancelled ?? false) throw const AutoTagPackCancelled();
          sink.add(chunk);
          hasher.add(chunk);
          received += chunk.length;
          if (received > _release.sizeBytes) {
            throw Exception('Le fichier reçu dépasse la taille attendue');
          }
          onProgress?.call(received, _release.sizeBytes);
        }
      } finally {
        hasher.close();
        await sink.close();
      }
      if (received != _release.sizeBytes) {
        throw Exception(
          'Taille inattendue ($received/${_release.sizeBytes} octets)',
        );
      }
      final actual = digestSink.value?.toString();
      if (actual != _release.sha256.toLowerCase()) {
        throw Exception(
          'Empreinte SHA-256 inattendue (attendue ${_release.sha256}, '
          'reçue $actual)',
        );
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      AppLog.info('Pack d\'analyse : installé et vérifié.');
    } on AutoTagPackCancelled {
      AppLog.info('Pack d\'analyse : téléchargement annulé.');
      rethrow;
    } catch (e) {
      AppLog.warn('Pack d\'analyse : téléchargement échoué — $e');
      rethrow;
    } finally {
      if (ownedClient) client.close();
      if (await part.exists()) await part.delete();
    }
  }

  /// Supprime le pack installé (et un éventuel `.part`). Les empreintes déjà
  /// calculées et les tags posés restent : seule l'analyse de nouveaux sons
  /// s'arrête.
  Future<void> remove() async {
    final root = await _pack.root();
    for (final name in [
      AutoTagPack.modelFileName,
      '${AutoTagPack.modelFileName}.part',
    ]) {
      final f = File(p.join(root.path, name));
      if (await f.exists()) await f.delete();
    }
    AppLog.info('Pack d\'analyse : supprimé.');
  }
}

class _DigestCapture implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
