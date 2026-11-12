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
| [0021](0021-synchronisation-incrementale-par-changes-list.md) | Synchronisation incrémentale par `changes.list`, avec repli systématique | acceptée |
| [0022](0022-veille-drive-en-cours-de-session.md) | Veille Drive en cours de session : delta seulement, jamais de scan | acceptée |
| [0023](0023-direction-visuelle-console-linear.md) | Direction visuelle "Console Linear", en rupture avec Material 3 par défaut | acceptée |
| [0024](0024-voie-ambiance-exclusive-en-boucle.md) | Voie ambiance exclusive, en boucle, dans la régie | acceptée |
| [0025](0025-journal-fichier-persistant.md) | Journal fichier persistant, borné et masqué, exportable depuis les réglages | acceptée |
| [0026](0026-verification-sha256-de-l-installeur.md) | Vérification SHA-256 de l'installeur avant lancement de la mise à jour | acceptée |
| [0027](0027-preecoute-casque-stricte.md) | Pré-écoute au casque stricte : jamais de repli sur la salle | acceptée |
| [0028](0028-consentement-oauth-desktop-avec-refresh-token.md) | Consentement OAuth desktop maison, pour toujours obtenir un refresh token | acceptée |
| [0029](0029-analyse-automatique-des-tags-sur-l-appareil.md) | Analyse automatique des tags sur l'appareil, par modèles ONNX en pack optionnel | acceptée (amendée par 0030 et 0031) |
| [0030](0030-tags-de-l-ia-en-couche-separee-et-masquables.md) | Tags de l'IA : couche séparée, masquables, jamais supprimés | acceptée (amendée par 0031) |
| [0031](0031-tags-de-l-ia-en-suggestions-avec-score.md) | Tags de l'IA : suggestions toujours affichées, avec leur score, acceptées une à une | acceptée |
| [0032](0032-cascades-emulees-par-declencheurs.md) | Cascades de suppression émulées par des déclencheurs SQLite, pas par `foreign_keys` | acceptée |
| [0033](0033-toast-global-au-dessus-du-navigator.md) | Notifications en toast global au-dessus du Navigator, plus de `SnackBar` | acceptée |
| [0034](0034-icones-lucide-via-appicons.md) | Icônes Lucide à trait fin, centralisées dans `AppIcons` | acceptée (rendu remplacé par 0038) |
| [0035](0035-suppression-d-un-son-par-la-corbeille-drive.md) | Supprimer un son = le mettre à la corbeille Drive, avant de toucher à la base | acceptée |
| [0036](0036-volume-auto-par-sonie-lufs-selon-le-type.md) | Volume « auto » : sonie LUFS pondérée K, cible selon le type de son | acceptée |
| [0037](0037-mode-reseau-binaire-spectacle-masque-les-pads.md) | Mode réseau binaire : c'est le Mode Spectacle qui masque les pads injouables | acceptée |
| [0037](0037-mise-a-jour-par-fermeture-de-l-app-sans-appmutex.md) | Mise à jour : l'app se ferme d'elle-même, l'installeur n'a plus d'AppMutex | acceptée |
| [0038](0038-icones-lucide-en-traces-vectoriels.md) | Icônes Lucide dessinées en tracés vectoriels (`StrokeIcon`), plus en police | acceptée |
| [0039](0039-apercu-lecteur-independant-recherche-eclair-lit-pour-de-vrai.md) | Aperçu : lecteur unique indépendant du STOP ; la recherche-éclair joue le son pour de vrai | acceptée |

Les entrées 0001 à 0006 consignent rétroactivement des décisions **antérieures**, confirmées par un audit du système de synchronisation (juillet 2026) ; les entrées 0007 à 0012 découlent des correctifs issus de ce même audit.
