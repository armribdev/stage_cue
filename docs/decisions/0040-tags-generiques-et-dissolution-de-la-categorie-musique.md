# 0040 — Tags génériques, et dissolution de la catégorie MUSIQUE

**Statut :** acceptée
**Date :** 2026-11-18

## Contexte

Le catalogue de tags était maigre, et la catégorie `MUSIQUE` n'en portait que 5 (Chant, Instrumental, Lent, Rythmé, Musique d'ambiance). Son nom se confondait avec le `SoundType.music` (qui pilote les voies audio), et la voix comme le tempo se posent aussi bien sur un bruitage que sur une musique. Par ailleurs, ajouter un tag pour chaque objet ou lieu précis (Train, Taverne…) ne sert à rien : le titre du fichier le porte déjà.

## Décision

1. **Un tag est une famille générique**, pas un nom que le titre du fichier portera. Les noms précis deviennent des **alias** (Train, Moto, Avion → alias de `Véhicule` ; Cloche, Sonnette, Réveil → alias de `Sonnerie`).
2. **La catégorie `MUSIQUE` est dissoute** dans `EMOTION_STYLE` (migration v48). Ses tags sont déplacés, pas recréés : même id, donc `sound_tags` et `sound_auto_tags` restent valides. Un doublon dans la catégorie d'accueil est fusionné. Il reste **5 catégories**.
3. Le catalogue est étendu dans les cinq catégories (`_extraTagCatalog`), avec en plus des tags de provenance et de statut d'une musique : `Remix`, `Reprise` (alias `cover`), `BO` (alias `ost`, `soundtrack`, `bande originale`), `Kitsch` (alias `cheesy`), `Célèbre` (alias `connu`, `tube`, `hit`).
4. Les alias viennent de l'analyse des mots des titres de sons (`docs/analyses/mots-des-titres`, non versionnée) : anglais (rain, dark, epic…), fautes courantes (sonette) et familles récurrentes. `Animal` (OBJET) remplace l'ancienne règle « pas de tag d'animaux » : une famille de ~40 sons, dont chaque nom est un alias.

## Alternatives écartées

- **Renommer la catégorie en « Voix / tempo »** — lève la confusion de nom mais garde une catégorie de plus (une couleur de plus à distinguer) pour 4 tags, alors que la recherche ne porte jamais sur les catégories.
- **Étendre `MUSIQUE`** (genres, usage) — la voix, le tempo et l'ambiance se cherchent tous d'un mot ; les genres retombent dans `EMOTION_STYLE` ou en alias.
- **Un tag par nom précis** — redondant avec le titre, et la liste ne finit jamais.
- **Supprimer « Musique d'ambiance » sans condition** — effacerait un tag déjà posé sur des sons. Il est supprimé **seulement s'il est inutilisé**, sinon conservé dans `EMOTION_STYLE` ; une installation neuve ne le crée plus (redondant avec `SoundType`).

## Conséquences

- Toute nouvelle catégorie retirée s'ajoute à `retiredTagCategories` (`database_tag_seed.dart`) : `reconcileTagCatalog` la dissout, à la migration comme après chaque import de snapshot (un appareil encore en v47 qui publie un son tagué « Chant » recréerait sinon `MUSIQUE` et un doublon à chaque pull). Voir [0043](0043-catalogue-de-tags-reconcilie-apres-chaque-import.md).
- Les anciennes migrations (v32, v42) créent encore `MUSIQUE` ; la v48 nettoie derrière elles. Ne pas retirer `_ensureMusicCategoryTags`.
- Les nouveaux tags d'`EMOTION_STYLE` sont **manuels** : l'analyse automatique ne suggère que les ambiances de `kMoods` (cf. [0029](0029-analyse-automatique-des-tags-sur-l-appareil.md)). La voix et le tempo n'étaient déjà pas suggérés.
- Les tags trop précis de l'ancien seed sont retirés en v48 (`mergedTags`, `_prunedTags`) : Chaise, Table et Lit vont dans Meuble, Voiture dans Véhicule, Téléphone dans Machine, le « Verre » d'OBJET dans celui de MATIERE. Usages, suggestions et alias suivent ; leur nom devient un alias de la famille. Livre, Fenêtre et Clés n'ont pas de famille : supprimés seulement s'ils ne sont posés sur aucun son. Une base neuve ne les crée plus.
- **Voix, déplacements et lieux généralisés** (même voie, `mergedTags`) : les verbes d'`ACTION` qui décrivent une voix ou un déplacement deviennent des alias de deux nouvelles familles — `Voix` (rire, pleurer, crier, chuchoter, siffler, applaudir) et `Déplacement` (marcher, courir, sauter, glisser). `Impact` absorbe les coups, les détonations et les chocs qui cassent ou claquent (Frapper, Exploser, Casser, Claquer), et Ouvrir et Fermer ne font plus qu'un tag, `Ouvrir/Fermer`. Lancer et Actionner restent des tags à part. Verser, Secouer, Déchirer et Frotter sont supprimés (`_prunedTags` : conservés seulement s'ils sont posés sur un son). Dans `AMBIANCE`, Forêt, Montagne, Désert et Campagne vont dans `Nature`, Aube dans `Jour`, Crépuscule dans `Nuit`, Foule dans `Public`, Post-apocalyptique dans `Futuriste`. Les usages et les alias suivent. Une base neuve ne crée plus ces tags (absents de `_seedDefaultTagsIfEmpty`, leurs mots sont dans `_extraTagCatalog`).
- Les tags précis restants (Porte, Pluie…) sont conservés tels quels : en retirer d'autres se fait par la même voie, jamais sans migrer les usages. `MATIERE`, `EMOTION_STYLE` et les époques (Années 20…90, Médiéval…) n'ont pas été touchés.
