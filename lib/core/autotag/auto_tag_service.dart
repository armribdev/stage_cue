import 'dart:io';

import 'package:path/path.dart' as p;

import '../../features/sampler/data/datasources/local_autotag_datasource.dart';
import '../../features/sampler/domain/entities/sound.dart' as domain;
import '../audio/audio_load_log.dart';
import '../logging/app_log.dart';
import '../sync/library_sound_paths.dart';
import '../utils/path_unicode.dart';
import 'audio_stream_info.dart';
import 'auto_tag_embedder.dart';
import 'auto_tag_pack.dart';
import 'mood_tagging.dart';

/// Bilan d'un passage de [AutoTagService.run].
class AutoTagReport {
  /// Sons dont l'empreinte a été calculée pendant ce passage.
  final int analyzed;

  /// Sons écartés pour de bon (format, durée, silence…), par raison.
  final Map<String, int> notAnalyzable;

  /// Échecs inattendus (réessayés au prochain passage).
  final int failed;

  /// Sons éligibles dont le fichier n'est pas encore sur l'appareil.
  final int notDownloaded;

  /// Sons qui ont reçu des tags, et nombre de tags posés.
  final int soundsTagged;
  final int tagsInserted;

  /// Raison pour laquelle le passage s'est arrêté avant la fin, ou `null`.
  final String? interruptedBy;

  const AutoTagReport({
    this.analyzed = 0,
    this.notAnalyzable = const {},
    this.failed = 0,
    this.notDownloaded = 0,
    this.soundsTagged = 0,
    this.tagsInserted = 0,
    this.interruptedBy,
  });
}

/// Analyse automatique des tags (décisions 0029 et 0030) : calcule l'empreinte
/// audio des musiques éligibles puis enregistre leurs ambiances comme tags de
/// l'IA — une couche à part, masquable, que l'utilisateur ne détruit jamais.
///
/// Éligible : type musique, non traité (le passer en « traité » fige ses tags),
/// jamais analysé, fichier déjà sur l'appareil. Deux temps, car la décision exige des statistiques sur la
/// bibliothèque :
/// 1. **analyse** : empreinte de chaque son, conservée en base ;
/// 2. **décision** : recentrage par ambiance sur tous les sons analysés, puis
///    tags posés (rien tant que [MoodTagRule.minLibrarySize] sons ne sont pas
///    analysés). Elle revérifie l'éligibilité de chaque son.
///
/// Ne s'orchestre pas elle-même : `AutoSyncCoordinator` décide quand lancer un
/// passage et quand l'interrompre (Mode Spectacle, arrière-plan, synchro).
class AutoTagService {
  final LocalAutoTagDataSource _data;
  final AutoTagPack _pack;
  final Future<Map<int, String>> Function() _libraryRoots;
  final Future<Set<int>> Function(Iterable<domain.Sound>) _probeAvailable;
  final Future<MoodScorer> Function() _loadScorer;
  final Future<AutoTagEmbedder> Function(String modelPath) _openEmbedder;
  final DateTime Function() _now;

  bool _running = false;
  bool _packMissingReported = false;

  AutoTagService({
    required LocalAutoTagDataSource data,
    required AutoTagPack pack,
    required Future<Map<int, String>> Function() libraryRoots,
    required Future<Set<int>> Function(Iterable<domain.Sound>) probeAvailable,
    required Future<MoodScorer> Function() loadScorer,
    Future<AutoTagEmbedder> Function(String modelPath) openEmbedder =
        MuqEmbedder.open,
    DateTime Function() now = DateTime.now,
  }) : _data = data,
       _pack = pack,
       _libraryRoots = libraryRoots,
       _probeAvailable = probeAvailable,
       _loadScorer = loadScorer,
       _openEmbedder = openEmbedder,
       _now = now;

  bool get isRunning => _running;

  /// Un passage. [stopReason] est interrogée entre deux sons : une valeur
  /// non nulle (« Mode Spectacle »…) arrête l'analyse, la décision se fait
  /// quand même sur ce qui est déjà analysé. Ne lève jamais.
  Future<AutoTagReport> run({required String? Function() stopReason}) async {
    if (_running) return const AutoTagReport();
    _running = true;
    try {
      return await _run(stopReason);
    } catch (e, stackTrace) {
      AppLog.severe(
        'Analyse auto : passage abandonné sur erreur inattendue.',
        error: e,
        stackTrace: stackTrace,
      );
      return const AutoTagReport();
    } finally {
      _running = false;
    }
  }

