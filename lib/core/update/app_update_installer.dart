import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_update_info.dart';
import 'update_log.dart';

/// Télécharge l'installeur d'une mise à jour et le lance en silencieux.
///
/// Ne ferme pas l'app lui-même : c'est `runUpdateFlow` qui la quitte une fois
/// l'installeur lancé, et l'installeur Inno Setup la relance (ADR 0037, voir
/// `windows/installer/stage_cue.iss`).
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
      final updateDir = Directory(p.join(tempDir.path, updateDirName));
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

  /// Lance l'installeur en `/VERYSILENT`, sans attendre sa fin. Il survit à
  /// l'app, que l'appelant ferme ensuite (voir `runUpdateFlow`) : Inno ne pose
  /// aucune question et relance l'app lui-même (`[Run]`, `stage_cue.iss`).
  ///
  /// `/LOG` : en silencieux, l'installeur n'affiche rien, même quand il
  /// abandonne — ce fichier est la seule trace de ce qu'il a fait, relue au
  /// lancement suivant par [reportPreviousInstall].
  Future<void> launchInstallerSilently(String installerPath) async {
    try {
      await Process.start(installerPath, [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/CLOSEAPPLICATIONS',
        '/LOG=${p.join(p.dirname(installerPath), installLogName)}',
      ], mode: ProcessStartMode.detached);
      UpdateLog.installLaunched(installerPath);
    } catch (e) {
      UpdateLog.installLaunchFailed(e);
      rethrow;
    }
  }

  /// Journalise l'issue de la dernière installation lancée par l'app, puis
  /// efface le dossier de mise à jour (installeur compris, ~25 Mo).
  ///
  /// Sans effet s'il n'y a pas de journal d'installeur, ou si celui-ci n'est pas
  /// clos : l'app relancée par l'installeur démarre avant qu'il ait terminé,
  /// elle repassera au lancement suivant. Ne lève jamais.
  Future<void> reportPreviousInstall() async {
    try {
      final tempDir = await _getTemporaryDirectory();
      final updateDir = Directory(p.join(tempDir.path, updateDirName));
      final logFile = File(p.join(updateDir.path, installLogName));
      if (!await logFile.exists()) return;

      final lines = (await logFile.readAsLines())
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (!lines.any((line) => line.endsWith('Log closed.'))) return;

      if (lines.any(
        (line) => line.endsWith('Installation process succeeded.'),
      )) {
        UpdateLog.previousInstallSucceeded();
      } else {
        // Les dernières lignes portent la cause (message ignoré par défaut,
        // exception levée…) ; le début n'est que l'en-tête de session.
        UpdateLog.previousInstallFailed(
          lines.reversed.take(8).toList().reversed.join(' | '),
        );
      }
      await updateDir.delete(recursive: true);
    } catch (e) {
      UpdateLog.warn('Lecture du journal de l\'installeur impossible — $e');
    }
  }

  /// Dossier temporaire de l'installeur téléchargé et de son journal.
  static const updateDirName = 'stagecue_update';
  static const installLogName = 'install.log';
}

/// Récupère le [Digest] émis à la fermeture d'une conversion `crypto` par blocs.
class _DigestCapture implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
