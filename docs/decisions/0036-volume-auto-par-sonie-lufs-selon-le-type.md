# 0036 — Volume « auto » : sonie LUFS pondérée K, cible selon le type

**Statut :** acceptée
**Date :** 2026-11-11

## Contexte

Le volume « auto » ramenait chaque son à −20 dBFS de RMS brute, moyennée sur toute la durée, avec une cible unique. Cette mesure ne correspond pas à la force perçue : elle ignore la sensibilité de l'oreille (les graves pèsent trop, les aigus pas assez), et pour un bruitage elle dépend de la durée de la queue ou du silence autour de l'attaque. Le volume par son est plafonné à 1.0 : l'auto ne peut qu'atténuer.

## Décision

La sonie se mesure en LUFS (pondération K, blocs de 400 ms, portes absolue −70 LUFS et relative −10 LU, ITU-R BS.1770-4) sur le canal gauche, avec une cible par type : musique −20 LUFS intégrée, ambiance −26 LUFS intégrée, bruitage −16 LUFS en maximum court terme (`LoudnessProfile`). Le plafond de volume reste 1.0.

## Alternatives écartées

- **Garder la RMS et ajuster la cible** — ne corrige ni la pondération ni la dépendance à la queue d'un bruitage.
- **Autoriser un volume > 1.0 pour relever les sons doux** — exige de mesurer le pic réel pour ne pas écrêter, et de relever le plafond partout (lecteurs, sliders, prévisualisation, Cue). Écarté pour l'instant ; les cibles sont posées bas pour que la plupart des fichiers soient au-dessus et donc ramenés à la cible.
- **Mesurer avec `SoLoud.readSamplesFromFile(average: true)`** — l'API Dart fuit ses tampons natifs (voir [0029](0029-analyse-automatique-des-tags-sur-l-appareil.md)) et ne donne que des RMS de fenêtres, pas le signal.

## Conséquences

- La mesure passe par `measureAutoVolume` (`core/audio/loudness_analyzer.dart`), qui décode avec `readLeftChannelWindow` (tampons libérés, file de décodage native de l'[ADR 0001](0001-chargement-audio-soloud.md)). Elle n'est plus un sous-produit de `extractWaveform` : un nouveau chemin d'indexation doit l'appeler après avoir déterminé le type.
- Fichier de plus de 60 s : 6 morceaux de 10 s répartis de bout en bout, pas le fichier entier.
- Un son plus doux que sa cible garde 1.0 et reste en dessous. L'égalisation n'est complète que vers le bas.
- Le canal gauche seul est mesuré (limite du décodeur détourné) : un fichier panoramique dur à droite est sous-estimé.
- Les valeurs de cible sont des points de départ à régler à l'oreille. Les sons déjà indexés gardent leur volume tant qu'on ne relance pas la mesure : bouton « auto » de la fiche d'un son, ou Paramètres → Volumes → « Recalculer les volumes auto » (`LibraryRepository.recomputeAutoVolumes`). Ce dernier ne mesure que les sons déjà téléchargés, demande confirmation en annonçant combien de volumes réglés il remplace, écrit son par son (annulable sans perte) et est indisponible en Mode Spectacle.
