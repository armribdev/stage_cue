# 0021 — Synchronisation incrémentale par `changes.list`, avec repli systématique

**Statut :** acceptée
**Date :** 2026-07-30

## Contexte

Après [0018](0018-journalisation-wal-et-synchronous-normal.md), [0019](0019-parcours-drive-parallele-borne.md) et [0020](0020-sonde-de-pull-groupee-et-jeton-de-manifest.md), le lancement d'une bibliothèque de 2000 sons était retombé de ~85 s à ~6 s, dont ~4,7 s pour reparcourir intégralement une arborescence qui, la plupart du temps, n'a pas bougé d'un fichier. `changes.list` permet de ne demander que le delta.

Le gain marginal est réel mais nettement plus faible que celui des étapes précédentes, alors que le risque est le plus élevé de la série : ce chemin décide de supprimer des sons et des fichiers de cache, et ses défaillances sont silencieuses. La décision a été prise en connaissance de cet arbitrage.

## Décision

Un chemin incrémental (`LibraryRepository.applyDriveChanges`) essayé avant le scan complet, construit autour d'une règle non négociable : **il n'élague jamais par différence d'ensembles, et se déclare insuffisant au moindre doute.**

Il retourne `DriveSyncNeedsFullScan` — qui n'est pas un échec mais le mode dégradé attendu — dans tous ces cas :

- aucun jeton de reprise (première fois, ou jeton invalidé) ;
- dernier scan complet plus vieux que `_fullScanInterval` (7 jours) ;
- jeton expiré (410 Gone) ;
- changement portant sur un **dossier** : le delta ne porte pas la descendance, appliquer un renommage laisserait toute une branche avec des chemins faux ;
- fichier audio dont le dossier parent n'a pas de nœud local ;
- Drive ne renvoie pas de `newStartPageToken`.

Suivi en base (schéma v37) : `libraries.drive_change_token` et `libraries.last_full_scan_at`.

## Alternatives écartées

- **Élaguer par différence depuis le delta** — le piège central, et la raison d'être de tout le reste. Un delta ne dit pas ce qui existe, seulement ce qui a bougé : appliquer `pruneSoundsAbsentFromDrive` sur un delta supprimerait tout ce qui n'a **pas** changé, c'est-à-dire la bibliothèque entière. C'est aussi pourquoi `presentDriveFileIds` n'est alimenté que par un scan complet, et pourquoi le ré-élagage post-pull de [0005](0005-ordre-de-synchronisation-au-lancement.md) est naturellement sauté sur ce chemin.
- **Ignorer silencieusement un fichier dont le parent est inconnu** — c'était la première implémentation, et un test l'a rattrapée : un son ajouté sur Drive dans un dossier neuf serait resté invisible jusqu'au rescan périodique, soit jusqu'à une semaine. Un scan complet de trop coûte quelques secondes ; un son manquant en représentation coûte bien plus.
- **Appliquer les renommages de dossier incrémentalement** — il faudrait re-dériver les chemins de tout le sous-arbre à partir d'un événement qui ne porte que le dossier. Faisable, mais c'est exactement le genre de reconstruction dont une erreur se solde par des chemins faux en masse.
- **Se passer du rescan périodique** — un système qui ne se corrige jamais accumule sa dérive indéfiniment. Les 7 jours bornent le pire cas.

## Conséquences

- **`applyDriveChanges` ne doit jamais appeler `pruneSoundsAbsentFromDrive`**, ni aucune suppression par différence. Les seules suppressions admises passent par `deleteLibrarySoundsByDriveFileIds`, c'est-à-dire des identités que Drive a explicitement signalées disparues. Verrouillé par le test « AUCUN élagage par différence : un delta vide ne supprime RIEN ».
- **Le jeton de départ se prend AVANT le scan complet, jamais après.** Pris après, un fichier modifié pendant le scan serait absent à la fois du scan (déjà passé sur son dossier) et du premier delta (antérieur au jeton) : perdu jusqu'au rescan périodique.
- **Le nouveau jeton ne s'écrit qu'après application complète du delta.** Une interruption avant ce point fait rejouer le même delta au lancement suivant — sans effet, les règles de rapprochement étant idempotentes. L'ordre inverse perdrait des changements.
- Toutes les pages sont collectées avant d'appliquer quoi que ce soit : un delta à moitié appliqué serait pire que pas de delta.
- Ajouter un dossier sur Drive provoque un scan complet au lancement suivant. C'est voulu. Ne pas « optimiser » ce cas en remontant la chaîne des parents sans mesurer d'abord qu'il pèse réellement.
- Les ajouts et modifications passent par `syncLibrarySoundsFromDriveIndex`, donc par les **mêmes** règles que l'indexation complète (identité forte, adoption par chemin, invalidation des dérivés sur md5 changé). Ne pas réimplémenter ces règles pour le chemin incrémental.
- Le flux `changes.list` couvre tout ce que l'app peut voir, pas une seule bibliothèque : filtrer les suppressions sur les identités réellement connues de la bibliothèque traitée.
