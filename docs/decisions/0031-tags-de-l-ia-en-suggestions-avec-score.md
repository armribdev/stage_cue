# 0031 — Tags de l'IA : des suggestions toujours affichées, avec leur score

**Statut :** acceptée (amende [0030](0030-tags-de-l-ia-en-couche-separee-et-masquables.md) et [0029](0029-analyse-automatique-des-tags-sur-l-appareil.md))
**Date :** 2026-11-04

## Contexte

[0029](0029-analyse-automatique-des-tags-sur-l-appareil.md) posait les tags de l'IA
comme de vrais tags (« suggestions à valider » y était écartée), et
[0030](0030-tags-de-l-ia-en-couche-separee-et-masquables.md) les a mis à part mais
comptés dans la recherche et les listes, que l'utilisateur pouvait **masquer**. À
l'usage, l'utilisateur veut l'inverse : l'IA **suggère**, et ses suggestions restent
toujours visibles, avec une mesure de la confiance du modèle, pour qu'il juge lui-même.

## Décision

- **Une suggestion n'est pas un tag.** `sound_auto_tags` porte maintenant
  `(sound_id, tag_id, score, updated_at)` ; la colonne `hidden` disparaît (schéma v46).
  Le masquage et le rétablissement sont supprimés : une suggestion est **toujours
  affichée**.
- **Accepter = ajouter aux tags du son.** Dans le formulaire du son, une pastille par
  suggestion (« Triste 38 % », de la plus à la moins sûre) ; la toucher l'ajoute aux tags
  de l'utilisateur (`sound_tags`), la retoucher la retire. Rien n'est écrit en base au
  tap : l'ajout suit l'enregistrement du formulaire, comme n'importe quel tag. La ligne
  de suggestion reste en base, acceptée ou non.
- **Recherche, listes et sélecteur ne lisent que les tags de l'utilisateur.** Les
  suggestions n'y comptent qu'une fois acceptées. `getVisibleTagsForSound` disparaît ;
  `getTagsForSound`, `getTagsForAllSounds` et `findSoundIdsByTagQuery` ne lisent que
  `sound_tags`.
- **Le score** (0 à 1) est la part de l'ambiance dans la **répartition du son** :
  softmax des écarts réduits (z) des 15 ambiances sur la bibliothèque analysée ; deux
  ambiances qui pointent vers le même tag (Sensuel et Romantique) s'additionnent. Les
  règles de sélection ne changent pas (z ≥ 1,0, 3 suggestions au plus, rien avant 50
  sons analysés). C'est une **confiance relative** — « cette ambiance domine-t-elle les
  autres pour ce son » —, **pas une probabilité calibrée** : aucune vérité terrain ne
  permet de la calibrer, et l'interface le dit.
- **Une ligne est écrite une fois** par l'analyse et ne change plus ; l'éligibilité
  (musique, non traitée) et le gel par « traité » restent ceux de 0030.
- **Synchro** : le snapshot exporte `(sound_id, tag_id, hidden = 0, score, updated_at)`.
  `hidden` n'existe plus localement mais reste publié à 0 pour qu'un appareil resté en
  v45, qui le lit à la fusion, ne voie pas son pull échouer. Fusion inchangée : union,
  dernière écriture gagnante (`updated_at`), jamais de suppression. Un snapshot **sans**
  `score` (appareil en v45) est ignoré avec une ligne de journal : ses tags de l'IA
  étaient des tags à part entière, sans confiance.
- **Migration v46** : la table de la v45, jamais publiée, est recréée vide ; les sons
  qui ont une empreinte voient leur décision rouverte (`auto_tagged_at = NULL`), donc
  leurs suggestions sont recalculées au prochain passage **sans ré-analyser le
  fichier**. Les sons écartés (format…) gardent leur marque.

## Alternatives écartées

- **Garder le masquage en plus** — contredit « toujours affichés », et la mémoire de ce
  qui a été écarté n'a plus d'usage : l'IA ne repose rien, la ligne est écrite une fois.
- **Centile dans la bibliothèque** (« plus marqué que 84 % de vos sons ») — stable, mais
  se lit comme une certitude alors que ce n'en est pas une ; le softmax est plus sévère
  et reflète la concurrence entre ambiances d'un même son.
- **Garder les suggestions cherchables** — une suggestion non validée polluerait la
  recherche de tags qu'aucun humain n'a confirmés.
- **Convertir en tags les tags de la v45** — la v45 n'a pas été publiée, aucune donnée
  d'utilisateur à préserver.

## Conséquences

- **Remplace dans 0030** : le masquage / rétablissement, l'union des tags visibles pour
  l'affichage et la recherche, la zone « Trouvés par l'IA » à masquer, et le principe
  « une ligne d'IA n'est jamais supprimée parce qu'on la masque ».
- Le score n'est **pas calibré** : si on veut un jour des pourcentages qui veulent dire
  « x % de chances d'être juste », il faut une vérité terrain (tags acceptés/refusés par
  l'utilisateur sont un candidat) et un étalonnage — hors de cette décision. La
  température du softmax (1,0) est un choix par défaut, non validé.
- Schéma v46 ; format de snapshot : colonne `score` ajoutée, `hidden` figée à 0.
