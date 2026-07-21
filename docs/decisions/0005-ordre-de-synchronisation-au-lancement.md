# 0005 — Ordre au lancement : indexer, puis tirer, puis ré-élaguer

**Statut :** acceptée
**Date :** 2026-07-21 *(décision antérieure, consignée rétroactivement)*

## Contexte

Sur un appareil vierge, le pull des métadonnées n'a aucun nœud dossier où atterrir tant que l'indexation Drive n'a pas créé la structure. À l'inverse, un snapshot distant périmé (poussé par un appareil pas encore rescanné) peut réinsérer des sons pointant vers des fichiers déjà supprimés sur Drive.

## Décision

`AutoSyncCoordinator._initialPull` exécute strictement : **1.** indexation Drive (métadonnées seules, avec timeout), **2.** pull par-dossier puis racine, **3.** ré-élagage d'après l'ensemble des fichiers réellement vus à l'étape 1 — et ne tire que les bibliothèques **entièrement** indexées.

## Alternatives écartées

- **Pull d'abord, indexation ensuite** — sur un appareil vierge, le pull racine recâblerait les boards sur des sons encore inexistants : pads perdus.
- **Tirer même sur un index partiel (timeout, réseau lent)** — le pull racine purgerait puis recâblerait les boards sur un sous-ensemble de sons. Mieux vaut garder l'état local et réessayer au prochain lancement, cache chaud.
- **Faire confiance au snapshot distant pour l'existence des fichiers** — un snapshot est par nature en retard sur le scan live ; le scan a le dernier mot.

## Conséquences

- Ne pas réordonner ces trois étapes, et ne pas retirer le filtre « entièrement indexée » : chacun de ces changements a un mode de défaillance qui ne se manifeste que sur un appareil vierge ou un réseau lent, donc rarement en développement.
- L'indexation est **métadonnées-only** (aucun téléchargement audio inline) : le timeout de 120 s ne borne que le listing Drive et les insertions. Y ajouter des téléchargements ferait exploser ce budget.
- Toute la séquence tourne sous `_ignoreUpdates` : les écritures issues du merge ne doivent pas déclencher de push (le contenu vient du distant, pas d'une édition locale).
- Les mises à jour ne touchant que la table `libraries` (bookkeeping de révision) sont ignorées par `_onTablesUpdated` — sans ce filtre, chaque push en déclenche un autre, en boucle.
