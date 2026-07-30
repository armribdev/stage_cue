# 0020 — Sonde de pull groupée et jeton de manifest

**Statut :** acceptée
**Date :** 2026-07-30

## Contexte

Le pull par-dossier sondait chaque nœud isolément : « trouve `.stagecue` », « trouve `manifest.json` », « télécharge-le », puis seulement comparaison de révision. Soit trois allers-retours en série par dossier — 240 requêtes et ~60 s (à 250 ms d'aller-retour) pour une bibliothèque de 80 dossiers, à **chaque lancement**, alors que la conclusion est presque toujours « rien de neuf ». Une fois l'indexation traitée ([0018](0018-journalisation-wal-et-synchronous-normal.md), [0019](0019-parcours-drive-parallele-borne.md)), c'était le poste dominant du démarrage.

## Décision

Trois changements complémentaires :

1. **`DriveClient.findInFolders`** — sonde le même nom dans N dossiers en une requête (par lots de 40 parents), en rattachant chaque résultat à son parent via le champ `parents`.
2. **`LibrarySyncService.pullFolders`** — groupe les deux sondes, télécharge les manifests restants en parallèle borné, et garde les **fusions strictement séquentielles** ([0004](0004-attach-detach-hors-transaction-drift.md)).
3. **Jeton de sonde** (`library_folders.manifest_probe_token`, schéma v36) — le `modifiedTime` du manifest au dernier pull concluant. S'il est inchangé, le manifest n'est même pas téléchargé.

Mesure à 250 ms d'aller-retour, 80 dossiers : **240 req / 60 s → 84 req / 5,0 s à froid, et 4 req / 1,0 s en régime établi** (le cas de tous les lancements).

## Alternatives écartées

- **Colonne `dateTime()` pour le jeton** — le choix naturel, et un piège. Drift stocke un `DateTime` en secondes epoch (la précision milliseconde de Drive serait perdue) et le relit en heure **locale** alors que Drive émet de l'UTC ; `==` sur `DateTime` distinguant les deux fuseaux, la comparaison aurait échoué à tous les coups. Le cache n'aurait jamais servi, sans rien signaler — l'optimisation aurait été purement décorative. Le jeton est donc du **texte** : une clé de cache opaque, comparée par égalité, jamais par ordre.
- **Comparer le `modifiedTime` du manifest à `lastSyncedAt`** — éviterait la migration, mais opposerait une horloge serveur à une horloge locale : une machine en avance sauterait une synchro légitime.
- **Listing à plat de tous les `.stagecue`** — même objection que pour l'indexation ([0019](0019-parcours-drive-parallele-borne.md)) : le pull tire ses conclusions de ce qu'il voit.
- **Paralléliser aussi les fusions** — collision d'`ATTACH` sur la base partagée ([0004](0004-attach-detach-hors-transaction-drift.md)). Seules les lectures réseau sont parallélisées.

## Conséquences

- **Ne mémoriser un jeton qu'après une passe CONCLUANTE** (`PullStaged` ou `PullUpToDate`). Une fusion ratée ou un blob introuvable doit laisser le jeton à `null` : sinon le pull suivant sauterait la sonde et croirait le nœud à jour, le figeant à jamais sur une révision jamais fusionnée. Verrouillé par un test dédié.
- Le jeton repose sur le fait que le manifest est **l'unique source de vérité** sur le snapshot courant ([0007](0007-publication-de-snapshot-par-blob-unique.md)) : manifest identique ⟹ blob identique. Publier un snapshot sans réécrire son manifest casserait cette hypothèse.
- Passer par `manifestProbeTokenOf` des **deux côtés** (ce qu'on mémorise et ce qu'on compare). Deux sérialisations différentes rouvriraient exactement le trou décrit plus haut.
- `library_folders` rejoint `libraries` dans le filtre de bookkeeping d'`AutoSyncCoordinator._onTablesUpdated` : le pull y écrit désormais à chaque passe, et sans ce filtre chaque pull déclencherait un push parasite. Ces deux tables ne voyagent dans aucun snapshot, donc une écriture qui ne touche qu'elles n'a rien à pousser. `updateFolderManifestProbe` n'écrit en outre qu'en cas de changement réel.
- `pullFolder` (unitaire) n'est plus qu'une façade à une entrée sur `pullFolders` : ne pas réintroduire d'implémentation séparée, et ne pas l'appeler en boucle.
