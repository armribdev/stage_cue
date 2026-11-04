import 'package:flutter/foundation.dart' show ValueListenable;

import 'auto_tag_service.dart';
import 'auto_tag_status.dart';

/// Ce que la fiche d'un son voit de l'analyse automatique : où elle en est pour
/// ce son, et un moyen de la demander.
///
/// Ne lance rien elle-même : la demande passe par `AutoSyncCoordinator`, seul à
/// décider si un passage peut tourner (Mode Spectacle, arrière-plan, synchro).
class AutoTagAnalysis {
  final AutoTagService _service;
  final String? Function(int soundId) _request;

  AutoTagAnalysis(this._service, this._request);

  /// Passage en cours — à écouter pour rafraîchir [statusOf].
  ValueListenable<AutoTagActivity> get activity => _service.activity;

  Future<SoundAnalysisStatus?> statusOf(int soundId) =>
      _service.statusOf(soundId);

  /// Demande l'analyse de ce son en tête de file. Renvoie la raison pour
  /// laquelle rien ne démarre (« Mode Spectacle »…), `null` si c'est parti.
  String? start(int soundId) => _request(soundId);
}
