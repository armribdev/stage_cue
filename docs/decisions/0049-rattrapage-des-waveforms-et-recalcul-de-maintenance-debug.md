# 0049 — Rattrapage de fond des waveforms, recalcul de maintenance réservé au debug

**Statut :** acceptée (corrige une affirmation de 0048 ; 0048 reste vraie pour le gain)
**Date :** 2026-11-19

## Contexte

[0048](0048-marque-de-mesure-du-gain-auto-et-rattrapage-explicite.md) disait que la waveform « se rattrape seule par `kWaveformProbeGeneration` ». C'était faux : la génération ne fait que **désigner** les sons à refaire ; le calcul ne part que sur un événement — fichier téléchargé, son résolu pour la lecture (`resolvePlayablePath`), pad chargé. Un son dont le fichier était déjà en cache avant ces événements, ou dont type et hash sont arrivés par le snapshot Drive d'un autre appareil, n'est jamais revisité. Constat sur une vraie base : 1009 sons sur 1200 sans waveform ni génération, 179 en génération 2 (courante : 3), tous les fichiers pourtant présents.

Deux pièges empêchaient de simplement « tout repasser par `resolvePlayablePath` » :

- `resolvePlayablePath` lance `materializeSoundFileMetadata`, qui **mesure le gain** d'un son encore à 1.0 avec sa première waveform. Une passe de masse changerait donc silencieusement des niveaux — exactement ce que 0048 interdit.
- `persistWaveformProbe` fait de même (gain « première waveform »).

## Décision

1. **Rattrapage de fond des waveforms** (`LibraryRepository.backfillStaleWaveforms`, orchestré par `AutoSyncCoordinator`). Après chaque passe de synchro, tick de veille ou retour au premier plan, les sons **déjà sur l'appareil** dont l'enveloppe manque ou date d'une génération obsolète (`waveformNeedsProbe`) sont recalculés, **avant** l'analyse des tags (elles décodent la même file native). Mêmes garde-fous que l'analyse : arrêt en Mode Spectacle, en arrière-plan, pendant une synchro ; ne télécharge rien ; ne retient jamais un « Actualiser ». Un moteur audio pas prêt arrête la passe sans rien mémoriser.
2. **Aucun gain n'est écrit par ces passes.** `persistWaveformProbe` reçoit `measureGain` (vrai par défaut : les chemins « première waveform » existants ne changent pas) ; le rattrapage et le recalcul le passent à faux, et lisent le fichier directement (`_existingLocalFile`) sans passer par `resolvePlayablePath`. Le gain reste régi par 0048 : mesure à la demande.
3. **Recalcul de maintenance, build debug seulement** (Réglages → Maintenance → « Recalcul », absent d'une release comme l'éditeur de catalogue, [0047](0047-editeur-de-catalogue-de-tags-debug-qui-produit-le-code.md)). On coche ce qui est recalculé, sur les sons téléchargés, l'un après l'autre, annulable, écriture au fil de l'eau :
   - **Waveforms** : toutes, sans toucher au gain ;
   - **Gain auto** : remplace les gains réglés (le comptage est affiché) — c'est le rattrapage explicite de 0048, étendu à « tout » ;
   - **Suggestions de tags** : `LocalAutoTagDataSource.reopenAnalysis` efface suggestions et marque de décision des musiques non traitées **qui ont une empreinte**, puis `requestAutoTag` ; l'analyse normale refait la décision (`applyDecisions` insère puisque les lignes ont disparu, sans changer ses règles) ;
   - **Empreintes audio** : idem, plus l'effacement de l'empreinte (ré-analyse de l'audio, long) ; refusé sans le pack de modèles, car l'effacement serait irréversible.

## Alternatives écartées

- **Rattraper aussi le gain dans la passe de fond** — contredit 0048 et 0044 (« aucun son ne change de niveau tout seul »). Le recalcul de maintenance est le chemin explicite.
- **Rattraper via `resolvePlayablePath`** — écrit des gains en douce (voir Contexte), et double le travail avec la tâche de fond qu'il lance.
- **Étendre `materializeSoundFileMetadata` pour rafraîchir les enveloppes obsolètes** — ne couvre que les sons résolus, donc jamais les 1009 qui n'ont aucun événement.
- **Recalcul de maintenance en release** — il écrase des gains réglés à la main et efface des empreintes : outil de développeur, pas de réglage d'opérateur.
- **Réécrire les suggestions en place (upsert)** plutôt que supprimer puis recalculer — ne change rien à la synchro (voir Conséquences) et obligerait à assouplir « une ligne existante n'est jamais modifiée par l'analyse ».

## Conséquences

- Le rattrapage écrit dans `sounds` : il passe par le compteur `_annotationWriters` du coordinateur (comme l'analyse des tags) pour ne pas déclencher un push pour chaque son ; un push final rattrape les éditions ignorées pendant la passe. `backfillStaleWaveforms` est une **méthode d'instance** du repository (pas une extension) pour que le coordinateur se teste avec un faux.
- Un rattrapage tourne au plus une fois à la fois ; si un rattrapage est en vol, les passes de synchro suivantes n'ouvrent pas l'analyse : elle s'enchaîne à sa fin. Une demande explicite (`requestAutoTag`, fiche d'un son) reste immédiate.
- **Limite du recalcul des suggestions** : la synchro fusionne `sound_auto_tags` par union, sans jamais supprimer. Les nouvelles suggestions (plus récentes) l'emportent, mais d'anciennes suggestions qu'un autre appareil possède encore peuvent revenir au prochain pull. Le recalcul ajoute et corrige, il ne retire pas de façon durable.
- Un son traité n'est jamais rouvert ; `sound_tags` (tags de l'utilisateur) n'est jamais touché ([autotag.md](../../.claude/rules/autotag.md)).
- Les 37 sons sans type connu reçoivent leur waveform mais gardent `type = null` jusqu'à leur premier chargement (`materializeSoundFileMetadata`, qui reste le seul chemin posant le type, le hash et le gain de premier fichier).
