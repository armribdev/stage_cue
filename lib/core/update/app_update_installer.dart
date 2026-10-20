import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_update_info.dart';
import 'update_log.dart';

/// Télécharge l'installeur d'une mise à jour et le lance en silencieux.
///
/// Ne ferme jamais l'app elle-même : l'installeur Inno Setup détecte
/// l'instance en cours via l'`AppMutex` maintenu ouvert par
/// [holdAppMutexForUpdateDetection] et gère fermeture + relance
/// (`/CLOSEAPPLICATIONS /RESTARTAPPLICATIONS`), voir `windows/installer/stage_cue.iss`.
class AppUpdateInstaller {
  AppUpdateInstaller({
    http.Client? httpClient,
    Future<Directory> Function()? getTemporaryDirectoryFn,
  }) : _httpClient = httpClient,
       _getTemporaryDirectory =
           getTemporaryDirectoryFn ?? getTemporaryDirectory;

  final http.Client? _httpClient;
  final Future<Directory> Function() _getTemporaryDirectory;

  /// Écrit en streaming dans un `.part` puis renomme atomiquement vers le nom
  /// final — un téléchargement interrompu ne laisse jamais un exe tronqué
  /// pris pour un installeur valide.
  Future<String> downloadInstaller(
    AppUpdateInfo info, {
    void Function(int received, int? total)? onProgress,
  }) async {
    UpdateLog.downloadStarted(info.downloadUrl);
    try {
      final tempDir = await _getTemporaryDirectory();
      final updateDir = Directory(p.join(tempDir.path, 'stagecue_update'));
      if (!await updateDir.exists()) {
        await updateDir.create(recursive: true);
      }
      final finalFile = File(p.join(updateDir.path, info.assetName));
      final partFile = File('${finalFile.path}.part');

      final ownedClient = _httpClient == null;
      final client = _httpClient ?? http.Client();
      try {
        final request = http.Request('GET', Uri.parse(info.downloadUrl));
        final response = await client.send(request);
        if (response.statusCode != 200) {
          throw Exception('Téléchargement échoué (${response.statusCode})');
        }

        final sink = partFile.openWrite();
        // Empreinte calculée au fil du flux : pas de seconde lecture du fichier.
        final digestSink = _DigestCapture();
        final hasher = sha256.startChunkedConversion(digestSink);
        var received = 0;
        await for (final chunk in response.stream) {
          sink.add(chunk);
          hasher.add(chunk);
          received += chunk.length;
          onProgress?.call(received, response.contentLength);
        }
        hasher.close();
        await sink.close();

        final expectedLength = response.contentLength;
        if (expectedLength != null && received != expectedLength) {
          await partFile.delete();
          throw Exception(
            'Taille inattendue ($received/$expectedLength octets)',
          );
        }

        // Le `.part` n'est jamais renommé tant que l'empreinte ne correspond
        // pas : un installeur altéré ou corrompu ne peut pas être lancé
        // (décision 0026).
        final actual = digestSink.value?.toString();
        if (actual != info.sha256.toLowerCase()) {
          await partFile.delete();
          throw Exception(
            'Empreinte SHA-256 de l\'installeur inattendue '
            '(attendue ${info.sha256}, reçue $actual)',
          );
        }
      } finally {
        if (ownedClient) client.close();
      }

      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await partFile.rename(finalFile.path);
      return finalFile.path;
    } catch (e) {
      UpdateLog.downloadFailed(e);
      rethrow;
    }
  }

  /// Lance l'installeur en `/VERYSILENT`, sans attendre sa fin — le process
  /// courant continue de tourner jusqu'à ce qu'Inno le ferme lui-même.
  Future<void> launchInstallerSilently(String installerPath) async {
    try {
      await Process.start(installerPath, const [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/CLOSEAPPLICATIONS',
        '/RESTARTAPPLICATIONS',
      ], mode: ProcessStartMode.detached);
      UpdateLog.installLaunched(installerPath);
    } catch (e) {
      UpdateLog.installLaunchFailed(e);
      rethrow;
    }
  }
}

/// Récupère le [Digest] émis à la fermeture d'une conversion `crypto` par blocs.
class _DigestCapture implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
