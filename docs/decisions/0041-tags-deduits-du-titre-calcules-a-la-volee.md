# 0041 — Tags déduits du titre : calculés à la volée, jamais stockés

**Statut :** acceptée
**Date :** 2026-11-18

## Contexte

Presque aucun son n'avait de tag, et l'analyse de l'IA ([0029](0029-analyse-automatique-des-tags-sur-l-appareil.md), [0031](0031-tags-de-l-ia-en-suggestions-avec-score.md)) ne suggère que pour les musiques : un bruitage n'a jamais de suggestion. Or le titre porte presque toujours le mot qui décide du tag (« Sonette porte », « dog-barking-70772 », « Tension - Bizarre - … »), et [0040](0040-tags-generiques-et-dissolution-de-la-categorie-musique.md) a déjà fait des noms précis des alias de tags génériques. Mesuré sur une copie de la bibliothèque (1 200 sons, appariement par mots entiers) : au moins un tag pour 62 % des musiques, 45 % des bruitages et 68 % des ambiances.

## Décision

1. **Les tags déduits du titre se calculent à la volée, sans stockage.** Une fonction pure (`TitleTagMatcher`, `lib/core/utils/title_tag_matcher.dart`) apparie le titre au nom et aux alias de chaque tag, **par mots entiers** (accents, casse et pluriel simple ignorés ; `-`, `_`, apostrophe séparent les mots ; une expression multi-mots prime sur ses mots).
2. **Ce n'est pas l'IA** : ni `sound_auto_tags`, ni score, ni migration, ni format de snapshot. 0029 et 0031 ne sont pas amendées : l'IA continue de ne toucher que les musiques non traitées, et son score garde son sens.
3. **Deux usages**, tous deux soumis à l'utilisateur :
   - la fiche d'un son affiche ces tags en pastilles sans score, dont l'infobulle donne le mot trouvé (à côté de celles de l'IA ; si l'IA propose le même tag, sa pastille avec son score prime). Les ajouter suit l'enregistrement du formulaire ;
   - l'action groupée « Tags des titres » (encart de la file « À traiter ») montre un aperçu par son, où chaque tag se retire d'un toucher, puis n'ajoute que ce qui est confirmé.
4. **L'action groupée n'écrit dans `sound_tags` que sur confirmation, par ajout** (`LocalTagDataSource.addTagsToUnprocessedSounds`, jamais un remplacement), **uniquement sur des sons non traités** (revérifié au moment d'écrire) et **sans les marquer traités**. Un son traité est figé : ni l'action groupée ni l'analyse n'y touchent.
5. Au plus 4 tags par son (`kMaxTitleTagSuggestions`) ; les tags déjà posés sont exclus.
6. **Mots ambigus** : `pas`, `theme`, `mix`, `hit` (`kAmbiguousTitlePhrases`) restent des alias pour la **recherche** mais ne déduisent rien d'un titre (« Ne me quitte pas » → Marcher, « … Theme » → BO étaient du bruit).

## Alternatives écartées

- **Stocker dans `sound_auto_tags`** (colonne `source` ou score fixe, orchestré par `AutoSyncCoordinator`) — la donnée se dérive de ce qui est déjà synchronisé (titre + alias) : ~1 700 lignes redondantes dans les snapshots Drive, figées alors que le catalogue d'alias évolue (une ligne existante n'est jamais modifiée), un score fixe qui mélange deux sens (confiance de l'IA / mot du titre), une migration v49, un format de snapshot que les appareils plus anciens liraient comme des scores de l'IA, et une deuxième marque « décision prise ». Aurait amendé 0029 et 0031.
- **Écrire directement dans `sound_tags` sans aperçu** — une suggestion n'est jamais ajoutée toute seule, et la précision mesurée (~80-85 %, jugée sur un échantillon) ne le permet pas.
- **Retirer les alias ambigus du catalogue** — une migration, et la recherche par ces mots disparaîtrait.

## Conséquences

- Aucune écriture, aucun état : rien à synchroniser, rien à migrer. La fiche suit toujours le catalogue d'alias du moment, donc **ajouter un alias améliore aussitôt les suggestions**.
- Le vocabulaire se lit en deux requêtes (`getTagVocabulary`) ; l'aperçu groupé travaille sur l'instantané de `SoundSearchIndex` ([0017](0017-index-de-recherche-en-memoire.md)), sans requête par son, et invalide l'index après l'écriture.
- Le son ouvert dans le volet d'édition est **exclu** de l'action groupée : sa fiche réécrit ses tags à l'enregistrement et écraserait l'ajout.
- Limites connues : les noms propres restent du bruit (« Philip Glass » → Verre) ; une expression absente du catalogue donne le mot isolé (« Machine gun » → Machine : il manque l'alias `machine gun` sous Arme). Corriger passe par une migration de données (alias), pas par le matcher.
- Un alias ambigu de plus (un mot courant devenu alias d'un tag) se traite en l'ajoutant à `kAmbiguousTitlePhrases`.
