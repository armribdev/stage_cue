# 0017 — Index de recherche en mémoire, servi périmé puis rafraîchi

**Statut :** acceptée
**Date :** 2026-07-30

## Contexte

Sur une bibliothèque d'environ 1100 sons, chaque ouverture du sélecteur de sons
(Ctrl+F en spectacle) affichait un écran de chargement de plusieurs secondes.
Trois causes cumulées : `getAllSounds()` relu à chaque ouverture ; les tags
chargés par un aller-retour SQL **par son affiché** (N+1, jusqu'à des centaines
de requêtes dès qu'une saisie large matche) ; et surtout la disponibilité locale
calculée en appelant `resolvePlayablePath` séquentiellement sur toute la
bibliothèque — soit, par son, deux lectures de la table `libraries`, une
validation d'en-tête audio, une écriture en base, et pour chaque fichier absent
du cache un **listage complet du dossier parent** via
`PathUnicode.canonicalizeLocalPath`.

## Décision

Un `SoundSearchIndex` tient en mémoire l'instantané de la bibliothèque (sons,
tags de tous les sons, catalogue, disponibilité locale). Le sélecteur adopte
l'instantané **synchronement** s'il existe et déclenche un rafraîchissement en
tâche de fond (*stale-while-revalidate*) : plus jamais d'attente à l'ouverture
passé le premier chargement, que l'index précède l'ouverture (préchauffé à la
fin du chargement de plateau) ou non.

La disponibilité locale passe par une sonde dédiée
(`core/sync/local_availability_probe.dart`) qui parcourt **une fois**
l'arborescence de chaque cache et teste l'appartenance en mémoire, au lieu
d'interroger le disque par son.

## Alternatives écartées

- **Invalider l'index à chaque mutation** — `markSoundPlayed` s'exécute à chaque
  déclenchement de pad : reconstruire l'index à chaque son ferait repartir la
  recherche sur la base précisément en spectacle. Les mutations locales connues
  (favori, dernière lecture, type) patchent donc l'instantané en place via
  `Sound.copyWith` ; seul un changement de masse l'invalide.
- **Cacher `getAllSounds()` dans le repository** — la synchronisation Drive écrit
  les sons directement (`library_snapshot_store.dart`), hors du repository : un
  cache à ce niveau deviendrait périmé sans aucun point d'accroche. Le
  rafraîchissement systématique à l'ouverture couvre ce cas sans avoir à
  recenser tous les points d'écriture.
- **Ne sonder que les sons affichés** — le filtre hors-ligne s'applique *avant*
  la troncature de la liste : sans la disponibilité de toute la bibliothèque, le
  filtre serait faux.
- **Garder `resolvePlayablePath` pour la sonde, mais en parallèle** — la
  concurrence n'enlève ni les écritures en base ni les listages de dossier ; elle
  les rend seulement simultanées.

## Conséquences

- **La sonde en lot est volontairement plus permissive que la lecture.** Elle
  atteste la *présence* du fichier, pas sa validité : pas de contrôle d'en-tête
  audio, pas de contrôle de taille. C'est acceptable parce que toute écriture
  dans le cache est atomique (`.part` puis renommage, [0006](0006-telechargement-atomique-temp-rename.md)),
  donc un fichier présent est complet. Un fichier corrompu reste détecté à la
  lecture, par `resolvePlayablePath`, qui demeure la seule voie du déclenchement.
- **`invalidateSearchIndex()` doit être appelé après tout changement de masse**
  de la bibliothèque (fusion d'un pull Drive, indexation d'un dossier). Sans cet
  appel, la première frame après le changement montre l'ancienne liste — le
  rafraîchissement de fond la corrige, mais l'écart est visible.
- La sonde disque n'est refaite qu'au-delà d'un TTL (30 s) : un téléchargement
  qui vient de finir peut mettre jusqu'à ce délai à se refléter dans le filtre
  hors-ligne.
- Les tags sont chargés en bloc (`getTagsForAllSounds`) : ne pas réintroduire
  d'appel `getTagsForSound` par ligne de résultat dans le sélecteur.
