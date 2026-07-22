# 0013 — Ouverture de la base sur l'isolate principal, pas en isolate de fond

**Statut :** acceptée
**Date :** 2026-07-22

## Contexte

Au démarrage à froid (cold start) sur Windows, l'app affichait un plateau vide
(« setup initial », création auto d'une « Scène 1 ») alors que la base contenait
bien les boards ; un hot restart corrigeait tout. Diagnostic : `_openConnection`
ouvrait la base via `NativeDatabase.createInBackground(file)`, qui exécute SQLite
dans un **isolate de fond**. À froid, cet isolate se bloque avant que la première
requête (`getSoundBoards`) ne revienne — le natif sqlite3 n'y est pas prêt tant
que la machinerie n'a pas été « chauffée » (d'où le hot restart qui fonctionne).
Comme `loadBoards` n'est appelé qu'une fois en `initState`, l'écran restait vide.

## Décision

Ouvrir la base sur l'**isolate principal** avec `NativeDatabase(file)` plutôt que
`createInBackground`.

## Alternatives écartées

- **`NativeDatabase.createInBackground`** — l'origine du blocage au cold start
  Windows ; le gain (requêtes hors de l'isolate UI) ne vaut pas une régression où
  les boards ne se chargent jamais sans hot restart.
- **Garder `createInBackground` + `setup`/pré-chauffage de l'isolate** — complexe,
  fragile, et sans bénéfice réel à l'échelle des requêtes de cette app (petites,
  déjà chargées en async avec skeletons).

## Conséquences

- Les requêtes Drift s'exécutent sur l'isolate UI. Acceptable ici (volumes
  faibles) ; si un jour une requête devient lourde (traitement massif de sons),
  la déporter ponctuellement plutôt que de rebasculer toute la DB en
  `createInBackground`.
- **Ne pas** revenir à `createInBackground` sans reproduire d'abord un cold start
  Windows après `flutter clean` — c'est le seul scénario qui révèle le blocage.
- Garde complémentaire (même thème, robustesse au lancement) : `loadBoards`
  n'auto-crée plus de « Scène 1 » tant que le pull de lancement n'est pas réglé
  (`LibraryRepository.initialSyncSettled`) si une bibliothèque Drive est
  connectée — sinon une lecture transitoirement vide créerait une scène fantôme.
  Voir [0005](0005-ordre-de-synchronisation-au-lancement.md) pour l'ordre du pull.
