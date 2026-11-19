# 0044 — Volume « auto » : relèvement du gain, plafonné par le pic mesuré

**Statut :** acceptée (amende [0036](0036-volume-auto-par-sonie-lufs-selon-le-type.md) : plus de plafond à 1.0 pour la sonie) — amendée par [0045](0045-gain-unique-par-son-sans-volume.md) (le gain de sonie n'est plus un facteur séparé du volume : `sounds.gain` est le seul niveau d'un son, `volume` et `loudness_gain` n'existent plus)
**Date :** 2026-11-19

Le relèvement est voulu parce que l'appli doit rester correcte sur des bibliothèques que l'auteur n'a pas écoutées : un fichier mal normalisé ne doit pas rester inaudible sans recours. Les essais d'écoute ne sont donc pas un préalable ; ils serviront à régler les marges, pas à décider du principe.

## Contexte

[0036](0036-volume-auto-par-sonie-lufs-selon-le-type.md) mesure bien la sonie, mais le volume par son est plafonné à 1.0 : l'auto ne peut qu'atténuer. Un son plus doux que sa cible reste en dessous, et c'est celui qu'on n'entend pas en live. Pour que la plupart des fichiers tombent au-dessus de la cible, celles-ci sont posées bas (−20 LUFS en musique), ce qui sacrifie le niveau global du plateau pour compenser une limite du lecteur. Rien ne mesure non plus le pic : la sonie ne dit pas si un bruitage bref dépasse sa force perçue.

## Décision

Mesurer le pic d'échantillon du fichier en même temps que la sonie (`LoudnessMeasurement` : sonie, pic, fichier entier lu ou échantillonné), et calculer un **gain de sonie** (`sounds.loudness_gain`, ≥ 0, `null` = pas de mesure = 1.0), qui peut dépasser 1.0. Le volume utilisateur (`volume`, 0–1) et ses curseurs ne changent pas : le gain de sonie est un facteur séparé, appliqué une seule fois à la frontière de lecture (`volume_effectif = volume.clamp(0, 1) × loudness_gain`, dans le lecteur).

**Constantes** (`core/audio/loudness_analyzer.dart`) :

| Constante | Valeur | Rôle |
|---|---|---|
| `kPeakCeilingDb` | −3 dBFS | pic maximal visé après relèvement |
| `kSampledPeakMarginDb` | 3 dB | marge en plus quand le fichier n'est lu que par morceaux (> 60 s, 6 morceaux de 10 s) |
| `kMaxBoostDb` | +12 dB | relèvement maximal |
| `kAutoVolumeMin` | 0.05 | plancher d'atténuation |

**Formule** (`autoLoudnessGain`) : `g_cible = 10^((cible − lufs)/20)`. Si `g_cible ≤ 1` : gain = `g_cible` (plancher `kAutoVolumeMin`) — **le pic ne force jamais une atténuation**. Sinon : gain = `max(1, min(g_cible, 10^((plafond − marge − pic_dB)/20), 10^(12/20)))` — un pic déjà au-dessus du plafond laisse le son à 1.0 plutôt que de l'atténuer. Les cibles de `LoudnessProfile` ne changent pas. Écrire le gain remet `volume` à 1.0 (« Auto » de la fiche, recalcul en masse, indexation).

## Alternatives écartées

- **Relever le plafond de `volume` au-dessus de 1.0** — exige de modifier lecteurs, curseurs, aperçu et Cue, et mélange réglage de l'utilisateur et correction automatique (l'écart « volume réglé » de `AutoVolumePlan.customized` n'aurait plus de sens). C'était déjà l'alternative écartée par 0036.
- **Relever sans mesurer le pic** — écrête les sons déjà proches de 0 dBFS. C'est exactement ce que 0036 voulait éviter.
- **Garder l'atténuation seule et baisser encore les cibles** — rend le plateau plus faible sans régler le cas du son doux.

## Conséquences

- **Le pic n'est fiable que sur le fichier entier.** La mesure par 6 morceaux de 10 s (fichiers > 60 s) peut rater le vrai pic. Plutôt que d'interdire le relèvement de la musique longue (règle d'abord envisagée) ou d'exiger un décodage complet (≈ 3 s pour 5 min sur la file de l'[ADR 0001](0001-chargement-audio-soloud.md)), le plafond de pic prend **3 dB de marge de plus** sur un fichier échantillonné. Choix à confirmer à l'oreille.
- **Pic d'échantillon, pas true-peak.** Le true-peak (suréchantillonnage ×4, BS.1770-4) est plus exact mais plus cher ; le plafond de −3 dBFS tient lieu de marge.
- **Pic du canal gauche seul.** Le décodeur d'analyse (`readLeftChannelWindow`, `readSamplesFromFile` détourné) ne rend que le premier canal de chaque trame : aucune lecture des deux canaux n'est possible sans le remplacer. Un fichier plus fort à droite a un pic sous-estimé ; le plafond de −3 dBFS est la seule marge. Même limite que la sonie (0036).
- **Schéma (v49) :** colonne nullable `sounds.loudness_gain`, `null` pour les sons existants (aucun ne change de niveau tout seul). Elle voyage dans le snapshot de dossier comme `volume` ; un snapshot sans la colonne (appareil en v48) s'importe avec un gain `null`, sans erreur ni journal. Un appareil en retard ignore la colonne : le son y joue au volume seul.
- **Application :** `PreviewPlayback.setLoudnessGain`, posé sur chaque lecteur (pads : `_syncPadSoundMetadata` ; aperçu : au chargement et à chaque départ). `AudioPlayerService._engineVolume` et `CuePreviewPlayer._mpvVolume` sont les seuls endroits où le gain se multiplie, y compris pour les fondus (`setVolume` à ~60 fps) et `fadeVolumeTo`. Le volume master et le volume par pad restent indépendants.
- **Vérifié dans les sources (flutter_soloud 4.0.12 verrouillé, media_kit 1.2.6) :**
  - *Salle (SoLoud).* Le natif n'écrête pas le volume d'une voix : `setVoiceVolume_internal` stocke la valeur telle quelle et la multiplie dans le mixage. « 0.0 à 1.0 » n'est qu'une consigne de la doc Dart. Le seul plafond est celui de l'app : `volume.clamp(0.0, 1.0)` dans `audio_player_service.dart` (démarrage de voix, ligne ~140, et `setVolume`, ligne ~279, que les fondus appellent à ~60 fps). Le gain de sonie se multiplie donc à cet endroit, après le clamp du volume utilisateur.
  - *Casque (Cue).* `cue_audio_service.dart` clampe aussi à 1.0 puis envoie `× 100` à mpv. `media_kit` ne fixe pas `volume-max` : mpv garde son défaut (130, d'après ma connaissance de mpv, non relu dans cette installation), soit +2,3 dB au maximum, puis écrête en silence. Le relèvement côté casque serait donc borné, sauf à régler `volume-max` à l'initialisation du lecteur. **Fait :** `CuePreviewPlayer.create` règle `volume-max` à 399 % (+12 dB) via `NativePlayer.setProperty` ; un échec est journalisé une fois (`warnOnce`) et laisse le casque borné à 130 %. *Non vérifié à l'exécution* : que mpv accepte bien `volume-max` posé après création du lecteur.
  - *Écrêtage de la salle.* `flutter_soloud` initialise SoLoud avec les drapeaux à `0` et `setPostClipScaler(1.0)` (`player.cpp`) : l'arrondi doux `CLIP_ROUNDOFF` est donc **désactivé**, et la somme des voix est écrêtée net à 0 dBFS (distorsion numérique), sans réglage exposé côté Dart. Le risque existe déjà aujourd'hui (musique et bruitage à 1.0 en même temps) ; un relèvement l'aggrave. Le plafond de pic par son ne protège pas la somme des voix : prévoir une marge franche (≈ −3 dBFS, pas −1) et ne relever que les bruitages et l'ambiance dans un premier temps.
  - *Non vérifié :* le rendu réel à l'oreille (un bruitage relevé de 6 dB joué par-dessus une musique). Un essai à l'écoute reste nécessaire avant d'accepter.
- **Migration des volumes existants :** les sons déjà indexés ont un `volume` qui encode l'ancienne atténuation et un `loudness_gain` à `null`. Pas de conversion automatique : le recalcul explicite (« Recalculer les volumes auto ») écrit le gain et remet `volume` à 1.0 ; il annonce déjà combien de volumes réglés il remplace. Tant qu'il n'a pas tourné, un son garde exactement son niveau d'avant.
- Fait : 0036 amendée, règle « plafonné à 1.0 » de `.claude/rules/audio.md` remplacée, index du README, schéma v49 dans `CLAUDE.md`.
- **Hors périmètre ici :** lecture des deux canaux, point d'entrée de lecture, réglage global de cible. Ils se décident séparément.
