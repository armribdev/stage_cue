# 0002 — Identité portable d'un son : `driveFileId` d'abord, `relativePath` en repli

**Statut :** acceptée
**Date :** 2026-07-21 *(décision antérieure, consignée rétroactivement)*

## Contexte

Un son doit être reconnaissable d'un appareil à l'autre alors que `filePath` est propre à l'appareil (racine de cache locale). La résolution par nom de fichier s'est révélée fragile : casse variable, normalisation Unicode NFC/NFD divergente entre Drive et SQLite, doublons de noms, renommages faits directement dans Drive.

## Décision

L'identité forte d'un son est son `driveFileId` (immuable, attribué par Drive) ; `relativePath` (normalisé NFC, séparateurs `/`) sert de clé portable de repli pour les sons legacy sans ID.

## Alternatives écartées

- **Résolution par chemin seul** — casse dès qu'un fichier est renommé ou déplacé côté Drive, et produit des doublons silencieux sur les noms accentués.
- **Identifiant applicatif propre (uuid) stocké dans un sidecar Drive** — un fichier de plus à synchroniser et à réconcilier, alors que Drive fournit déjà un identifiant stable et gratuit.
- **Hash du contenu** — impose de télécharger le fichier pour l'identifier, incompatible avec une indexation métadonnées-only.

## Conséquences

- `ensureCached` télécharge par `driveFileId` quand il est disponible ; le repli par nom (`_findFileByName`) parcourt **récursivement toute l'arborescence Drive** et ne doit rester qu'un chemin de secours pour les sons legacy.
- Les snapshots exportent `drive_file_id` **et** `relative_path`, jamais l'`id` local (cf. [0003](0003-snapshots-par-dossier-et-fusion-board-par-board.md)). Un pad dont le son n'a aucune des deux clés n'est pas exporté : il ne peut pas voyager.
- Tout nouveau code comparant des noms de fichiers doit passer par `PathUnicode.sameName` / `LibrarySoundPaths.normalizeRelativePath` — une comparaison `==` brute réintroduit les doublons NFC/NFD.
- Corollaire déjà inscrit dans `.claude/rules/audio.md` : le `type` est classifié **uniquement à l'insertion**, sur le fichier local. Sans fichier téléchargé, `type = null` — ce n'est pas une anomalie à « réparer ».
