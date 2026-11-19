import 'package:flutter/foundation.dart';

import '../../../../core/sync/auto_sync_coordinator.dart';
import '../../data/datasources/local_autotag_datasource.dart';
import '../../data/repositories/library_repository.dart';
import '../../domain/entities/sound.dart';
import 'sync_controller.dart';

/// Ce que la maintenance (build debug) peut recalculer.
enum RecomputeTask {
  /// Enveloppe waveform de chaque son téléchargé.
  waveforms,

  /// Gain « auto » (sonie) de chaque son téléchargé : **remplace** les gains
  /// réglés.
  gains,

  /// Suggestions de tags des musiques non traitées, depuis leur empreinte.
  suggestions,

  /// Empreinte audio des musiques non traitées (ré-analyse l'audio, long) ;
  /// entraîne le recalcul de leurs suggestions.
  fingerprints,
}

/// Ce qu'un recalcul toucherait, pour l'afficher avant de lancer.
class RecomputePlan {
  /// Sons dont le fichier est sur cet appareil : seuls recalculables.
  final List<Sound> local;
  final int unavailable;

  /// Waveforms manquantes ou d'une génération d'extraction obsolète.
  final int staleWaveforms;

  /// Sons au gain déjà réglé, que « Gain auto » remplacerait.
  final int customizedGains;

  /// Musiques non traitées : les seules dont l'analyse de tags se rouvre.
  final int eligibleMusic;

  const RecomputePlan({
    required this.local,
    required this.unavailable,
    required this.staleWaveforms,
    required this.customizedGains,
    required this.eligibleMusic,
  });
}

/// Orchestre le recalcul de maintenance (décision 0049), **build debug
/// seulement** : waveforms, gains et analyse de tags, au choix, l'un après
/// l'autre. Ne télécharge rien ; chaque écriture est faite au fil de l'eau, donc
/// annuler ne perd rien de ce qui est déjà recalculé.
class MaintenanceRecomputeController extends ChangeNotifier {
  final LibraryRepository _repository;
  final LocalAutoTagDataSource _autoTagData;
  final AutoSyncCoordinator _coordinator;
  final SyncController _syncController;

  MaintenanceRecomputeController({
    required LibraryRepository repository,
    required LocalAutoTagDataSource autoTagData,
    required AutoSyncCoordinator coordinator,
    required SyncController syncController,
  }) : _repository = repository,
       _autoTagData = autoTagData,
       _coordinator = coordinator,
       _syncController = syncController;

  RecomputePlan? _plan;
  AutoVolumePlan? _volumePlan;
  Object? _loadError;
  bool _isRunning = false;
  bool _cancelRequested = false;
  String? _stage;
  ({int done, int total})? _progress;
  final List<String> _report = [];

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Une passe qui finit après la fermeture de l'écran ne doit pas notifier un
  /// contrôleur libéré.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  RecomputePlan? get plan => _plan;
  Object? get loadError => _loadError;
  bool get isRunning => _isRunning;
  bool get cancelRequested => _cancelRequested;

  /// Étape en cours (« Waveforms »…), `null` hors passe.
  String? get stage => _stage;
  ({int done, int total})? get progress => _progress;

  /// Bilan ligne à ligne de la dernière passe.
  List<String> get report => List.unmodifiable(_report);

  /// Les passes de maintenance se taisent en Mode Spectacle, comme le reste.
  bool get isBlockedByLiveMode => _syncController.isAutoSyncPaused;

  /// L'analyse de tags n'existe que sur poste de bureau.
  bool get hasAutoTag => _coordinator.autoTagAnalysis != null;

  Future<void> load() async {
    _loadError = null;
    notifyListeners();
    try {
      final volumePlan = await _repository.planAutoVolumeRecompute();
      _volumePlan = volumePlan;
      _plan = RecomputePlan(
        local: volumePlan.sounds,
        unavailable: volumePlan.unavailable,
        staleWaveforms: _repository
            .soundsWithStaleWaveform(volumePlan.sounds)
            .length,
        customizedGains: volumePlan.customized,
        eligibleMusic: _eligibleMusic(volumePlan.sounds).length,
      );
    } catch (e) {
      _loadError = e;
    }
    notifyListeners();
  }

