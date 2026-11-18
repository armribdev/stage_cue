# 0043 — Le catalogue de tags se réconcilie après chaque import de snapshot

**Statut :** acceptée
**Date :** 2026-11-18

## Contexte

La v48 (décision 0040) a fusionné « Applaudir » dans « Voix », mais « Applaudir » est revenu dans les suggestions : le snapshot Drive, publié avant la migration ou par un appareil pas encore à jour, le contient encore, et l'import recrée par son nom tout tag absent en local. Le cas d'une catégorie retirée (MUSIQUE) avait été traité à part dans l'import, mais pas celui des tags fusionnés ou élagués. Chaque évolution du catalogue devait donc être codée deux fois (migration, import), et la seconde se faisait oublier.

## Décision

Retirer, fusionner ou élaguer un tag ou une catégorie se déclare **une seule fois**, dans `retiredTagCategories`, `mergedTags` et `prunedTags` (`database_tag_seed.dart`), et `AppDatabase.reconcileTagCatalog` les applique. Elle est idempotente et appelée par la migration **et** à la fin de chaque `mergeFolderSnapshot`, dans sa transaction, après les imports de tags : l'import n'a plus aucune règle de catalogue.

## Alternatives écartées

- **Remapper chaque cas dans l'import** (ce que faisait 0040 pour MUSIQUE) — une règle de plus à écrire dans `_importTags` à chaque évolution, donc un oubli à chaque fois.
- **Versionner le catalogue dans le snapshot et ne réconcilier que les snapshots plus anciens** — un champ de plus à publier et à garder cohérent entre appareils, pour éviter une série de requêtes déjà très bon marché.
- **Réconcilier seulement au lancement** — la fusion suivante d'un snapshot en retard recréerait le tag jusqu'au prochain lancement.

## Conséquences

- Ajouter un tag à une de ces trois listes suffit : le test `un snapshot d'un appareil en retard ne recrée aucun tag retiré du catalogue` (`library_snapshot_store_test.dart`) est piloté par les listes et couvre l'entrée sans qu'on y touche. Ne rien ajouter d'autre dans `LibrarySnapshotStore._importTags`.
- Le tag d'accueil d'une fusion doit exister dans le catalogue (`_extraTagCatalog`) ; sinon la fusion est journalisée (`AppLog.warn`) et ignorée.
- Les noms de ces listes sont **réservés** : un tag que l'utilisateur recréerait sous un nom fusionné serait refondu dans sa famille au prochain pull, et un tag élagué inutilisé serait supprimé. Un tag élagué déjà posé sur un son est conservé.
- La fusion d'un tag emporte ses usages (`sound_tags`), ses suggestions (`sound_auto_tags`) et ses alias.
- Remplace le remappage de l'import décrit en conséquence de [0040](0040-tags-generiques-et-dissolution-de-la-categorie-musique.md).
