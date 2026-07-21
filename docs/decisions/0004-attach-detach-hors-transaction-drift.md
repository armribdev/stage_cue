# 0004 — `ATTACH`/`DETACH` SQLite en dehors des transactions Drift

**Statut :** acceptée
**Date :** 2026-07-21 *(décision antérieure, consignée rétroactivement)*

## Contexte

L'export et la fusion de snapshots attachent une seconde base SQLite (`snap`) à la connexion Drift. Placer le `DETACH` à l'intérieur de la transaction — ce que suggère l'instinct « tout dans la transaction » — fait échouer l'opération avec `database snap is locked`, car SQLite refuse de détacher une base encore engagée dans une transaction non committée.

## Décision

`ATTACH` et `DETACH` encadrent la transaction Drift de l'extérieur ; seules les lectures/écritures sur `snap` vivent à l'intérieur (`library_snapshot_store.dart`).

## Alternatives écartées

- **Tout envelopper dans `database.transaction()`** — provoque `database snap is locked` au `DETACH`. C'est le piège que cette décision existe pour éviter.
- **Ouvrir une seconde connexion Drift sur le fichier snapshot** — Drift avertit explicitement contre plusieurs instances de `AppDatabase` sur le même exécuteur (risque de corruption), et l'`ATTACH` natif fait le travail sans cette complexité.

## Conséquences

- Le `DETACH` est en `finally` : il doit rester atteignable sur tous les chemins d'erreur, sinon la connexion garde une base attachée et le prochain `ATTACH` échoue.
- La fusion elle-même reste transactionnelle : un merge qui échoue en cours de route ne laisse pas la base locale à moitié modifiée.
- Corollaire : le fichier snapshot ne peut pas être supprimé tant qu'il est attaché. Le nettoyage des fichiers temporaires se fait après le `DETACH`.
- Ne pas déplacer les `customStatement('ATTACH …')` à l'intérieur d'un `transaction()` lors d'un refactor — le test passera peut-être en isolation et cassera sous charge réelle.
