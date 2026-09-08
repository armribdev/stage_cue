import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_update_info.dart';
import 'update_log.dart';

/// Interroge la dernière GitHub Release de Stage Cue et la compare à la
/// version en cours d'exécution.
class AppUpdateChecker {
  static const _repoSlug = 'armribdev/stage_cue';
  static const _latestReleaseUrl =
      'https://api.github.com/repos/$_repoSlug/releases/latest';

  /// `null` si déjà à jour, si le check échoue silencieusement en amont (voir
  /// l'appelant), ou si la release n'a pas d'asset installeur exploitable.
  /// Les erreurs réseau/format remontent à l'appelant — c'est lui qui décide
  /// de logguer et d'afficher (ou pas) un message.
  Future<AppUpdateInfo?> checkForUpdate({required String currentVersion}) async {
    UpdateLog.checkStarted();
    final response = await http.get(
      Uri.parse(_latestReleaseUrl),
      headers: const {'Accept': 'application/vnd.github+json'},
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Réponse inattendue de GitHub (${response.statusCode})',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final tagName = body['tag_name'] as String?;
    if (tagName == null || tagName.isEmpty) {
      throw Exception('Release GitHub sans tag_name');
    }
    final remoteVersion =
        tagName.startsWith('v') ? tagName.substring(1) : tagName;

    if (!_isNewer(remoteVersion, currentVersion)) {
      UpdateLog.upToDate(currentVersion);
      return null;
    }

    final assets = (body['assets'] as List?) ?? const [];
    Map<String, dynamic>? installerAsset;
    for (final asset in assets) {
      final map = asset as Map<String, dynamic>;
      final name = map['name'] as String?;
      if (name != null && name.toLowerCase().endsWith('.exe')) {
        installerAsset = map;
        break;
      }
    }
    if (installerAsset == null) {
      UpdateLog.warn(
        'Version $remoteVersion disponible mais aucun asset .exe trouvé',
      );
      return null;
    }

    final assetName = installerAsset['name'] as String;
    final downloadUrl = installerAsset['browser_download_url'] as String;
    UpdateLog.newVersionFound(version: remoteVersion, assetName: assetName);
    return AppUpdateInfo(
      version: remoteVersion,
      downloadUrl: downloadUrl,
      assetName: assetName,
    );
  }

  /// Comparateur semver minimal (major.minor.patch) — suffisant pour des tags
  /// `vX.Y.Z` ; un composant non numérique retombe sur 0 plutôt que d'échouer.
  bool _isNewer(String remote, String current) {
    final remoteParts = _parseVersion(remote);
    final currentParts = _parseVersion(current);
    for (var i = 0; i < 3; i++) {
      if (remoteParts[i] != currentParts[i]) {
        return remoteParts[i] > currentParts[i];
      }
    }
    return false;
  }

  List<int> _parseVersion(String version) {
    final parts = version.split('.');
    return List.generate(3, (i) {
      if (i >= parts.length) return 0;
      return int.tryParse(parts[i]) ?? 0;
    });
  }
}
