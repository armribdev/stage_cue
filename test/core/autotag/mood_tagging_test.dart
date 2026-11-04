import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/autotag/mood_tagging.dart';
import 'package:stage_cue/core/autotag/muq_analyzer.dart';
import 'package:stage_cue/core/database/database.dart';

/// Vecteurs texte « identité » : la ligne m est e_m, donc score[m] = embedding[m].
Float32List identityText() {
  final t = Float32List(kMoods.length * kMuqLatentSize);
  for (var m = 0; m < kMoods.length; m++) {
    t[m * kMuqLatentSize + m] = 1;
  }
  return t;
}

/// 60 sons dont les scores valent `base[m] ± 0,1` en alternance : moyenne
/// `base[m]`, écart-type 0,1.
MoodStats statsAround(List<double> base, {int count = 60}) =>
    MoodStats.fromScores([
      for (var i = 0; i < count; i++)
        [for (final b in base) b + (i.isEven ? 0.1 : -0.1)],
    ]);

List<double> flat(double v) => List.filled(kMoods.length, v);

void main() {
  group('MoodScorer', () {
    test('produit scalaire avec le vecteur texte de chaque ambiance', () {
      final e = Float32List(kMuqLatentSize);
      for (var i = 0; i < kMoods.length; i++) {
        e[i] = i / 10;
      }
      final s = MoodScorer(identityText()).scores(e);
      expect(s.length, kMoods.length);
      for (var m = 0; m < kMoods.length; m++) {
        expect(s[m], closeTo(m / 10, 1e-6));
      }
    });

    test('dimensions invalides refusées', () {
      expect(() => MoodScorer(Float32List(10)), throwsArgumentError);
      expect(
        () => MoodScorer(identityText()).scores(Float32List(3)),
        throwsArgumentError,
      );
    });

    test('le fichier livré en asset a une ligne par ambiance, unitaire', () {
      final bytes = File('assets/autotag/text_latents.f32').readAsBytesSync();
      expect(bytes.length, kMoods.length * kMuqLatentSize * 4);
      final v = MoodScorer.fromBytes(ByteData.sublistView(bytes));
      // Les latents MuQ sont normalisés : un écart signalerait un fichier
      // régénéré avec un autre modèle ou un autre ordre.
      final probe = Float32List(kMuqLatentSize)..[0] = 1;
      expect(v.scores(probe), everyElement(inInclusiveRange(-1.0, 1.0)));
      var normSq = 0.0;
      for (var i = 0; i < kMuqLatentSize; i++) {
        final f = ByteData.sublistView(bytes).getFloat32(i * 4, Endian.little);
        normSq += f * f;
      }
      expect(math.sqrt(normSq), closeTo(1, 1e-3));
    });
  });

  group('MoodStats', () {
    test('moyenne et écart-type par ambiance', () {
      final s = statsAround(List.generate(kMoods.length, (m) => m / 10));
      for (var m = 0; m < kMoods.length; m++) {
        expect(s.mean[m], closeTo(m / 10, 1e-9));
        expect(s.std[m], closeTo(0.1, 1e-9));
      }
      expect(s.sampleCount, 60);
    });

    test('aucun son : statistiques vides', () {
      expect(MoodStats.fromScores(const []).sampleCount, 0);
    });
  });

  group('MoodTagRule', () {
    final stats = statsAround(flat(0));

    List<String> names(List<double> scores, MoodStats stats) => [
      for (final s in MoodTagRule.suggestions(scores, stats)) s.tagName,
    ];

    test('aucun tag tant que la bibliothèque est trop petite', () {
      final small = statsAround(flat(0), count: MoodTagRule.minLibrarySize - 1);
      final scores = flat(0)..[0] = 5;
      expect(names(scores, small), isEmpty);
      expect(names(scores, statsAround(flat(0), count: 50)), ['Joyeux']);
    });

    test('seuil : en dessous d\'un écart-type, rien', () {
      final scores = flat(0)..[0] = 0.0999; // z ≈ 0,999
      expect(names(scores, stats), isEmpty);
      scores[0] = 0.1001;
      expect(names(scores, stats), ['Joyeux']);
    });

    test('le score est comparé à la moyenne de l\'ambiance, pas au brut', () {
      // Calme sort toujours haut (moyenne 0,5) : 0,55 est banal, 0,75 marqué.
      final biased = statsAround(flat(0)..[8] = 0.5);
      final scores = flat(0)..[8] = 0.55;
      expect(names(scores, biased), isEmpty);
      scores[8] = 0.75;
      expect(names(scores, biased), ['Calme']);
    });

    test('au plus 3 tags, du plus marqué au moins marqué', () {
      final scores = flat(0)
        ..[1] =
            0.5 // Triste
        ..[4] =
            0.9 // Angoisse
        ..[10] =
            0.7 // Sombre
        ..[5] = 0.3; // Tension
      expect(names(scores, stats), ['Angoisse', 'Sombre', 'Triste']);
    });

    test('deux ambiances du même tag ne le posent qu\'une fois', () {
      // Romantique (7) et Sensuel (14) → Romantique ; Sensuel plus marqué.
      final scores = flat(0)
        ..[7] = 0.4
        ..[14] = 0.9
        ..[8] = 0.3; // Calme
      expect(names(scores, stats), ['Romantique', 'Calme']);
    });

    test('une ambiance qui ne varie pas ne discrimine rien', () {
      final constant = MoodStats.fromScores([
        for (var i = 0; i < 60; i++) flat(0.3),
      ]);
      expect(names(flat(9), constant), isEmpty);
    });

    test(
      'chaque suggestion porte une confiance entre 0 et 1, décroissante',
      () {
        final scores = flat(0)
          ..[1] =
              0.5 // Triste
          ..[4] =
              0.9 // Angoisse
          ..[10] = 0.7; // Sombre
        final suggestions = MoodTagRule.suggestions(scores, stats);
        expect(suggestions.map((s) => s.tagName), [
          'Angoisse',
          'Sombre',
          'Triste',
        ]);
        for (final s in suggestions) {
          expect(s.score, inExclusiveRange(0, 1));
        }
        final sorted = [for (final s in suggestions) s.score];
        expect(
          sorted,
          orderedEquals([...sorted]..sort((a, b) => b.compareTo(a))),
        );
        // La plus marquée domine la répartition du son.
        expect(sorted.first, greaterThan(sorted.last));
      },
    );

    test('deux ambiances du même tag additionnent leur confiance', () {
      final single = MoodTagRule.suggestions(flat(0)..[7] = 0.5, stats);
      final both = MoodTagRule.suggestions(
        flat(0)
          ..[7] = 0.5
          ..[14] = 0.5,
        stats,
      );
      expect(single.single.tagName, 'Romantique');
      expect(both.single.tagName, 'Romantique');
      expect(both.single.score, greaterThan(single.single.score));
    });

    test('nombre de scores invalide', () {
      expect(() => MoodTagRule.suggestions([1], stats), throwsArgumentError);
    });
  });

  group('catalogue', () {
    test('chaque ambiance pointe vers un tag EMOTION_STYLE existant', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final rows = await database
          .customSelect(
            'SELECT t.name AS name FROM tags t '
            'JOIN tag_categories c ON c.id = t.category_id '
            'WHERE c.name = ?',
            variables: [Variable.withString(kMoodTagCategory)],
          )
          .get();
      final existing = {for (final r in rows) r.read<String>('name')};
      for (final mood in kMoods) {
        expect(
          existing,
          contains(mood.tagName),
          reason: '${mood.label} → ${mood.tagName}',
        );
      }
    });
  });
}
