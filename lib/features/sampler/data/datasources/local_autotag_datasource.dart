import 'package:drift/drift.dart';

import '../../../../core/database/database.dart' as db;
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

/// Tags d'ambiance à poser sur un son (peut être vide : la décision est alors
/// « rien à poser » et le son est marqué comme décidé).
class AutoTagDecision {
  final int soundId;
  final List<String> tagNames;
  const AutoTagDecision(this.soundId, this.tagNames);
}

/// Bilan de [LocalAutoTagDataSource.applyDecisions].
class AutoTagApplyResult {
  /// Sons qui ont reçu au moins un tag.
  final int soundsTagged;
  final int tagsInserted;

  /// Sons laissés intacts parce que traités, taggés ou retypés entre l'analyse
  /// et la décision.
  final int soundsNoLongerEligible;
  const AutoTagApplyResult({
    required this.soundsTagged,
    required this.tagsInserted,
    required this.soundsNoLongerEligible,
  });
}

/// Accès base de l'analyse automatique des tags (décision 0029).
///
/// Un son est **éligible** s'il est de type musique, non traité et sans tag :
/// l'analyse ne touche jamais un son que l'utilisateur a déjà validé ou tagué.
class LocalAutoTagDataSource {
  final db.AppDatabase _database;

  LocalAutoTagDataSource(this._database);

  /// Condition d'éligibilité, sur l'alias `sounds`. `type = 1` est
  /// `SoundType.music` (index de l'enum, cf. `sounds.dart`).
  static const String _eligibleSql =
      'sounds.type = 1 AND sounds.is_processed = 0 '
      'AND NOT EXISTS (SELECT 1 FROM sound_tags st WHERE st.sound_id = sounds.id)';

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
  /// chaque son (l'utilisateur a pu le traiter ou le tagger depuis l'analyse),
  /// pose les tags de [categoryName] puis renseigne `auto_tagged_at` — même
  /// quand rien n'est posé, pour ne pas décider en boucle.
  ///
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
        if (eligible.isEmpty) {
          notEligible++;
        } else {
          var inserted = 0;
          for (final name in decision.tagNames) {
            final tagId = tagIds[name];
            if (tagId == null) continue;
            await _database
                .into(_database.soundTags)
                .insert(
                  db.SoundTagsCompanion.insert(
                    soundId: decision.soundId,
                    tagId: tagId,
                    addedAt: Value(when),
                  ),
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
