import 'package:drift/drift.dart';

import '../../../../core/database/database.dart' as db;
import '../../domain/entities/auto_tag_suggestion.dart';
import '../../domain/entities/sound.dart' as domain;
import '../models/sound_model.dart';

/// Empreinte d'un son déjà analysé, avec l'état de la décision de tags.
class AnalyzedSound {
  final int soundId;
  final Uint8List embedding;

  /// `true` si la décision (tags posés ou non) est déjà prise.
  final bool decided;
  const AnalyzedSound({
    required this.soundId,
    required this.embedding,
    required this.decided,
  });
}

/// Marques d'analyse d'un son, telles qu'écrites en base.
class SoundAnalysisMarks {
  final bool isMusic;
  final bool isProcessed;

  /// Une empreinte audio est stockée.
  final bool hasEmbedding;

  /// `auto_tagged_at` renseigné : décision prise, ou son écarté pour de bon.
  final bool decided;
  const SoundAnalysisMarks({
    required this.isMusic,
    required this.isProcessed,
    required this.hasEmbedding,
    required this.decided,
  });
}

/// Suggestions d'ambiance à enregistrer pour un son (peut être vide : la
/// décision est alors « rien à suggérer » et le son est marqué comme décidé).
class AutoTagDecision {
  final int soundId;
  final List<AutoTagSuggestion> suggestions;
  const AutoTagDecision(this.soundId, this.suggestions);
}

/// Bilan de [LocalAutoTagDataSource.applyDecisions].
class AutoTagApplyResult {
  /// Sons qui ont reçu au moins une suggestion, et nombre de suggestions.
  final int soundsTagged;
  final int tagsInserted;

  /// Sons laissés intacts parce que traités ou retypés entre l'analyse et la
  /// décision.
  final int soundsNoLongerEligible;
  const AutoTagApplyResult({
    required this.soundsTagged,
    required this.tagsInserted,
    required this.soundsNoLongerEligible,
  });
}

/// Accès base de l'analyse automatique des tags (décisions 0029 à 0031).
///
/// Un son est **éligible** s'il est de type musique et non traité : passer un
/// son en « traité » à la main fige ses suggestions, l'IA n'y revient plus. Les
/// suggestions de l'IA vont dans `sound_auto_tags` avec leur score, jamais dans
/// `sound_tags` (ceux de l'utilisateur).
class LocalAutoTagDataSource {
  final db.AppDatabase _database;

  LocalAutoTagDataSource(this._database);

  /// Condition d'éligibilité, sur l'alias `sounds`. `type = 1` est
  /// `SoundType.music` (index de l'enum, cf. `sounds.dart`).
  static const String _eligibleSql =
      'sounds.type = 1 AND sounds.is_processed = 0';

  /// Sons éligibles jamais analysés ni écartés (pas d'empreinte, pas de marque).
  Future<List<domain.Sound>> soundsToAnalyze() async {
    final rows =
        await (_database.select(_database.sounds)..where(
              (s) =>
                  s.autoTaggedAt.isNull() &
                  s.autoEmbedding.isNull() &
                  const CustomExpression<bool>(_eligibleSql),
            ))
            .get();
    return rows.map(SoundModel.toEntity).toList();
  }

