# 0022 — Veille Drive en cours de session : delta seulement, jamais de scan

**Statut :** acceptée
**Date :** 2026-07-31

## Contexte

La synchronisation ne tournait qu'au lancement ([0005](0005-ordre-de-synchronisation-au-lancement.md)). Une session de spectacle ou de répétition reste ouverte des heures : un son déposé sur Drive entre-temps n'était visible qu'après un redémarrage, ou via le bouton « Actualiser depuis Drive ». Ce bouton, de son côté, orchestrait sa **propre** séquence — pull puis scan complet systématique — c'est-à-dire l'ordre inverse de 0005 et sans le chemin incrémental de [0021](0021-synchronisation-incrementale-par-changes-list.md).

## Décision

Une **séquence unique** (`AutoSyncCoordinator._runPass`) partagée par trois déclencheurs (`SyncPassTrigger`) : lancement, actualisation manuelle, et **veille** — sonde périodique (5 min) plus une sonde au retour de l'app au premier plan.

La veille est volontairement bridée : elle applique le delta et tire les snapshots, mais **ne déclenche jamais de scan complet** et ne fait pas bouger la pastille tant qu'elle n'a rien fusionné (`SyncController.pullInBackground`). Elle se tait en Mode Spectacle, en mode local, et app en arrière-plan. Un verrou (`_passInFlight`) garantit une seule passe à la fois : une demande manuelle rejoint celle en cours.

## Alternatives écartées

- **Notifications push Drive (`files.watch`)** — la vraie détection événementielle, et impossible ici : les webhooks Google exigent un endpoint HTTPS public. Cette app est un client de bureau/mobile sans serveur ; l'introduire changerait la nature du produit.
- **Laisser la veille rescanner quand le delta se déclare insuffisant** — un scan complet, c'est des secondes de listing Drive et des écritures en masse, déclenchées par une **horloge** et non par un geste utilisateur : exactement ce qu'on ne veut pas sous une app posée sur une table de régie. La bibliothèque garde son état ; le prochain lancement ou le bouton fait le scan.
- **Tirer quand même une bibliothèque dont le delta a échoué** — le pull racine recâblerait les boards sur des sons pas encore indexés (0005). La veille saute la bibliothèque entière.
- **Réutiliser `pullForLaunch` en veille** — la pastille passerait par « Synchro… » puis « Synchronisé » toutes les 5 minutes pour dire qu'il n'y a rien à dire. Un écran de régie qui clignote sans raison est un défaut, pas une information.
- **Intervalle plus court (30 s – 1 min)** — le gain perçu est nul (personne n'ajoute un son sur Drive en attendant qu'il apparaisse à la seconde près) et le trafic est multiplié par 5 à 10 pour rien.
- **Observer le cycle de vie depuis `AutoSyncCoordinator`** — il vit dans `core/sync` et n'a aucune dépendance widget ; `SoundboardApp` (déjà `WindowListener`) rapporte l'état, le coordinateur décide.

## Conséquences

- **La veille ne rescanne jamais.** Ajouter un repli sur `indexDriveFolder` dans le chemin `watch` ferait tourner un scan complet en tâche de fond, potentiellement en pleine représentation. Verrouillé par le test « delta inexploitable : ni scan complet, ni pull ».
- **Une seule séquence.** Ne pas réintroduire d'orchestration de synchro dans un écran : le bouton « Actualiser » passe par `refreshNow`, qui retourne un `SyncPassReport`. Deux séquences pour le même travail divergent — c'est déjà arrivé une fois.
- **Le verrou est structurel, pas cosmétique.** `_ignoreUpdates` est un booléen partagé : deux passes concurrentes le verraient rabaissé par la première à finir, rouvrant les push parasites pendant que la seconde fusionne encore.
- **Une passe partielle ne s'annonce pas comme un succès** : `SyncPassReport.skipped`/`authExpired`/`error` sont distincts, parce que le cas qui compte est celui où l'utilisateur cherche un son qu'il vient d'ajouter et ne le trouve pas.
- **Le renoncement de la veille au scan est journalisé une fois par bibliothèque** ([SyncLog.watchFullScanDeferred]) : la raison est stable d'un tick à l'autre, la répéter toutes les 5 minutes rendrait le canal `StageCue.Sync` inutilisable — mais renoncer en silence laisserait croire que la veille rattrape encore quelque chose.
- La veille hérite des garanties de 0021 : elle n'élague jamais par différence d'ensembles, puisqu'elle ne fait tourner que `applyDriveChanges`.
