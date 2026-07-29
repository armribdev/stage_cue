# 0010 — Épinglage LRU : favoris **et** sons du plateau actif

**Statut :** acceptée
**Date :** 2026-07-21

## Contexte

Seuls les favoris étaient exclus de l'éviction ; les sons du plateau en cours étaient censés être protégés « implicitement par la récence ». Cette hypothèse tombe dès qu'un téléchargement massif (bouton « Tout télécharger ») rebat l'ordre LRU : les sons de la scène en cours, mis en cache une heure plus tôt, deviennent les plus anciens et sont supprimés en pleine représentation.

## Décision

Le callback `pinnedPaths` fourni à `AudioCacheManager` retourne les favoris **et** les chemins des sons du plateau actif ; les deux ensembles sont exclus de l'éviction quelle que soit leur récence.

## Alternatives écartées

- **Compter sur la récence d'accès seule** — l'hypothèse ne tient pas sous téléchargement massif, exactement le moment où l'éviction se déclenche.
- **Ne jamais évincer pendant une passe de téléchargement massif** — reporte le problème : le cache dépasse alors sa borne, ce que la politique existe précisément pour empêcher.
- **Donner au cache une dépendance directe au `SamplerNotifier`** — casserait l'indépendance d'`AudioCacheManager` (pas de dépendance à Flutter, à la base ni au SDK Google), qui le rend testable avec de simples mocks. Le callback préserve cette frontière.

## Conséquences

- `AudioCacheManager` reste ignorant de la notion de plateau : il consomme un ensemble de chemins opaques. Ne pas y introduire de dépendance à la couche présentation.
- Le callback est branché à la construction du `LibraryRepository` — s'il n'est pas fourni, l'éviction redevient purement LRU **sans avertissement**. C'est le mode de régression le plus probable de cette décision.
- Les chemins retournés viennent de la base sous forme brute et sont canonicalisés côté cache (cf. [0009](0009-integrite-de-l-index-lru.md)).
- Un plateau plus gros que l'espace disque disponible rendrait l'éviction incapable de tenir sa borne. Le cas n'est pas traité aujourd'hui.
- [0016](0016-cache-sans-plafond-garde-fou-disque.md) remplace le plafond fixe (`maxCacheBytes`) par un garde-fou fondé sur l'espace disque réel : cette politique d'épinglage (favoris + plateau actif) reste inchangée et continue de s'appliquer à chaque éviction, qu'elle soit déclenchée par le préchargement automatique ou par le bouton « Tout télécharger ».
- Rappel : l'éviction ne peut pas couper une lecture en cours, les octets étant déjà en mémoire (cf. [0001](0001-chargement-audio-soloud.md)). Elle affecte la **disponibilité future**, pas le son qui joue.
