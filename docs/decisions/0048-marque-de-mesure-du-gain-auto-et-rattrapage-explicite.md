# 0048 — Marque de mesure du gain auto, rattrapage explicite des sons anciens

**Statut :** acceptée (précise 0044 : « aucun son ne change de niveau tout seul » reste vrai)
**Date :** 2026-11-19

## Contexte

Le gain auto est mesuré à la création d'un son, au premier fichier d'un son Drive et avec la première waveform ([0036](0036-volume-auto-par-sonie-lufs-selon-le-type.md), [0044](0044-volume-auto-releve-plafonne-par-le-pic.md)). Un son indexé avant ces mesures, ou dont la waveform a seulement été régénérée, garde `gain = 1.0` sans que rien ne le distingue d'un son réglé volontairement à 0 dB : l'app ne pouvait ni le signaler, ni le rattraper sans écraser un réglage. La waveform, elle, se rattrape seule par `kWaveformProbeGeneration` ; les suggestions de tags aussi (colonnes nulles = candidat). *(Inexact pour la waveform : la génération ne fait que désigner les sons, rien ne les revisitait — corrigé par [0049](0049-rattrapage-des-waveforms-et-recalcul-de-maintenance-debug.md).)*

## Décision

`sounds.gain_measure_generation` (v51, nullable, annotation **locale** : absente du snapshot) reçoit `kGainMeasureGeneration` avec **chaque gain mesuré par l'app** (création, premier fichier, première waveform, « Auto » de la fiche enregistré tel quel, recalcul en masse). Un son à `gain = 1.0` **et** génération `null` est « jamais mesuré ». Rien ne change tout seul : Réglages → Maintenance → Gain auto annonce ce nombre et propose « Non mesurés seulement », qui ne touche à aucun gain réglé, à côté de « Tout recalculer ».

## Alternatives écartées

- **Rattrapage automatique en tâche de fond** — contredit 0044 : une passe silencieuse changerait le niveau de sons que l'opérateur a peut-être calés à la main, hors Mode Spectacle certes, mais avant un spectacle qu'il croit réglé.
- **Se fier à `gain == 1.0` seul** — indiscernable d'un 0 dB voulu ; les sons non mesurables (silence, format) seraient aussi reproposés indéfiniment.
- **Colonne synchronisée dans le snapshot** — un appareil qui importe un gain ≠ 1.0 n'a pas besoin de la marque ; un 1.0 reçu se remesure au pire une fois, sur demande. Pas de format de snapshot à faire évoluer.
- **Versionner dès maintenant l'empreinte de tags IA** — un seul pack existe (`autotag-pack-1`). Le sort des sons traités, des suggestions déjà posées et des statistiques de recentrage ne se décide qu'avec le vrai second modèle : voir la règle ajoutée à `.claude/rules/autotag.md`.

## Conséquences

- Écrire un gain mesuré sans `gainMeasureGeneration` (ou l'inverse : marquer un son dont la mesure a échoué) casse le décompte. Les écritures passent par `_measuredGeneration` (datasource) ou `updateSoundSettings(gainMeasured: true)`.
- Un réglage à la main (curseur) n'écrit pas la marque ; retoucher le curseur après « Auto » l'annule (`SoundEditForm._gainMeasured`). Cas limite accepté : un son jamais mesuré réglé à la main sur exactement 1.0 reste compté.
- Changer une cible de `LoudnessProfile` ou la formule d'`autoLoudnessGain` : incrémenter `kGainMeasureGeneration`. Rien ne ré-estampille alors les sons déjà marqués ; le décompte « jamais mesurés » ne les reprend pas, « Tout recalculer » reste le rattrapage. Étendre le décompte aux générations antérieures est possible, mais seulement le jour où la formule change.
- Contenu Drive écrasé en place (`contentChanged`) : la marque n'est pas effacée, comme le gain.