  /// Marques d'analyse d'un son, `null` s'il n'existe plus.
  Future<SoundAnalysisMarks?> marksOf(int soundId) async {
    final row = await _database
        .customSelect(
          'SELECT COALESCE(type = 1, 0) AS is_music, is_processed, '
          'auto_embedding IS NOT NULL AS has_embedding, '
          'auto_tagged_at IS NOT NULL AS decided '
          'FROM sounds WHERE id = ?',
          variables: [Variable<int>(soundId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return SoundAnalysisMarks(
      isMusic: row.read<int>('is_music') != 0,
      isProcessed: row.read<int>('is_processed') != 0,
      hasEmbedding: row.read<int>('has_embedding') != 0,
      decided: row.read<int>('decided') != 0,
    );
  }

  /// Empreinte de tous les sons analysés — éligibles ou non, décidés ou non :
  /// les statistiques par ambiance portent sur toute la bibliothèque analysée.
  Future<List<AnalyzedSound>> analyzedSounds() async {
    final rows = await _database
        .customSelect(
          'SELECT id, auto_embedding, auto_tagged_at FROM sounds '
          'WHERE auto_embedding IS NOT NULL',
        )
        .get();
    return [
      for (final r in rows)
        AnalyzedSound(
          soundId: r.read<int>('id'),
          embedding: r.read<Uint8List>('auto_embedding'),
          decided: r.read<int?>('auto_tagged_at') != null,
        ),
    ];
  }

  Future<void> storeEmbedding(int soundId, Uint8List embedding) =>
      (_database.update(_database.sounds)..where((s) => s.id.equals(soundId)))
          .write(db.SoundsCompanion(autoEmbedding: Value(embedding)));

  /// Marque un son comme à ne plus jamais tenter (format non analysable…).
  Future<void> markNotAnalyzable(int soundId, DateTime when) =>
      (_database.update(_database.sounds)..where((s) => s.id.equals(soundId)))
          .write(db.SoundsCompanion(autoTaggedAt: Value(when)));

  /// Applique les [decisions] en une transaction : revérifie l'éligibilité de
  /// chaque son (l'utilisateur a pu le traiter depuis l'analyse), enregistre ses
  /// suggestions dans `sound_auto_tags` (tags de [categoryName]), puis renseigne
  /// `auto_tagged_at` — même quand rien n'est suggéré, pour ne pas décider en
  /// boucle.
  ///
  /// Une ligne existante n'est **jamais modifiée**. Un son qui a déjà des
  /// suggestions (reçues d'un autre appareil par la synchro) n'est pas recalculé.
  /// Un nom de tag introuvable est ignoré (catalogue modifié à la main) : on ne
  /// crée jamais de tag.
  Future<AutoTagApplyResult> applyDecisions(
    List<AutoTagDecision> decisions, {
    required String categoryName,
    required DateTime when,
  }) {
    return _database.transaction(() async {
      final tagRows = await _database
          .customSelect(
            'SELECT t.id AS id, t.name AS name FROM tags t '
            'JOIN tag_categories c ON c.id = t.category_id WHERE c.name = ?',
            variables: [Variable<String>(categoryName)],
          )
          .get();
      final tagIds = {
        for (final r in tagRows) r.read<String>('name'): r.read<int>('id'),
      };

      var soundsTagged = 0;
      var tagsInserted = 0;
      var notEligible = 0;
      for (final decision in decisions) {
        final eligible = await _database
            .customSelect(
              'SELECT 1 FROM sounds WHERE id = ? AND $_eligibleSql',
              variables: [Variable<int>(decision.soundId)],
            )
            .get();
        final alreadyHasAutoTags = await _database
            .customSelect(
              'SELECT 1 FROM sound_auto_tags WHERE sound_id = ? LIMIT 1',
              variables: [Variable<int>(decision.soundId)],
            )
            .get();
        if (eligible.isEmpty) {
          notEligible++;
        } else if (alreadyHasAutoTags.isEmpty) {
          var inserted = 0;
          for (final suggestion in decision.suggestions) {
            final tagId = tagIds[suggestion.tagName];
            if (tagId == null) continue;
            await _database
                .into(_database.soundAutoTags)
                .insert(
                  db.SoundAutoTagsCompanion.insert(
                    soundId: decision.soundId,
                    tagId: tagId,
                    score: suggestion.score,
                    updatedAt: Value(when),
                  ),
                  mode: InsertMode.insertOrIgnore,
                );
            inserted++;
          }
          if (inserted > 0) soundsTagged++;
          tagsInserted += inserted;
        }
        await (_database.update(_database.sounds)
              ..where((s) => s.id.equals(decision.soundId)))
            .write(db.SoundsCompanion(autoTaggedAt: Value(when)));
      }
      return AutoTagApplyResult(
        soundsTagged: soundsTagged,
        tagsInserted: tagsInserted,
        soundsNoLongerEligible: notEligible,
      );
    });
  }
}
