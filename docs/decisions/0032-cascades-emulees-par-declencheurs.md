# 0032 — Cascades de suppression émulées par des déclencheurs SQLite

**Statut :** acceptée
**Date :** 2026-11-05

## Contexte

Les tables déclarent des `onDelete: cascade`, mais l'app ne pose aucun `PRAGMA foreign_keys` : SQLite ne les exécute donc pas. Supprimer un pad, une scène, un son ou un tag laissait des lignes orphelines (`pad_sounds`, `sound_tags`, `sound_auto_tags`, `tag_aliases`, pads sans scène). La lecture les masquait par des `INNER JOIN`, mais elles s'accumulaient — dont à **chaque synchro** qui remplace une scène par une version distante plus récente.

## Décision

Des déclencheurs `AFTER DELETE` (`_createCascadeTriggers`, `database.dart`) émulent les cascades : scène → pads → `pad_sounds` ; son → `pad_sounds`, `sound_tags`, `sound_auto_tags` ; tag → `sound_tags`, `sound_auto_tags`, `tag_aliases` ; bibliothèque → ses dossiers (`library_folders`) et appartenances (`folder_memberships`). Retirer une bibliothèque **détache** ses scènes (`sound_boards.library_id` à null, la scène et ses pads sont conservés) ; la déclaration Drift est alignée (`KeyAction.setNull`). Les déclencheurs sont recréés (`IF NOT EXISTS`) à **chaque ouverture** de la base, et la v47 purge les orphelins existants (`_purgeOrphans`).

## Alternatives écartées

- **`PRAGMA foreign_keys = ON`** — un import de snapshot pose transitoirement des lignes qui référencent des absents (ex. pads avant leurs sons, ordre imposé par [0003](0003-snapshots-par-dossier-et-fusion-board-par-board.md)) : les insertions échoueraient. Les migrations `alterTable` exigent aussi de le désactiver.
- **Suppressions explicites dans chaque datasource** — une quinzaine de sites (dont du SQL brut et la fusion de snapshots), et tout nouveau site oublierait la purge.
- **Faire exécuter la cascade déclarée `libraries` → `sound_boards`** — retirer une bibliothèque n'a jamais supprimé ses scènes ; l'exécuter aurait détruit des scènes et leurs pads. Elles deviennent locales à la place.

## Conséquences

- Toute nouvelle relation parent → enfant « orpheline sans le parent » s'ajoute à la liste de `_createCascadeTriggers`, pas dans un datasource.
- `DROP TABLE` ne déclenche rien et emporte les déclencheurs de la table : une migration `alterTable` sur l'une de ces tables ne purge pas ses dépendants (comme avant) mais ses déclencheurs reviennent à l'ouverture suivante.
- Les suppressions en masse (élagage Drive) paient une recherche par ligne supprimée dans `pad_sounds`, dont la clé primaire commence par `pad_id` : négligeable aux volumes actuels, à indexer `sound_id` si ça change.
- Un nœud dossier a un unique propriétaire dont les sons sont supprimés au retrait : le purger est cohérent, y compris pour une autre bibliothèque qui le « voyait » (elle n'y a plus aucun son). Après un retrait, l'écran des réglages appelle `SyncController.onLibraryMerged` pour relire l'index de recherche et les scènes en mémoire.
