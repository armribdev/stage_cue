# 0008 — Distinguer « rien à tirer » de « pas de snapshot distant »

**Statut :** acceptée
**Date :** 2026-07-21

## Contexte

`PullUpToDate` était retourné dans trois situations distinctes : rien de plus récent, pas de dossier `.stagecue`, pas de fichier `.db`. L'appelant les traitait uniformément comme un succès — la pastille affichait « Synchronisé » avec un horodatage frais alors que la zone de synchro distante avait été supprimée, laissant croire à une sauvegarde inexistante.

## Décision

Ajouter la variante `PullNoRemoteSnapshot` à l'union scellée `PullOutcome`, retournée quand `.stagecue`, le manifest ou le blob désigné sont absents ; `PullUpToDate` ne signifie plus que « le distant existe et n'a rien de plus récent ».

## Alternatives écartées

- **Un champ `reason` dans `PullUpToDate`** — l'information deviendrait optionnelle à consulter ; une variante distincte force le `switch` exhaustif sur la `sealed class` à traiter le cas.
- **Lever une exception** — l'absence de snapshot est un état normal (bibliothèque fraîchement liée, jamais poussée), pas une erreur.
- **Laisser l'appelant sonder `hasRemoteSnapshot` avant chaque pull** — un aller-retour API supplémentaire et une fenêtre de course entre le sondage et le pull.

## Conséquences

- Toute nouvelle variante de `PullOutcome` fera échouer la compilation des `switch` existants — c'est l'effet recherché, ne pas le contourner par un `default`.
- Un `PullNoRemoteSnapshot` ne doit **jamais** être présenté à l'utilisateur comme « synchronisé », ni avancer `lastSyncedAt`.
- `hasRemoteSnapshot` teste désormais la présence d'un **manifest** en priorité (les blobs portant un nom unique depuis [0007](0007-publication-de-snapshot-par-blob-unique.md)), avec repli sur les noms de fichiers historiques.
- `_pullLibrary` propage la révision réellement atteinte dans `PullStaged`, et non la révision d'avant l'opération.
