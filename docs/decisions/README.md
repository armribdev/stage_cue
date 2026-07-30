# Décisions d'architecture (ADR)

Journal des décisions structurantes du projet — le **pourquoi**, pas le quoi (le code et `git log` suffisent pour ça).

## Quand créer une entrée

Une décision mérite une entrée si elle répond à au moins un de ces critères :

- Elle écarte une alternative raisonnable (ex. "pourquoi pas Riverpod", "pourquoi pas de cache disque ici")
- Elle introduit une contrainte durable qui n'est pas évidente en lisant le code (ex. buffer size audio fixé à 1024)
- Elle change une convention établie dans `CLAUDE.md` ou `.claude/rules/`
- Revenir dessus plus tard casserait quelque chose de non-évident (migration, format de fichier, contrat d'API interne)

Un simple refactor, un bugfix, ou un choix qui découle naturellement des conventions existantes ne justifie **pas** une entrée.

## Format

Fichier `NNNN-titre-court.md`, numéroté séquentiellement. Voir [template.md](template.md).

## Index

| # | Titre | Statut |
|---|-------|--------|
| [0001](0001-chargement-audio-soloud.md) | Chargement audio SoLoud : file unique et octets lus côté Dart | acceptée |
| [0002](0002-identite-portable-des-sons.md) | Identité portable d'un son : `driveFileId` d'abord, `relativePath` en repli | acceptée |
| [0003](0003-snapshots-par-dossier-et-fusion-board-par-board.md) | Snapshots par-dossier + racine, et fusion board-par-board non destructive | acceptée |
| [0004](0004-attach-detach-hors-transaction-drift.md) | `ATTACH`/`DETACH` SQLite en dehors des transactions Drift | acceptée |
| [0005](0005-ordre-de-synchronisation-au-lancement.md) | Ordre au lancement : indexer, puis tirer, puis ré-élaguer | acceptée |
| [0006](0006-telechargement-atomique-temp-rename.md) | Téléchargement atomique : écriture dans `.part` puis renommage | acceptée |
| [0007](0007-publication-de-snapshot-par-blob-unique.md) | Publication de snapshot : blob au nom unique, manifest comme point de bascule | acceptée |
| [0008](0008-distinguer-absence-de-distant-et-a-jour.md) | Distinguer « rien à tirer » de « pas de snapshot distant » | acceptée |
| [0009](0009-integrite-de-l-index-lru.md) | Intégrité de l'index LRU : clé canonique unique et sauvegardes sérialisées | acceptée |
| [0010](0010-epinglage-lru-favoris-et-plateau-actif.md) | Épinglage LRU : favoris **et** sons du plateau actif | acceptée |
| [0011](0011-deduplication-de-la-file-de-telechargement.md) | Déduplication par clé de pad et attente explicite pour les portées imbriquées | acceptée |
| [0012](0012-retry-drive-limite-aux-appels-idempotents.md) | Réessai Drive réservé aux appels idempotents | acceptée |
| [0013](0013-ouverture-db-isolate-principal.md) | Ouverture de la base sur l'isolate principal, pas en isolate de fond | acceptée |
| [0014](0014-priorite-au-son-le-moins-joue-en-mode-live.md) | Mode live : priorité au son le moins joué de la session pour les multipads | acceptée |
| [0015](0015-plein-ecran-windows-manuel.md) | Plein écran Windows (F11) : implémentation manuelle plutôt que `window_manager.setFullScreen` | acceptée |
| [0016](0016-cache-sans-plafond-garde-fou-disque.md) | Cache local sans plafond fixe, garde-fou par espace disque réel | acceptée |
| [0017](0017-index-de-recherche-en-memoire.md) | Index de recherche en mémoire, servi périmé puis rafraîchi | acceptée |
| [0018](0018-journalisation-wal-et-synchronous-normal.md) | Journalisation WAL et `synchronous = NORMAL` | acceptée |
| [0019](0019-parcours-drive-parallele-borne.md) | Parcours Drive en largeur, parallélisme borné, complet ou rien | acceptée |
| [0020](0020-sonde-de-pull-groupee-et-jeton-de-manifest.md) | Sonde de pull groupée et jeton de manifest | acceptée |

Les entrées 0001 à 0006 consignent rétroactivement des décisions **antérieures**, confirmées par un audit du système de synchronisation (juillet 2026) ; les entrées 0007 à 0012 découlent des correctifs issus de ce même audit.
