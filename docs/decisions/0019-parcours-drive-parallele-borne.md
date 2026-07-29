# 0019 — Parcours Drive en largeur, parallélisme borné, complet ou rien

**Statut :** acceptée
**Date :** 2026-07-30

## Contexte

`_collectDriveAudioFiles` descendait en profondeur d'abord et attendait le listing de chaque dossier avant de passer au frère suivant : une bibliothèque de 80 dossiers coûtait 81 allers-retours Drive mis bout à bout. Une fois le coût local réglé ([0018](0018-journalisation-wal-et-synchronous-normal.md) et l'écriture par lots), c'était la totalité du budget de lancement — mesure à 250 ms d'aller-retour simulé : **20,3 s** passées à attendre le réseau, CPU au repos.

## Décision

Parcours en **largeur**, un niveau à la fois, avec au plus `_driveListingConcurrency` (5) listings en vol via un `_mapBounded` qui préserve l'ordre des résultats. Même mesure après : **4,7 s** (4,3×), pour un nombre de requêtes inchangé.

## Alternatives écartées

- **Un seul `files.list` à plat sur tout le corpus visible, arbre reconstruit depuis `parents`** — c'est le gain maximal (O(total/1000) requêtes au lieu de O(dossiers)), et c'est précisément pourquoi il a été envisagé. Écarté pour son **profil d'échec** : le parcours par dossier échoue bruyamment (une erreur de listing lève), alors qu'un listing à plat qui retournerait silencieusement un sous-ensemble — quirk de visibilité du scope `drive.file`, page manquée — ressemblerait à un scan réussi et complet. Or `_indexDriveFolder` déduit l'existence d'un fichier de sa présence dans le résultat : un scan partiel pris pour complet ne fait pas *afficher moins* de sons, il en fait **supprimer**, en base et en cache. Inacceptable sur une app de déclenchement live, et invisible en développement (ne se manifesterait que sur une grosse bibliothèque en production).
- **Pool global couvrant toute la profondeur (workers tirant d'une file partagée)** — parallélise aussi entre niveaux, mais complexifie la détection de fin et le traitement des erreurs. Le parcours par niveau capte l'essentiel du gain : les bibliothèques réelles sont larges (beaucoup de dossiers frères), pas profondes.
- **Tenir un slot de concurrence pendant la récursion d'un dossier** — interblocage garanti : les parents occuperaient tous les slots en attendant leurs enfants, qui ne pourraient jamais démarrer. Le parcours par niveau rend la faute impossible par construction (un slot ne couvre qu'un seul `listFolder`).

## Conséquences

- **« Complet ou rien » est une propriété de sûreté, pas un détail d'implémentation.** Toute erreur de listing doit continuer à faire échouer le scan entier. Ne jamais entourer un listing d'un `catch` qui poursuivrait le parcours : le résultat alimente `pruneSoundsAbsentFromDrive`, et un dossier injoignable serait lu comme « ces fichiers ont été supprimés sur Drive ». C'est aussi ce qui permet à `AutoSyncCoordinator` de sauter le pull d'une bibliothèque mal indexée ([0005](0005-ordre-de-synchronisation-au-lancement.md)). Verrouillé par le test « COMPLET OU RIEN » de `library_repository_index_test.dart`.
- L'ordre des résultats passe de profondeur d'abord à largeur d'abord. Rien n'en dépend aujourd'hui (les consommateurs construisent des ensembles ou des maps) — ne pas introduire de dépendance à cet ordre.
- `listFolder` est idempotent : son réessai sur erreur transitoire reste assuré par `_guardRetry` ([0012](0012-retry-drive-limite-aux-appels-idempotents.md)). Ne pas ajouter de réessai dans `_mapBounded`, ce serait le doubler.
- Relever `_driveListingConcurrency` rapproche des quotas Drive sans gain proportionnel (la profondeur borne déjà le parallélisme utile). Les 429 sont absorbés par le backoff, mais chaque réessai coûte plus cher que la requête économisée.
- Le test de caractérisation compte les appels `listFolder` : la parallélisation ne doit pas changer leur nombre, seulement leur ordonnancement.
