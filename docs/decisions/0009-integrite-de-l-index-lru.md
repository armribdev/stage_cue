# 0009 — Intégrité de l'index LRU : clé canonique unique et sauvegardes sérialisées

**Statut :** acceptée
**Date :** 2026-07-21

## Contexte

L'index d'accès du cache (`.cache_access.json`) recevait des clés sous des formes hétérogènes selon l'appelant : chemin normalisé depuis `ensureCached`, chemin brut avec préfixe `sounds/` legacy ou en NFD depuis `importFile`. Un même fichier obtenait deux entrées, sa taille était comptée deux fois, et l'éviction se déclenchait bien avant `maxCacheBytes`. Par ailleurs deux téléchargements concurrents sauvegardaient l'index en parallèle sur le même fichier, sans écriture atomique.

## Décision

Toutes les clés de l'index passent obligatoirement par `_indexKey` (canonicalisation `normalizeRelativePath`), les sauvegardes sont sérialisées par racine de cache (`_saveChains`), et l'écriture du JSON se fait en temp + rename.

## Alternatives écartées

- **Normaliser à l'appel plutôt qu'à l'intérieur** — c'est ce qui était fait ; il suffit d'un appelant qui oublie pour réintroduire le double comptage. La canonicalisation doit être un passage obligé, pas une convention.
- **Un verrou (`package:synchronized`)** — une chaîne de futures suffit ici et évite une dépendance ; le point de sérialisation est unique et local.
- **Abandonner l'index et se fier au parcours du système de fichiers** — coûteux à chaque éviction, et perd la récence d'accès qui est toute l'information utile.

## Conséquences

- Ne jamais écrire dans `index.entries` sans passer par `_indexKey`, y compris pour une lecture ou un test d'appartenance. Les chemins venant de la base arrivent sous forme **brute** : les épinglés sont convertis avant comparaison, sinon un favori legacy ne serait pas reconnu comme protégé.
- La corruption du JSON reste rattrapée par un repli sur index vide au chargement, mais ce filet a un coût caché : `total = 0` désactive l'éviction jusqu'à reconstitution de l'index. C'est une dégradation acceptable, pas un comportement sur lequel s'appuyer.
- La chaîne de sauvegarde absorbe les erreurs pour ne pas mourir, tout en les propageant à l'appelant via le future retourné. Ne pas « simplifier » en supprimant le `catchError` : une sauvegarde en échec bloquerait toutes les suivantes.
