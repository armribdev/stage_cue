# 0006 — Téléchargement atomique : écriture dans `.part` puis renommage

**Statut :** acceptée
**Date :** 2026-07-21 *(décision antérieure, consignée rétroactivement)*

## Contexte

Le cache disque considère la simple **présence** d'un fichier comme preuve de validité (`ensureCached` retourne immédiatement si le fichier existe). Une écriture directe à la destination finale laisserait, sur coupure réseau ou arrêt de l'app, un fichier tronqué indistinguable d'un cache valide — donc un pad définitivement muet.

## Décision

`GoogleDriveClient.downloadToFile` écrit dans `<destination>.part`, puis renomme vers la destination finale ; sur erreur, le `.part` est supprimé.

## Alternatives écartées

- **Écriture directe à la destination** — produit exactement le fichier partiel considéré comme valide décrit ci-dessus.
- **Validation par hash après coup (`md5Checksum`)** — Drive expose bien le champ, mais il faudrait relire tout le fichier pour le vérifier à chaque téléchargement. Le renommage atomique règle le cas sans ce coût. La validation par hash reste une option si une corruption silencieuse est un jour observée.
- **Marqueur de validité en base** — dédoublerait l'état (fichier + ligne) et introduirait sa propre désynchronisation.

## Conséquences

- Le contrat « fichier présent = fichier complet » repose entièrement sur ce renommage. Toute nouvelle voie d'écriture dans le cache (import, copie, migration) doit respecter le même schéma temp + rename.
- Un arrêt brutal (OS qui tue l'app) laisse un `.part` orphelin : ni renommé, ni inscrit dans l'index LRU, donc jamais évincé. `AudioCacheManager.cleanupPartialDownloads` les purge au démarrage — ce ménage est nécessaire *parce que* l'atomicité est assurée par un fichier annexe.
- Le même schéma est appliqué à l'index LRU lui-même (cf. [0009](0009-integrite-de-l-index-lru.md)).
- Défense en profondeur côté audio : `loadAudioSourceFromFile` rejette les fichiers trop petits ou sans en-tête audio plausible. Ce filet ne remplace pas l'atomicité, il la double.
