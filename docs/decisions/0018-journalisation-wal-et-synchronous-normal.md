# 0018 — Journalisation WAL et `synchronous = NORMAL`

**Statut :** acceptée
**Date :** 2026-07-30

## Contexte

La base était ouverte sans réglage de journalisation, donc aux défauts SQLite : `journal_mode = delete` + `synchronous = full`. Chaque transaction crée puis supprime un journal de rollback et paie deux fsync. L'indexation Drive écrit des milliers de lignes par petites transactions implicites — mesure sur 2000 fichiers / 80 dossiers, client Drive à latence nulle pour isoler le coût disque : **4577 ms**. C'est le mode journal qui domine, pas le coût des requêtes (les index d'identité forte existent déjà).

## Décision

`beforeOpen` applique `PRAGMA journal_mode = WAL` et `PRAGMA synchronous = NORMAL` à chaque ouverture. Même mesure après : **788 ms** (5,8×).

## Alternatives écartées

- **WAL seul, `synchronous` laissé à FULL** — durabilité stricte conservée, mais on abandonne une part du gain sans contrepartie utile ici : NORMAL sous WAL ne peut pas corrompre la base, il ne peut que perdre les dernières transactions non checkpointées. Arbitrage validé explicitement avec l'utilisateur.
- **Callback `setup:` de `NativeDatabase`** — c'est la voie canonique de drift, mais son paramètre est une `sqlite3.Database` : il faudrait déclarer `sqlite3` en dépendance directe (aujourd'hui transitive) et épingler l'app à la version choisie par drift, qu'un futur bump ferait diverger. `beforeOpen` obtient le même résultat via l'API publique de drift.
- **Ne rien changer et n'optimiser que la boucle d'indexation** — le batch des écritures et le mode journal se cumulent, mais le mode journal profite à *toutes* les écritures de l'app, pas seulement à l'indexation.

## Conséquences

- `synchronous = NORMAL` n'est **pas persistant** : il est propre à chaque connexion et doit rester dans `beforeOpen`. `journal_mode`, lui, est inscrit dans l'en-tête du fichier — le rejouer est sans effet et sans coût.
- Une coupure brutale (crash, perte secteur) peut perdre les toutes dernières transactions non encore checkpointées. La base reste **incorruptible**. Pour une édition de pad c'est acceptable ; si un jour une écriture demande une durabilité stricte, l'encadrer ponctuellement plutôt que de repasser toute la base en FULL.
- Ces deux lignes sont invisibles et leur perte ne casse aucun test fonctionnel — la base retomberait silencieusement aux défauts. D'où `test/core/database/journal_mode_test.dart`, qui les verrouille sur une base **fichier** : en base mémoire SQLite ignore WAL sans erreur, un test en mémoire ne prouverait rien.
- Deux fichiers annexes (`-wal`, `-shm`) apparaissent à côté de la base. Toute manipulation du fichier de base au niveau système (copie, sauvegarde) doit les inclure — ou passer par SQL. L'export de snapshot n'est pas concerné : il reconstruit une base neuve par `ATTACH` + `CREATE TABLE AS SELECT` (cf. [0004](0004-attach-detach-hors-transaction-drift.md)), il ne copie jamais le fichier brut.
- WAL exige de la mémoire partagée : il ne fonctionne pas sur un système de fichiers réseau. La base vit dans le répertoire support de l'app, donc toujours local — ne pas déplacer son emplacement sans revalider ce point.
