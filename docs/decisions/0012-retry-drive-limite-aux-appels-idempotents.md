# 0012 — Réessai Drive réservé aux appels idempotents

**Statut :** acceptée
**Date :** 2026-07-21

## Contexte

Aucun réessai n'existait : un 429 momentané ou un incident Google faisait échouer la synchro, et l'erreur brute (`DetailedApiRequestError(status: 403, …)`) était affichée telle quelle dans la pastille. Ajouter un réessai global aurait été pire — rejouer un upload envoie un `Stream` déjà épuisé, et rejouer une création de dossier la duplique si seule la réponse s'est perdue.

## Décision

Deux enveloppes distinctes dans `GoogleDriveClient` : `_guardRetry` (réessai exponentiel avec bruit aléatoire, 4 tentatives) pour les appels **idempotents** — lecture, listing, téléchargement — et `_guard` (sans réessai) pour les appels qui consomment un flux ou créent une ressource.

## Alternatives écartées

- **Réessai uniforme sur tous les appels** — corrompt les uploads (flux épuisé) et duplique les dossiers créés. C'est précisément ce que la séparation empêche.
- **Réessai dans la couche appelante (`SyncController`)** — rejouerait toute la séquence push (export + upload), très coûteuse, là où seul un appel unitaire a échoué.
- **Rendre les uploads idempotents par clé de requête** — l'API Drive ne fournit pas de clé d'idempotence exploitable ici.

## Conséquences

- **Le choix de l'enveloppe est porteur de correction, pas de style.** Un nouvel appel d'API doit être classé : idempotent → `_guardRetry`, sinon `_guard`. Basculer un upload vers `_guardRetry` provoque un échec sur flux épuisé.
- Le 403 est ambigu chez Drive (quota dépassé *ou* droits refusés) : seul le motif (`reason`/`message` contenant `ratelimit`/`quota`) le rend retentable. Un 403 de permission ne doit jamais être rejoué.
- Le 401 n'est **jamais** retenté ici : il est converti en `DriveAuthException` et traité en amont par le renouvellement silencieux de session, puis par une demande d'OAuth interactif au second échec.
- Les erreurs sont traduites en `DriveRequestException` (quota / denied / unavailable / offline) : l'UI ne doit plus afficher `e.toString()` d'une erreur d'API brute.
- Le bruit aléatoire du backoff existe pour éviter que plusieurs appareils ne se resynchronisent sur le même créneau — ne pas le retirer au nom du déterminisme des tests.
