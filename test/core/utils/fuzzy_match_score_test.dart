import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/utils/string_utils.dart';

/// Classe une liste de textes par pertinence décroissante pour une requête,
/// en ignorant ceux qui ne matchent pas (helper de test).
List<String> _rank(List<String> texts, String query) {
  final q = normalizeForSearch(query);
  final scored = <(String, int)>[];
  for (final t in texts) {
    final s = fuzzyMatchScore(normalizeForSearch(t), q);
    if (s != null) scored.add((t, s));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final e in scored) e.$1];
}

void main() {
  group('fuzzyMatchScore', () {
    test('requête vide -> score neutre (tout matche)', () {
      expect(fuzzyMatchScore('porte', ''), 0);
    });

    test('aucune correspondance -> null', () {
      expect(fuzzyMatchScore('porte', 'xyz'), isNull);
    });

    test('le préfixe bat le début de mot qui bat la sous-chaîne', () {
      final prefixe = fuzzyMatchScore('tonnerre', 'ton')!;
      final motDebut = fuzzyMatchScore('gros tonnerre', 'ton')!;
      final sousChaine = fuzzyMatchScore('piston', 'ton')!;
      expect(prefixe, greaterThan(motDebut));
      expect(motDebut, greaterThan(sousChaine));
    });

    test('sous-séquence dispersée matche mais score plus bas qu\'une sous-chaîne',
        () {
      final sousChaine = fuzzyMatchScore('porte', 'por')!;
      final dispersee = fuzzyMatchScore('pomme rouge', 'por')!; // p..o..r
      expect(dispersee, isNotNull);
      expect(sousChaine, greaterThan(dispersee));
    });

    test('normalisation des accents : "tele" matche "Télé"', () {
      expect(
        fuzzyMatchScore(normalizeForSearch('Téléphone'),
            normalizeForSearch('tele')),
        isNotNull,
      );
    });

    test('classement réaliste : préfixe exact en tête', () {
      final ranked = _rank(
        ['Grosse porte', 'Porte qui claque', 'Aéroport', 'Sirène'],
        'porte',
      );
      expect(ranked.first, 'Porte qui claque');
      expect(ranked.contains('Sirène'), isFalse); // ne matche pas
    });

    test('lettres interverties -> matche quand même (tolérance de faute)', () {
      expect(fuzzyMatchScore('explosion', 'epxlosion'), isNotNull);
    });

    test('substitution d\'une lettre -> matche quand même', () {
      expect(fuzzyMatchScore('tonnerre', 'tonnarre'), isNotNull);
    });

    test('mot trop court -> pas de tolérance aux fautes', () {
      // "ton" a 3 lettres : sous le seuil, pour éviter les faux positifs.
      expect(fuzzyMatchScore('ton', 'tno'), isNull);
    });

    test('trop de fautes -> ne matche pas', () {
      expect(fuzzyMatchScore('explosion', 'xpsloin'), isNull);
    });

    test('faute de frappe : score entre sous-chaîne et sous-séquence', () {
      final substring = fuzzyMatchScore('grosse explosion', 'explosion')!;
      final typo = fuzzyMatchScore('grosse explosion', 'epxlosion')!;
      expect(substring, greaterThan(typo));
    });
  });

  group('buildHighlightedSpan (via fuzzyMatchScore + surlignage approximatif)', () {
    test('une faute de frappe met en évidence la fenêtre correspondante', () {
      final span = buildHighlightedSpan('Grosse Explosion', ['epxlosion']);
      final bold = <String>[];
      void collect(InlineSpan s) {
        if (s is TextSpan) {
          if (s.style?.fontWeight == FontWeight.bold && s.text != null) {
            bold.add(s.text!);
          }
          s.children?.forEach(collect);
        }
      }
      collect(span);
      expect(bold, isNotEmpty);
      expect(bold.first.toLowerCase(), 'explosion');
    });
  });
}