  Future<AutoTagReport> _run(String? Function() stopReason) async {
    var analyzed = 0;
    var failed = 0;
    var notDownloaded = 0;
    final notAnalyzable = <String, int>{};
    String? interruptedBy;

    // ── 1. Analyse ──────────────────────────────────────────────────────────
    final candidates = await _data.soundsToAnalyze();
    if (candidates.isNotEmpty) {
      if (!await _pack.isInstalled()) {
        if (!_packMissingReported) {
          _packMissingReported = true;
          AppLog.info(
            'Analyse auto : ${candidates.length} musique(s) à analyser mais le '
            'pack de modèles n\'est pas installé — rien à faire.',
          );
        }
      } else {
        final available = await _probeAvailable(candidates);
        final local = [
          for (final s in candidates)
            if (available.contains(s.id)) s,
        ];
        notDownloaded = candidates.length - local.length;
        if (local.isNotEmpty) {
          AppLog.info(
            'Analyse auto : démarrage — ${local.length} musique(s) à analyser'
            '${notDownloaded > 0 ? ' ($notDownloaded pas encore téléchargée(s))' : ''}.',
          );
          final roots = await _libraryRoots();
          AutoTagEmbedder? embedder;
          try {
            embedder = await _openEmbedder((await _pack.modelFile()).path);
            var consecutiveFailures = 0;
            for (final sound in local) {
              interruptedBy = stopReason();
              if (interruptedBy != null) break;
              try {
                final file = await _localFile(sound, roots);
                if (file == null) {
                  notDownloaded++;
                  continue;
                }
                final embedding = await embedder.embed(file);
                await _data.storeEmbedding(
                  sound.id,
                  embeddingToBytes(embedding),
                );
                analyzed++;
                consecutiveFailures = 0;
              } on AudioNotAnalyzable catch (e) {
                await _data.markNotAnalyzable(sound.id, _now());
                notAnalyzable[e.reason] = (notAnalyzable[e.reason] ?? 0) + 1;
                AudioLoadLog.trace(
                  'Analyse auto : "${sound.title}" écarté — ${e.reason}',
                );
              } catch (e) {
                failed++;
                AudioLoadLog.trace(
                  'Analyse auto : échec sur "${sound.title}" — $e',
                );
                // Une panne qui se répète (modèle, mémoire) ne s'arrange pas
                // en insistant : on s'arrête, le prochain passage réessaiera.
                if (++consecutiveFailures >= 5) {
                  interruptedBy = 'erreurs répétées ($e)';
                  break;
                }
              }
            }
          } catch (e, stackTrace) {
            AppLog.severe(
              'Analyse auto : chargement du modèle impossible.',
              error: e,
              stackTrace: stackTrace,
            );
            interruptedBy = 'modèle illisible';
          } finally {
            await embedder?.close();
          }
        }
      }
    }

    // ── 2. Décision ─────────────────────────────────────────────────────────
    final applied = await _decide();

    final report = AutoTagReport(
      analyzed: analyzed,
      notAnalyzable: notAnalyzable,
      failed: failed,
      notDownloaded: notDownloaded,
      soundsTagged: applied?.soundsTagged ?? 0,
      tagsInserted: applied?.tagsInserted ?? 0,
      interruptedBy: interruptedBy,
    );
    if (analyzed > 0 ||
        failed > 0 ||
        notAnalyzable.isNotEmpty ||
        report.tagsInserted > 0) {
      final skipped = notAnalyzable.entries
          .map((e) => '${e.value}× ${e.key}')
          .join(', ');
      AppLog.info(
        'Analyse auto : bilan — $analyzed analysé(s)'
        '${notAnalyzable.isEmpty ? '' : ', écarté(s) ($skipped)'}'
        '${failed > 0 ? ', $failed échec(s)' : ''}'
        ', ${report.tagsInserted} tag(s) posé(s) sur ${report.soundsTagged} son(s)'
        '${interruptedBy != null ? ' — interrompue : $interruptedBy' : ''}.',
      );
    }
    return report;
  }

  /// Pose les tags des sons analysés dont la décision n'est pas prise.
  Future<AutoTagApplyResult?> _decide() async {
    final analyzed = await _data.analyzedSounds();
    final pending = [
      for (final a in analyzed)
        if (!a.decided) a,
    ];
    if (pending.isEmpty) return null;

    final scorer = await _loadScorer();
    final scores = <int, List<double>>{};
    for (final a in analyzed) {
      final embedding = embeddingFromBytes(a.embedding);
      if (embedding != null) scores[a.soundId] = scorer.scores(embedding);
    }
    final stats = MoodStats.fromScores(scores.values.toList());
    if (stats.sampleCount < MoodTagRule.minLibrarySize) {
      AppLog.info(
        'Analyse auto : ${stats.sampleCount}/${MoodTagRule.minLibrarySize} '
        'musique(s) analysée(s) — aucun tag posé tant que la bibliothèque '
        'analysée est trop petite.',
      );
      return null;
    }

    final decisions = [
      for (final a in pending)
        if (scores[a.soundId] != null)
          AutoTagDecision(
            a.soundId,
            MoodTagRule.tagNames(scores[a.soundId]!, stats),
          ),
    ];
    final result = await _data.applyDecisions(
      decisions,
      categoryName: kMoodTagCategory,
      when: _now(),
    );
    if (result.soundsNoLongerEligible > 0) {
      AppLog.info(
        'Analyse auto : ${result.soundsNoLongerEligible} son(s) traité(s) ou '
        'retypé(s) entre-temps, laissé(s) intact(s).',
      );
    }
    return result;
  }

  /// Fichier local d'un son, ou `null` s'il a disparu depuis la sonde. Les noms
  /// du disque peuvent être NFD là où la base est NFC : on les rapproche.
  Future<File?> _localFile(domain.Sound sound, Map<int, String> roots) async {
    final libraryId = sound.libraryId;
    final relative = sound.relativePath;
    final String expected;
    if (libraryId != null && relative != null && relative.isNotEmpty) {
      final root = roots[libraryId];
      if (root == null) return null;
      expected = LibrarySoundPaths.localPathFor(
        root,
        LibrarySoundPaths.normalizeRelativePath(relative),
      );
    } else {
      expected = sound.filePath;
    }
    final canonical = await PathUnicode.canonicalizeLocalPath(expected);
    return canonical == null ? null : File(p.normalize(canonical));
  }
}
