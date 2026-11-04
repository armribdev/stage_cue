import 'dart:math' as math;
import 'dart:typed_data';

import '../../features/sampler/domain/entities/auto_tag_suggestion.dart';
import 'muq_analyzer.dart' show kMuqLatentSize;

/// Ambiance reconnue par le modèle et tag de la base qu'elle pose.
///
/// [label] sert à générer le vecteur texte (`tool/autotag/gen_text_latents.py`) ;
/// [tagName] est un tag **existant** de la catégorie EMOTION_STYLE
/// ([kMoodTagCategory]) : l'analyse ne crée jamais de tag (un tag nouveau passe
/// par une migration de données, cf. `docs/tags.md`).
class Mood {
  final String label;
  final String tagName;
  const Mood(this.label, this.tagName);
}

/// Catégorie des tags posés par l'analyse d'ambiance.
const String kMoodTagCategory = 'EMOTION_STYLE';

/// Ambiances, **dans l'ordre des lignes de `assets/autotag/text_latents.f32`**.
/// Merveilleux, Dramatique et Sensuel n'ont pas de tag propre : alias de
/// Magie, Drame et Romantique.
const List<Mood> kMoods = [
  Mood('Joyeux', 'Joyeux'),
  Mood('Triste', 'Triste'),
  Mood('Nostalgique', 'Nostalgique'),
  Mood('Épique', 'Épique'),
  Mood('Angoisse', 'Angoisse'),
  Mood('Tension', 'Tension'),
  Mood('Mystérieux', 'Mystérieux'),
  Mood('Romantique', 'Romantique'),
  Mood('Calme', 'Calme'),
  Mood('Merveilleux', 'Magie'),
  Mood('Sombre', 'Sombre'),
  Mood('Énergique', 'Énergique'),
  Mood('Léger', 'Léger'),
  Mood('Dramatique', 'Drame'),
  Mood('Sensuel', 'Romantique'),
];

/// Score brut de chaque ambiance pour un son : produit scalaire de son
/// empreinte avec le vecteur texte de l'ambiance.
class MoodScorer {
  final Float32List _text;

  /// [textLatents] : `kMoods.length × kMuqLatentSize` flottants, ligne par ambiance.
  MoodScorer(this._text) {
    if (_text.length != kMoods.length * kMuqLatentSize) {
      throw ArgumentError(
        'Vecteurs texte : ${_text.length} valeurs au lieu de '
        '${kMoods.length * kMuqLatentSize}',
      );
    }
  }

  /// Lit les octets du fichier `text_latents.f32` (flottants 32 bits
  /// petit-boutistes).
  factory MoodScorer.fromBytes(ByteData bytes) {
    final out = Float32List(bytes.lengthInBytes ~/ 4);
    for (var i = 0; i < out.length; i++) {
      out[i] = bytes.getFloat32(i * 4, Endian.little);
    }
    return MoodScorer(out);
  }

  List<double> scores(Float32List embedding) {
    if (embedding.length != kMuqLatentSize) {
      throw ArgumentError(
        'Empreinte de ${embedding.length} valeurs au lieu de $kMuqLatentSize',
      );
    }
    return [
      for (var m = 0; m < kMoods.length; m++)
        () {
          var s = 0.0;
          final base = m * kMuqLatentSize;
          for (var i = 0; i < kMuqLatentSize; i++) {
            s += _text[base + i] * embedding[i];
          }
          return s;
        }(),
    ];
  }
}

/// Moyenne et écart-type de chaque ambiance sur les sons déjà analysés de la
/// bibliothèque. Les scores bruts sont biaisés par ambiance (certaines sortent
/// toujours haut) : seul l'écart à la moyenne de la bibliothèque est informatif
/// (ADR 0029 : recentrer améliore le n°1 identique à la référence de 81 % à 92 %).
class MoodStats {
  final List<double> mean;
  final List<double> std;
  final int sampleCount;
  const MoodStats._(this.mean, this.std, this.sampleCount);

  factory MoodStats.fromScores(List<List<double>> scores) {
    final n = scores.length;
    final mean = List<double>.filled(kMoods.length, 0);
    final std = List<double>.filled(kMoods.length, 0);
    if (n == 0) return MoodStats._(mean, std, 0);
    for (final s in scores) {
      for (var m = 0; m < kMoods.length; m++) {
        mean[m] += s[m] / n;
      }
    }
    for (final s in scores) {
      for (var m = 0; m < kMoods.length; m++) {
        final d = s[m] - mean[m];
        std[m] += d * d / n;
      }
    }
    for (var m = 0; m < kMoods.length; m++) {
      std[m] = math.sqrt(std[m]);
    }
    return MoodStats._(mean, std, n);
  }
}

/// Règle qui transforme les scores d'un son en suggestions de tags d'ambiance.
///
/// Conservatrice : mieux vaut aucune suggestion qu'une mauvaise. Une ambiance
/// n'est retenue que si son score dépasse la moyenne de la bibliothèque d'au moins
/// [minZScore] écarts-types ; au plus [maxTags] tags distincts ; et rien du tout
/// tant que la bibliothèque compte moins de [minLibrarySize] sons analysés
/// (moyennes et écarts-types encore instables).
///
/// Le score d'une suggestion est la part de son ambiance dans la **répartition
/// du son** : softmax des écarts réduits (z) des 15 ambiances. C'est une
/// confiance relative — « cette ambiance domine-t-elle les autres pour ce
/// son » —, pas une probabilité calibrée : aucune vérité terrain ne permet de la
/// calibrer. Deux ambiances qui pointent vers le même tag (Sensuel et Romantique)
/// s'additionnent.
abstract final class MoodTagRule {
  static const int minLibrarySize = 50;
  static const double minZScore = 1.0;
  static const int maxTags = 3;

  /// Écart-type en deçà duquel une ambiance ne discrimine rien.
  static const double _minStd = 1e-4;

  /// Suggestions du son, de la plus à la moins confiante (peut être vide).
  static List<AutoTagSuggestion> suggestions(
    List<double> scores,
    MoodStats stats,
  ) {
    if (scores.length != kMoods.length) {
      throw ArgumentError(
        '${scores.length} scores au lieu de ${kMoods.length}',
      );
    }
    if (stats.sampleCount < minLibrarySize) return const [];

    // Une ambiance qui ne discrimine rien pèse comme une ambiance moyenne (z = 0).
    final z = [
      for (var m = 0; m < kMoods.length; m++)
        stats.std[m] < _minStd
            ? 0.0
            : (scores[m] - stats.mean[m]) / stats.std[m],
    ];
    final weights = [for (final v in z) math.exp(v)];
    final total = weights.fold<double>(0, (a, b) => a + b);

    final byTag = <String, double>{};
    final qualified = <String>{};
    for (var m = 0; m < kMoods.length; m++) {
      final tag = kMoods[m].tagName;
      byTag[tag] = (byTag[tag] ?? 0) + weights[m] / total;
      if (stats.std[m] >= _minStd && z[m] >= minZScore) qualified.add(tag);
    }

    final ranked = [
      for (final tag in qualified) AutoTagSuggestion(tag, byTag[tag] ?? 0),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return ranked.take(maxTags).toList();
  }
}
