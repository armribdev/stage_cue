import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/sync/reconcile_path_matcher.dart';

/// Vérifie la désambiguïsation d'un chemin relatif périmé (fichier déplacé ou
/// renommé sur Drive) parmi des candidats partageant le même basename.
void main() {
  String? pick(String current, List<String> candidates) =>
      ReconcilePathMatcher.pickBestCandidate(current, candidates);

  test('aucun candidat → null', () {
    expect(pick('SFX/knock.mp3', const []), isNull);
  });

  test('candidat unique → toujours retenu', () {
    expect(pick('SFX/knock.mp3', const ['Ambiance/knock.mp3']),
        'Ambiance/knock.mp3');
  });

  test('correspondance exacte (insensible à la casse) l\'emporte', () {
    expect(
      pick('SFX/Knock.mp3', const ['Ambiance/knock.mp3', 'sfx/knock.mp3']),
      'sfx/knock.mp3',
    );
  });

  test('doublons stricts (même chemin, casse différente) → indécidable', () {
    expect(
      pick('SFX/knock.mp3', const ['SFX/knock.mp3', 'sfx/KNOCK.mp3']),
      isNull,
    );
  });

  test('choisit le candidat au dossier parent le plus proche', () {
    expect(
      pick(
        'SFX/Portes/knock.mp3',
        const ['Décor/SFX/Portes/knock.mp3', 'Ambiance/knock.mp3'],
      ),
      'Décor/SFX/Portes/knock.mp3',
    );
  });

  test('similarité de parent strictement unique tranche', () {
    expect(
      pick(
        'A/B/C/hit.wav',
        const ['X/B/C/hit.wav', 'Y/C/hit.wav'],
      ),
      'X/B/C/hit.wav', // partage [B, C] (2) contre [C] (1)
    );
  });

  test('égalité de similarité au sommet → null (pas de choix hasardeux)', () {
    expect(
      pick(
        'SFX/knock.mp3',
        const ['A/SFX/knock.mp3', 'B/SFX/knock.mp3'],
      ),
      isNull, // les deux partagent [SFX] (1) : indécidable
    );
  });

  test('aucun segment de dossier commun → null', () {
    expect(
      pick(
        'SFX/knock.mp3',
        const ['Ambiance/knock.mp3', 'Musique/knock.mp3'],
      ),
      isNull,
    );
  });

  test('chemin racine (sans dossier) avec candidats en sous-dossiers → null',
      () {
    expect(
      pick('knock.mp3', const ['A/knock.mp3', 'B/knock.mp3']),
      isNull,
    );
  });
}
