# 0045 — Un seul niveau par son : le gain, réglé dans la bibliothèque

**Statut :** acceptée (amende [0044](0044-volume-auto-releve-plafonne-par-le-pic.md) : le gain de sonie n'est plus un facteur séparé du réglage de l'utilisateur, il en est la seule valeur)
**Date :** 2026-11-19

## Contexte

Un son avait trois niveaux : `sounds.volume` (curseur « Volume par défaut » de la fiche, 0–1), `sounds.loudness_gain` (gain « auto » de [0044](0044-volume-auto-releve-plafonne-par-le-pic.md), invisible, jusqu'à +12 dB) et `pad_sounds.volume` (curseur par son dans la fiche d'un pad). Le niveau entendu était `override ?? volume`, × `loudness_gain`. L'opérateur réglait donc le même son à trois endroits, et « Auto » remettait `volume` à 1.0 pour ne pas empiler les deux.

## Décision

Un son n'a qu'**un** niveau propre, le **gain** (`sounds.gain`, facteur linéaire ≥ 0, `1.0` = le fichier tel quel). Il se règle **uniquement** dans la fiche du son de la bibliothèque, en dB (curseur −24 à +12 dB, pas de 0,5 dB, `core/audio/gain.dart`) ou par « Auto » (la sonie mesurée, 0036 et 0044). Plus aucun volume par son ailleurs : le pad, la régie et l'aperçu jouent le son à son gain, sans pouvoir le changer. `Sound.volume`, `Sound.loudnessGain`, `Pad.soundVolumes`, `Pad.effectiveVolume`, `updatePadSoundVolume` et le curseur de `PadSoundRow` disparaissent.

Le gain reste appliqué **une seule fois, à la frontière de lecture** (`PreviewPlayback.setGain`, anciennement `setLoudnessGain`). Les appelants ne manipulent que le volume 0–1 de la **voie** et des fondus (`SamplerNotifier._busVolume` : voie musique ou ambiance, 1.0 pour un bruitage).

## Alternatives écartées

- **Garder le volume par pad** — c'est ce que le changement supprime : un son se règle en un seul endroit, la bibliothèque.
- **Gain nullable (`null` = pas mesuré), comme `loudness_gain`** — chaque lecture aurait un `?? 1.0`, pour une distinction qui n'a plus d'usage hors du premier téléchargement d'un son Drive (voir conséquences).
- **Gain en pourcentage, 0–400 %** — l'échelle de l'ancien volume étirée au-delà de 100 % ; un gain se pense en dB, et la borne haute (+12 dB) est celle du lecteur du casque.
- **Plancher à −∞ (muet)** — le curseur s'arrête à −24 dB. Un son déjà à 0 (ancien volume 0) reste muet tant qu'on n'y touche pas, le curseur l'affiche à −24 dB.

## Conséquences

- **Schéma v50.** `sounds.gain` (`REAL NOT NULL DEFAULT 1.0`) remplace `volume` et `loudness_gain` ; `pad_sounds.volume` est supprimée. Migration : `gain = volume × COALESCE(loudness_gain, 1.0)` — chaque son garde exactement son niveau — puis `DROP COLUMN`. **Les volumes propres à un son dans un pad sont perdus** : un son y retombe sur le gain de la bibliothèque. Les anciennes migrations qui recréent `sounds` (v23, v40) passent par `_soundsRecreation`, qui calcule `gain` depuis `volume` : un upgrade ancien ne perd pas les niveaux.
- **Synchro.** Le snapshot de dossier publie `gain`, **et encore `volume` (= 1.0) et `loudness_gain` (= gain)** : l'import d'un appareil en v49 lit `volume` sans garde et ferait échouer le pull ; `volume × loudness_gain` y donne exactement le gain. À retirer quand plus aucun appareil n'est en v49. À l'import, un snapshot sans `gain` (v49 ou avant) donne `volume × loudness_gain`. `pad_sounds.volume` n'est plus publiée ni lue.
- **Un gain à exactement 1.0 est indiscernable d'un gain jamais touché.** `materializeSoundFileMetadata` ne remesure le gain « auto » d'un son Drive, au premier fichier réel, que s'il vaut 1.0 : un gain réglé à 0 dB avant ce premier téléchargement est remesuré une fois. Cas limité (le type est connu juste après), accepté contre un `NULL` à propager partout.
- **Waveform de la fiche.** Elle est mise à l'échelle du gain (`min(1, 10^(dB/20))`) : elle reste pleine hauteur à partir de 0 dB, un relèvement ne se voit que sur le nombre.
- **« Auto » et le recalcul en masse** n'ont plus de volume à remettre à 1.0. Le recalcul remplace le gain des sons déjà réglés (≠ 1.0), réglés à la main ou par un « Auto » précédent, et l'annonce avant d'écrire.
- **Le bouton « Masquer les volumes » de la fiche d'un pad** (un état qui ne commandait rien) est retiré avec les curseurs.
- **Non vérifié :** le rendu à l'oreille d'un gain relevé de plusieurs dB sur un bruitage joué sur une musique (même réserve que 0044), et la fiche à l'écran (curseur en dB, glissement entre deux sons).
