import '../../../../core/autotag/auto_tag_analysis.dart';
import '../../../../core/autotag/auto_tag_status.dart';
import '../../../../core/logging/app_log.dart';
import '../../../../core/utils/title_tag_matcher.dart';
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/sound_auto_tag.dart';
import '../utils/title_tag_proposals.dart';
import 'animated_pill_wrap.dart';

/// Tout ce que la section « Tags » de [SoundEditForm] lit en base : les tags du
/// son, les suggestions de l'IA, celles du titre (décision 0041) et l'état de
/// l'analyse.
///
/// Lu **avant** de monter le formulaire d'un son ([SoundEditPane]) pour que sa
/// première image soit déjà complète : sinon la section s'afficherait vide puis
/// se remplirait en s'animant à chaque changement de son.
class SoundEditPreload {
  final Set<int> tagIds;
  final List<SoundAutoTag> autoTags;
  final List<TitleTagMatch> titleMatches;

  /// `null` : fonction d'analyse absente, son disparu ou lecture impossible.
  final SoundAnalysisStatus? analysisStatus;

  const SoundEditPreload({
    required this.tagIds,
    required this.autoTags,
    required this.titleMatches,
    required this.analysisStatus,
  });

  /// Lève si les tags du son sont illisibles ; le reste est facultatif (un
  /// échec est journalisé et laisse la valeur vide).
  static Future<SoundEditPreload> load({
    required Sound sound,
    required SoundRepository repository,
    AutoTagAnalysis? autoTag,
  }) async {
    final tags = await repository.getTagsForSound(sound.id);
    var auto = const <SoundAutoTag>[];
    try {
      auto = await repository.getAutoTagsForSound(sound.id);
    } catch (error) {
      AppLog.warn('Tags de l’IA illisibles (son ${sound.id}) : $error');
    }
    var fromTitle = const <TitleTagMatch>[];
    try {
      final matcher = TitleTagMatcher(await repository.getTagVocabulary());
      fromTitle = titleTagMatchesFor(
        sound,
        matcher,
        excluded: {for (final tag in tags) tag.id},
      );
    } catch (error) {
      AppLog.warn('Tags du titre indisponibles (son ${sound.id}) : $error');
    }
    SoundAnalysisStatus? status;
    if (autoTag != null) {
      try {
        status = await autoTag.statusOf(sound.id);
      } catch (error) {
        AppLog.warn(
          'État de l’analyse IA illisible (son ${sound.id}) : $error',
        );
      }
    }
    return SoundEditPreload(
      tagIds: {for (final tag in tags) tag.id},
      autoTags: auto,
      titleMatches: fromTitle,
      analysisStatus: status,
    );
  }
}

/// Durée de la transition d'un son à l'autre : la waveform qui se transforme et
/// le curseur de volume qui glisse partent ensemble et durent pareil, pour
/// arriver ensemble.
const kSoundSwitchDuration = Duration(milliseconds: 500);

/// Ce que le formulaire affiché laisse au suivant, pour qu'il ne soit pas une
/// rupture d'un son à l'autre :
/// - section « Tags » : sa hauteur (la section suivante part de celle-ci et
///   s'anime vers la sienne) et ses suggestions (les pastilles qui n'ont plus
///   lieu d'être se referment, les nouvelles s'ouvrent) ;
/// - [waveformBars] et [offsetFraction] : l'enveloppe et la position (0→1) du
///   point d'entrée du son précédent, d'où la waveform du suivant se transforme
///   et sa poignée glisse au lieu de repartir d'une piste vide ;
/// - [volume] : celui du son précédent, d'où le curseur du suivant glisse.
class SoundFormMemory {
  double? value;
  final suggestions = PillMemory();
  List<double> waveformBars = const [];
  double? offsetFraction;
  double? volume;
}
