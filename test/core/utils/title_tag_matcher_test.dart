// Appariement titre → tags (décision 0041) : mots entiers, accents, pluriels,
// expressions multi-mots, mots ambigus.

import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/utils/title_tag_matcher.dart';

const _animal = 1;
const _sonnerie = 2;
const _porte = 3;
const _bo = 4;
const _bar = 5;
const _rire = 6;
const _vehicule = 7;
const _arme = 8;
const _marcher = 9;
const _remix = 10;

TitleTagMatcher _matcher() => TitleTagMatcher(const [
  TagVocabularyEntry(
    tagId: _animal,
    phrases: ['Animal', 'dog', 'chien', 'turkey', 'gobble', 'oiseau'],
  ),
  TagVocabularyEntry(
    tagId: _sonnerie,
    phrases: ['Sonnerie', 'sonette', 'ring'],
  ),
  TagVocabularyEntry(tagId: _porte, phrases: ['Porte']),
  TagVocabularyEntry(
    tagId: _bo,
    phrases: ['BO', 'ost', 'bande originale', 'theme'],
  ),
  TagVocabularyEntry(tagId: _bar, phrases: ['Bar', 'taverne']),
  TagVocabularyEntry(tagId: _rire, phrases: ['Rire', 'rire']),
  TagVocabularyEntry(tagId: _vehicule, phrases: ['Véhicule', 'train', 'bus']),
  TagVocabularyEntry(tagId: _arme, phrases: ['Arme', 'machine gun', 'gun']),
  TagVocabularyEntry(tagId: _marcher, phrases: ['Marcher', 'pas', 'steps']),
  TagVocabularyEntry(tagId: _remix, phrases: ['Remix', 'mix']),
]);

List<int> _ids(String title, {Set<int> excluded = const {}}) =>
    _matcher().suggest(title, excluded: excluded).map((m) => m.tagId).toList();

void main() {
  group('mots entiers', () {
    test('« bar » n’est pas dans « Barbara »', () {
      expect(_ids('Barbara - Nantes'), isEmpty);
      expect(_ids('Bar de nuit'), [_bar]);
    });

    test('« ring » n’est pas dans « Spring »', () {
      expect(_ids('Spring Waltz'), isEmpty);
      expect(_ids('office phone ring'), [_sonnerie]);
    });

    test('un mot collé à un autre ne compte pas', () {
      expect(_ids('dogma'), isEmpty);
      expect(_ids('hotdog'), isEmpty);
    });
  });

  group('séparateurs et casse', () {
    test('tiret et souligné séparent les mots (nom de fichier)', () {
      expect(_ids('dog-barking-70772'), [_animal]);
      expect(_ids('turkey_gobble_02'), [_animal]);
    });

    test('un titre de la bibliothèque : « Sonette porte »', () {
      expect(_ids('Sonette porte'), [_sonnerie, _porte]);
    });

    test('« Turkey Gobble » : un seul tag malgré deux mots', () {
      final matches = _matcher().suggest('Turkey Gobble');
      expect(matches.map((m) => m.tagId), [_animal]);
      expect(matches.single.matchedText, 'Turkey');
    });

    test('la casse est ignorée', () {
      expect(_ids('PORTE'), [_porte]);
    });

    test('l’apostrophe sépare : « l’oiseau »', () {
      expect(_ids('Le Roi et l’Oiseau'), [_animal]);
    });
  });

  group('accents', () {
    test('accents ignorés des deux côtés', () {
      expect(_ids('vehicule'), [_vehicule]);
      expect(_ids('VÉHICULE'), [_vehicule]);
    });
  });

  group('pluriels simples', () {
    test('« rires » désigne « rire », « chiens » désigne « chien »', () {
      expect(_ids('rires'), [_rire]);
      expect(_ids('Chiens errants'), [_animal]);
    });

    test('un mot de trois lettres en s n’est pas écorché : « bus »', () {
      expect(_ids('bus'), [_vehicule]);
    });
  });

  group('expressions multi-mots', () {
    test('« bande originale » désigne BO', () {
      expect(_ids('Bande Originale du film'), [_bo]);
    });

    test('l’expression prime sur ses mots isolés : « machine gun »', () {
      final matches = _matcher().suggest('Machine gun');
      expect(matches.map((m) => m.tagId), [_arme]);
      expect(matches.single.matchedText, 'Machine gun');
    });

    test('une expression incomplète ne déduit rien', () {
      expect(_ids('bande'), isEmpty);
    });
  });

  group('mots ambigus', () {
    test('ils ne déduisent rien d’un titre', () {
      expect(_ids('Ne me quitte pas'), isEmpty);
      expect(_ids('James Bond Theme'), isEmpty);
      expect(_ids('Animal Rap Gatti Mix'), [_animal]);
      expect(kAmbiguousTitlePhrases, containsAll(['pas', 'theme', 'mix']));
    });

    test('« steps » reste valide quand « pas » est ignoré', () {
      expect(_ids('footsteps steps'), [_marcher]);
    });

    test('la liste est un paramètre : sans elle, ces mots déduisent', () {
      final matcher = TitleTagMatcher(const [
        TagVocabularyEntry(tagId: _marcher, phrases: ['pas']),
      ], ambiguousPhrases: const {});
      expect(matcher.suggest('Ne me quitte pas').single.tagId, _marcher);
    });
  });

  group('sélection', () {
    test('les tags déjà posés sont exclus', () {
      expect(_ids('Sonette porte', excluded: {_porte}), [_sonnerie]);
    });

    test('un tag désigné deux fois n’apparaît qu’une fois', () {
      expect(_ids('chien dog chien'), [_animal]);
    });

    test('ordre d’apparition dans le titre', () {
      expect(_ids('porte puis chien'), [_porte, _animal]);
    });

    test('au plus kMaxTitleTagSuggestions, 4 par défaut', () {
      final title = 'dog ring porte ost bar rire train gun';
      expect(_matcher().suggest(title), hasLength(kMaxTitleTagSuggestions));
      expect(_matcher().suggest(title, limit: 2), hasLength(2));
    });

    test('un titre vide ou sans mot ne déduit rien', () {
      expect(_ids(''), isEmpty);
      expect(_ids(' - _ - 123 '), isEmpty);
    });

    test('un vocabulaire vide ne déduit rien', () {
      expect(TitleTagMatcher(const []).suggest('porte'), isEmpty);
    });
  });
}