  /// Musiques non traitées : mêmes critères que l'analyse (`LocalAutoTagDataSource`).
  List<Sound> _eligibleMusic(Iterable<Sound> sounds) => [
    for (final sound in sounds)
      if (sound.type == SoundType.music && !sound.isProcessed) sound,
  ];

  void requestCancel() {
    if (!_isRunning) return;
    _cancelRequested = true;
    notifyListeners();
  }

  /// Recalcule [tasks] dans l'ordre : waveforms, gains, puis tags. Ne lève pas :
  /// un échec est consigné dans le [report].
  Future<void> run(Set<RecomputeTask> tasks) async {
    final plan = _plan;
    final volumePlan = _volumePlan;
    if (_isRunning || plan == null || volumePlan == null || tasks.isEmpty) {
      return;
    }
    _isRunning = true;
    _cancelRequested = false;
    _report.clear();
    notifyListeners();
    try {
      if (tasks.contains(RecomputeTask.waveforms)) {
        await _runWaveforms(plan);
      }
      if (tasks.contains(RecomputeTask.gains) && !_cancelRequested) {
        await _runGains(volumePlan);
      }
      final fingerprints = tasks.contains(RecomputeTask.fingerprints);
      if ((fingerprints || tasks.contains(RecomputeTask.suggestions)) &&
          !_cancelRequested) {
        await _runTags(plan, dropEmbeddings: fingerprints);
      }
    } catch (e) {
      _report.add('Échec : $e');
    } finally {
      _isRunning = false;
      _stage = null;
      _progress = null;
      if (_cancelRequested) {
        _report.add('Annulé : le déjà recalculé est conservé.');
      }
      _cancelRequested = false;
      // Les pads chargés et l'index de recherche portent les anciennes valeurs.
      _syncController.onLibraryMerged?.call();
      notifyListeners();
      // Les compteurs ont changé.
      await load();
    }
  }

  void _step(String stage, int total) {
    _stage = stage;
    _progress = (done: 0, total: total);
    notifyListeners();
  }

  void _tick(int done, int total) {
    _progress = (done: done, total: total);
    notifyListeners();
  }

  Future<void> _runWaveforms(RecomputePlan plan) async {
    _step('Waveforms', plan.local.length);
    final result = await _repository.recomputeWaveforms(
      plan.local,
      onProgress: _tick,
      isCancelled: () => _cancelRequested,
    );
    _report.add(
      'Waveforms : ${result.updated} recalculée(s), ${result.unsupported} '
      'format(s) refusé(s), ${result.unavailable} fichier(s) indisponible(s)'
      '${result.cancelled && !_cancelRequested ? ' — moteur audio pas prêt' : ''}.',
    );
  }

  Future<void> _runGains(AutoVolumePlan volumePlan) async {
    _step('Gain auto', volumePlan.sounds.length);
    final result = await _repository.recomputeAutoVolumes(
      volumePlan,
      onProgress: _tick,
      isCancelled: () => _cancelRequested,
    );
    final failed = result.unmeasurable + result.skipped;
    _report.add(
      'Gain auto : ${result.updated} mis à jour'
      '${failed > 0 ? ', $failed non mesurable(s) (gain conservé)' : ''}.',
    );
  }

  Future<void> _runTags(
    RecomputePlan plan, {
    required bool dropEmbeddings,
  }) async {
    _step('Analyse des tags', 0);
    final reopened = await _autoTagData.reopenAnalysis(
      _eligibleMusic(plan.local).map((s) => s.id),
      dropEmbeddings: dropEmbeddings,
    );
    // L'analyse tourne en fond (file native, arrêtée en Mode Spectacle…) : on
    // la demande, on ne l'attend pas.
    final refused = _coordinator.requestAutoTag();
    _report.add(
      'Tags : $reopened musique(s) rouverte(s)'
      '${dropEmbeddings ? ' (empreintes effacées)' : ''}. '
      '${refused == null ? 'Analyse lancée en arrière-plan (journal : « Analyse auto »).' : 'Analyse différée : $refused.'}',
    );
  }
}
