# 0007 — Publication de snapshot : blob au nom unique, manifest comme point de bascule

**Statut :** acceptée
**Date :** 2026-07-21

## Contexte

Le push écrivait le snapshot sous un nom fixe (`boards.db`) après une simple lecture du manifest. Deux appareils partant de la même révision passaient tous deux la garde, écrivaient tous deux au même emplacement, et le second **détruisait les données du premier** en annonçant un succès. Un arrêt entre l'upload et l'écriture du manifest laissait un contenu distant que le manifest ne désignait pas, invisible des pairs et écrasable par eux.

## Décision

Chaque push téléverse un blob au nom unique (`boards-<uuid>.db`), relit le manifest juste avant de publier, et n'expose le blob qu'en écrivant le manifest — qui porte désormais le champ `dbFileName` désignant le snapshot courant.

## Alternatives écartées

- **Écriture conditionnelle par ETag** — l'API Drive n'expose pas de précondition sur `files.update`. L'atomicité côté serveur n'est tout simplement pas disponible.
- **Fichier de verrou dans `.stagecue`** — un verrou sans bail expirable se retrouve orphelin dès qu'un appareil meurt en le détenant ; avec bail, il faut une horloge commune que l'on n'a pas.
- **Conserver le nom fixe et se contenter de la relecture du manifest** — réduit la fenêtre mais laisse le perdant détruire le blob du gagnant avant de s'en rendre compte. Le nom unique est ce qui rend l'abandon **inoffensif**.

## Conséquences

- **Le manifest est la seule source de vérité** sur le snapshot courant. Un blob non désigné par un manifest n'existe pas : ne jamais résoudre un snapshot en devinant son nom (sauf repli explicite sur les noms historiques, pour les dossiers poussés par une version antérieure).
- La séquence n'est **pas** atomique et ne peut pas l'être. La garantie obtenue est plus faible mais suffisante : le perdant d'une course abandonne sans avoir détruit les données du gagnant, et repart sur une résolution de conflit. Ne pas présenter cette décision comme une exclusion mutuelle.
- Le blob précédent est supprimé après publication (best-effort) pour que `.stagecue` ne grossisse pas indéfiniment ; un résidu ne compromet rien.
- Les fichiers temporaires d'export/import portent un nom unique par opération (`_uniqueTempPath`) : deux synchros concurrentes ne peuvent plus se marcher dessus, y compris sur des bibliothèques différentes.
- `SyncManifest.dbFileName` est **nullable** : un manifest écrit par une version antérieure n'a pas ce champ et doit continuer à être lu (repli sur le nom historique). Ne pas le rendre obligatoire.
