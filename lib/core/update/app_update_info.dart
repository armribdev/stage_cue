/// Résultat d'un check de mise à jour concluant : une version plus récente
/// que celle en cours d'exécution, avec l'asset installeur correspondant.
class AppUpdateInfo {
  final String version;
  final String downloadUrl;
  final String assetName;

  const AppUpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.assetName,
  });
}
