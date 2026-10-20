/// Résultat d'un check de mise à jour concluant : une version plus récente
/// que celle en cours d'exécution, avec l'asset installeur correspondant.
class AppUpdateInfo {
  final String version;
  final String downloadUrl;
  final String assetName;

  /// Empreinte SHA-256 attendue de l'installeur (hexadécimal minuscule, 64
  /// caractères), lue dans le champ `digest` de l'API GitHub. Vérifiée avant
  /// tout lancement — voir [décision 0026](../../../docs/decisions/0026-verification-sha256-de-l-installeur.md).
  final String sha256;

  const AppUpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.assetName,
    required this.sha256,
  });
}
