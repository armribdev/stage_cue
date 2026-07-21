# 0003 — Snapshots par-dossier + racine, et fusion board-par-board non destructive

**Statut :** acceptée
**Date :** 2026-07-21 *(décision antérieure, consignée rétroactivement)*

## Contexte

Une bibliothèque Drive peut être partagée entre plusieurs régisseurs travaillant simultanément sur des scènes différentes. Un snapshot unique de toute la bibliothèque, fusionné par écrasement, faisait perdre le travail de celui qui poussait en second.

## Décision

Deux niveaux de snapshot indépendants — un par **nœud dossier** (`library.db` : les sons du dossier) et un à la **racine** (`boards.db` : les scènes et pads) — chacun avec sa propre révision ; et une fusion des boards **board-par-board** par clé portable `board_key`, arbitrée par `updated_at`, sans purge globale.

## Alternatives écartées

- **Snapshot unique de la bibliothèque** — le moindre conflit portait sur tout le contenu ; deux régisseurs sur deux scènes distinctes se bloquaient mutuellement sans raison.
- **Écrasement global au merge (« dernier qui pousse gagne »)** — perte de travail silencieuse, exactement le scénario que la fusion par board élimine.
- **Fusion à trois voies (three-way merge) avec base commune** — imposerait de stocker l'ancêtre commun de chaque board et une résolution champ par champ, pour un gain marginal sur ce domaine (une scène est éditée par une personne à la fois en pratique).

## Conséquences

- **Ordre imposé au pull** : les snapshots de dossiers (les SONS) d'abord, la racine (les BOARDS) ensuite. La racine recâble les pads par `driveFileId` — les sons doivent déjà exister localement. Inverser l'ordre produit des pads orphelins.
- Un même dossier Drive peut être **à la fois** un nœud-dossier et la racine d'une bibliothèque : les noms de fichiers des deux snapshots et de leurs manifests sont volontairement distincts (`library.db`/`manifest.json` vs `boards.db`/`boards-manifest.json`). Les fusionner écraserait un snapshot par l'autre.
- Un board présent seulement en local est **conservé**, jamais purgé : c'est le cœur de la décision. Toute optimisation du merge qui réintroduit un `DELETE` global des boards casse le cas « deux régisseurs ».
- Chaque nœud dossier porte sa propre `lastSyncedRevision` : un conflit sur un dossier n'immobilise pas les autres.
