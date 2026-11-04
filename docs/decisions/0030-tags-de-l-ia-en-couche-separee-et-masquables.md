# 0030 — Tags de l'IA : couche séparée, masquables, jamais supprimés

**Statut :** acceptée (amende [0029](0029-analyse-automatique-des-tags-sur-l-appareil.md)) — amendée par [0031](0031-tags-de-l-ia-en-suggestions-avec-score.md) : les tags de l'IA deviennent des suggestions avec un score, sans masquage, hors recherche tant qu'ils ne sont pas acceptés
**Date :** 2026-11-04

## Contexte

La première version de l'analyse écrivait ses tags dans `sound_tags`, mélangés à ceux
de l'utilisateur, et ne touchait qu'un son non traité **sans aucun tag**. Conséquences :
impossible de savoir qui a posé quoi ; un tag de l'IA retiré par l'utilisateur
disparaissait, donc l'IA pouvait le reposer ; et un son déjà tagué à la main n'était
jamais analysé. L'utilisateur veut au contraire que le résultat de l'IA soit **toujours
conservé en mémoire**, même écarté, et que chaque son ait deux couches : celle de l'IA
(masquable) et la sienne (libre).

## Décision

- **Deux couches.** `sound_tags` reste **les tags de l'utilisateur**, ajoutés et retirés
  librement. Les tags de l'IA vivent dans `sound_auto_tags` (v45) :
  `(sound_id, tag_id, hidden, updated_at)`. Les tags **visibles** d'un son sont l'union
  des deux, sans doublon.
- **Masquer, jamais supprimer.** L'utilisateur masque un tag de l'IA (`hidden = 1`) ou
  le rétablit ; la ligne n'est jamais effacée. Un tag masqué n'est ni affiché ni
  cherché, mais l'IA ne le repose pas, et sa trace voyage avec la synchro.
- **Passer un son en « traité » fige ses tags** : l'IA ne l'analyse plus et n'y ajoute
  rien. Les tags de l'IA déjà posés restent (masquables). Éligible = type musique, non
  traité, jamais analysé, fichier sur l'appareil. Un son qui porte déjà des tags de
  l'utilisateur est analysé aussi : les deux couches coexistent.
- **Posés automatiquement dès l'indexation** : l'analyse se lance après l'insertion de
  sons (délai de grâce de 10 s, repoussé tant que l'indexation continue), en plus de
  chaque passe de synchro et du tick de veille, y compris en usage 100 % local.
- **Synchro** : `sound_auto_tags` est exportée dans le snapshot par dossier, masqués
  compris. Fusion **par union, jamais de suppression**, et pour une paire (son, tag)
  connue des deux côtés la dernière modification (`updated_at`) gagne : c'est ce qui
  propage un masquage ou un rétablissement. Un snapshot sans cette table (appareil plus
  ancien) laisse les tags locaux intacts, et un appareil ancien ignore la table
  nouvelle. Un son qui a déjà des tags d'IA reçus d'ailleurs n'est pas recalculé.
- **Mémoire de l'analyse** : l'empreinte (`sounds.auto_embedding`, v44) est conservée
  pour tous les sons analysés ; avec `sound_auto_tags`, rien de ce que l'IA a trouvé ne
  se perd.
- **Interface** : le formulaire d'un son affiche ses tags de l'utilisateur (éditeur
  habituel) puis une zone « Trouvés par l'IA » : pastilles à masquer d'un geste, puis
  la liste des masqués, à rétablir. Le masquage s'écrit tout de suite (hors baseline
  `dirty`) ; enregistrer n'écrit **jamais** un tag de l'IA dans `sound_tags`.

## Alternatives écartées

- **Colonne `origin` sur `sound_tags`** — mélange les deux couches dans une table que
  chaque lecteur devrait filtrer, impose un masquage dans un format partagé, et le
  « remplace tout le dossier » du pull effacerait les tags de l'IA non encore publiés.
- **Supprimer le tag quand l'utilisateur le retire** — c'est exactement ce qui faisait
  perdre la mémoire et laissait l'IA reposer un tag écarté.
- **Tags de l'IA locaux à l'appareil, hors snapshot** — un appareil sans modèle (mobile)
  n'en verrait jamais, et le masquage ne suivrait pas l'utilisateur.
- **Ne plus analyser un son dès qu'il porte un tag à la main** — contredit « chaque son
  a des tags de l'IA et des siens » ; c'est le statut « traité » qui fige.

## Conséquences

- **Remplace dans 0029** : « les tags sont appliqués directement » dans `sound_tags`,
  « jamais sur un son qui porte déjà des tags », le bandeau « tags posés
  automatiquement », la réouverture de décision après un pull (devenue inutile : le pull
  ne touche plus aux tags de l'IA) et la mention « hors snapshot » de `auto_tagged_at`
  (les marques `auto_tagged_at` et l'empreinte restent, elles, locales).
- **L'indexation n'a pas toujours le fichier** : l'indexation Drive est métadonnées
  seules, donc un son non téléchargé n'est analysé qu'une fois son fichier présent
  (passe suivante, tick de veille ou nouvelle insertion). Les sons d'une bibliothèque
  locale le sont dans la foulée.
- **Seuil de 50 sons analysés** : tant que la bibliothèque analysée est plus petite,
  aucun tag n'est posé (moyennes instables) ; les premiers reçoivent leurs tags
  d'un coup au 50ᵉ.
- **Écran de détail d'un pad** : son éditeur de tags ne montre que les tags de
  l'utilisateur ; les tags de l'IA se voient et se masquent dans le formulaire du son
  (bibliothèque et sélecteur). Les listes et la recherche, elles, utilisent les tags
  visibles des deux couches.
- Schéma v45 et format de snapshot étendu (table optionnelle) ; compatible dans les deux
  sens avec les versions précédentes.
