# 0035 — Supprimer un son = le mettre à la corbeille Drive

**Statut :** acceptée
**Date :** 2026-11-11

## Contexte

Aucun écran ne permettait de supprimer un son de la bibliothèque. Or un son n'existe que parce que Drive le contient : l'indexation (scan complet, delta `changes.list`, pull de snapshot) recrée en local tout ce que Drive liste ([0002](0002-identite-portable-des-sons.md), [0021](0021-synchronisation-incrementale-par-changes-list.md)). Supprimer la seule ligne locale ferait donc revenir le son à la synchro suivante.

## Décision

« Supprimer un son » **met le fichier à la corbeille Drive** (`DriveClient.trashFile`, `files.update(trashed: true)`, récupérable ~30 jours), **puis** supprime la ligne locale et évince le fichier du cache (`LibraryRepository.deleteLibrarySound`). Drive d'abord, base ensuite : sur échec Drive (hors-ligne, dossier partagé en lecture seule, session expirée) l'exception remonte et rien n'a changé en local.

Les autres appareils n'ont rien à recevoir : `changes.list` signale le fichier `trashed` (déjà traité comme une disparition), ou le scan complet l'élague, et les cascades ([0032](0032-cascades-emulees-par-declencheurs.md)) vident leurs pads. Aucun snapshot n'est publié, aucun nouveau chemin d'élagage n'est ajouté.

Garde-fous, posés dans `SamplerNotifier.soundDeletionBlockedReason` (là où l'état de lecture est connu) : refus en Mode Spectacle et sous un pad qui joue le son. Le formulaire d'édition du son (`SoundEditForm`) demande confirmation en annonçant la corbeille, la portée « tous les appareils / dossier partagé » et le nombre de pads touchés. L'action n'est proposée que pour un son à identité Drive (`driveFileId`).

## Alternatives écartées

- **Masquer** (pierre tombale par son) — colonne et migration, règle de fusion de synchro, filtre dans la recherche, les listes et le sélecteur ; et le fichier resterait sur Drive, sans rien libérer. Beaucoup de surface pour une suppression seulement apparente.
- **Suppression locale seule** — le son revient à la prochaine synchro (cf. Contexte).
- **Suppression définitive (`DriveClient.deleteFile`, `files.delete`)** — irréversible, et une erreur de clic sur un son de spectacle l'est alors aussi, pour tous les appareils et tous les utilisateurs d'un dossier partagé. `deleteFile` reste réservé aux fichiers techniques de la synchro (snapshots, `LibrarySyncService`).

## Conséquences

- Requiert le droit d'écriture sur le fichier : le scope `drive` (déjà demandé) et, en dossier partagé, un rôle éditeur. Sinon `DriveRequestException.denied()` est affichée et le son reste.
- Un 404 est un succès (déjà disparu). La mise à la corbeille est idempotente, donc rejouée par `_guardRetry` ([0012](0012-retry-drive-limite-aux-appels-idempotents.md)).
- Une passe de synchro concurrente qui avait listé le fichier avant la mise à la corbeille peut réinsérer brièvement la ligne ; le prochain delta (`trashed`) ou scan complet la retire.
- Restaurer un son depuis la corbeille Drive le fait revenir à l'indexation suivante, mais ses tags, réglages et places dans les pads sont perdus : seul le fichier est récupérable.
- Les pads qui n'avaient que ce son restent sur la scène, vides, comme après n'importe quelle disparition venue de la synchro.
