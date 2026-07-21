# 0011 — Déduplication par clé de pad et attente explicite pour les portées imbriquées

**Statut :** acceptée
**Date :** 2026-07-21

## Contexte

`DownloadQueue` déduplique par clé, et deux opérations de portées différentes — « télécharger le slot *i* » et « télécharger tout le pad » — utilisaient la même clé `pad.id`. Un tap utilisateur sur un slot pendant un prefetch du pad entier recevait le future du prefetch : la tâche du slot n'était **jamais exécutée** et le booléen retourné (playabilité du pad) était interprété comme « slot prêt ». Les deux opérations retournant `bool`, le cast interne ne levait rien : l'erreur était silencieuse.

## Décision

La clé de déduplication reste `pad.id` ; l'appelant de portée plus **large** attend la tâche plus étroite déjà en vol via `DownloadQueue.inFlight(key)` avant d'enfiler la sienne, au lieu d'être dédupliqué sur elle.

## Alternatives écartées

- **Clé composite `(pad.id, slotIndex)`** — supprime la collision mais aussi la déduplication utile : un tap et un prefetch sur le même pad relanceraient deux téléchargements concurrents des mêmes fichiers.
- **Typer la file par opération** — le cast `value as T` deviendrait sûr, mais le vrai problème n'est pas le type : c'est qu'une portée large soit satisfaite par une portée étroite. Une erreur de type aurait rendu le bug bruyant, pas absent.
- **Interdire les portées imbriquées côté appelant** — impossible : le prefetch automatique et le tap utilisateur sont par nature concurrents et non coordonnés.

## Conséquences

- Toute nouvelle opération enfilée sous une clé de pad existante doit se demander si elle est **plus large** que ce qui peut déjà tourner. Si oui, passer par `inFlight` d'abord.
- `enqueue` renvoie `existing.completer.future.then((v) => v as T)` : deux opérations de types de retour différents sous la même clé produiraient une erreur de cast asynchrone. Aujourd'hui tout retourne `bool`. À revoir si un type de tâche hétérogène rejoint la file.
- Le contrat d'annulation reste inchangé : `cancelQueued` ne touche que les tâches **en attente** ; celles déjà démarrées finissent et remplissent le cache (pas de gâchis de bande passante déjà consommée). `DownloadCancelledException` doit être rattrapée par chaque appelant — un `enqueue` non `await`é produirait une erreur asynchrone non gérée.
- Le pad musique détaché hors-scène est exclu de l'annulation au changement de plateau : le tapis sonore doit poursuivre son téléchargement.
