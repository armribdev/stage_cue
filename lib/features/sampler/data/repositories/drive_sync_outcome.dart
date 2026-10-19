part of 'library_repository.dart';

/// Issue d'une tentative de synchronisation incrémentale.
sealed class DriveSyncOutcome {
  const DriveSyncOutcome();
}

/// Les changements ont été appliqués : aucun scan complet n'est nécessaire.
class DriveSyncApplied extends DriveSyncOutcome {
  /// Fichiers ajoutés ou modifiés reflétés en base.
  final int upserted;

  /// Sons retirés parce que Drive a signalé leur disparition.
  final int removed;

  const DriveSyncApplied({required this.upserted, required this.removed});
}

/// Le delta n'est pas exploitable : l'appelant doit lancer un scan complet.
///
/// **Ce n'est pas un échec** : c'est le mode dégradé attendu, et le seul qui
/// puisse rétablir la vérité. Y retomber souvent coûte du temps ; ne pas y
/// retomber quand il le faudrait coûte des données.
class DriveSyncNeedsFullScan extends DriveSyncOutcome {
  final String reason;
  const DriveSyncNeedsFullScan(this.reason);
}
