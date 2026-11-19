# 0046 — Le catalogue de tags fait foi : la base s'y aligne à chaque ouverture

**Statut :** acceptée (amende 0040 et 0043)
**Date :** 2026-11-19

## Contexte

La réconciliation du catalogue (0043) ne tournait qu'à la migration v48 et après un import de snapshot, et elle **conservait** un tag élagué (`prunedTags`) dès qu'il était posé ou suggéré sur un son. Résultat observé sur une base à jour : `Verser`, `Secouer`, `Frotter` et `Déchirer` y étaient encore alors qu'ils étaient déclarés retirés — la migration était déjà passée avant que la liste ne les contienne, et aucun import ne s'était produit depuis. Rien ne garantissait donc qu'un utilisateur voie le catalogue courant.

Il n'existe aucune création ni suppression de tag dans l'interface : tout tag d'une base vient du catalogue. Le catalogue est la seule source de vérité.

## Décision

1. **Une base ne garde aucun tag que le catalogue ne porte plus.** Un tag de `prunedTags` est supprimé **même posé ou suggéré** sur des sons (ses `sound_tags`, `sound_auto_tags` et alias partent avec). Un tag de `mergedTags` est remplacé par son tag d'accueil, usages et suggestions reportés (inchangé).
2. **`reconcileTagCatalog` s'exécute à chaque ouverture** (`beforeOpen`), en plus de l'import de snapshot. Elle enchaîne dissolution des catégories retirées, création des tags du catalogue (`_ensureExtraTags`), puis retraits : un tag ajouté ou retiré dans une version de l'app arrive chez tous les utilisateurs au prochain lancement, sans nouvelle migration ni `schemaVersion`. La migration v48 n'est plus qu'un appel à cette même méthode.

3. **Premier usage : `Météo`.** `Pluie` et `Orage` sont fusionnés dans un tag `Météo` (`AMBIANCE`), qui porte aussi leurs alias (pluie, orage, tempête, tonnerre, vent, brouillard, grêle…). `Mer` est fusionné dans `Nature` (mer, waves, ocean, sea en alias). `Silence` est élagué (il ne décrit pas un contenu sonore). Cela remplace la mention de `Pluie` comme tag conservé dans 0040.

## Alternatives écartées

- **Garder « supprimé seulement si inutilisé »** (0040/0043) — laisse à jamais un tag retiré dans la liste de l'utilisateur ; une donnée perdue est ici un tag que le catalogue a explicitement abandonné.
- **Une migration (`schemaVersion`) par évolution du catalogue** — oublie les retraits ajoutés après coup, et force un codegen pour une donnée.
- **Un numéro de version du catalogue pour ne réconcilier qu'au changement** — un état de plus à conserver, pour économiser ≈ 12 ms par ouverture (mesuré sur une base mémoire).

## Conséquences

- Retirer un tag détruit les tagging que l'utilisateur lui avait donnés : pour ne rien perdre, **fusionner** dans une famille (`mergedTags`) plutôt qu'élaguer.
- Un tag du catalogue qu'on supprimerait à la main dans la base est recréé au lancement suivant.
- Les noms de `mergedTags` et `prunedTags` restent réservés (0043).
