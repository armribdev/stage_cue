# Tags et catégories de tags

Référence de ce que sert chaque catégorie. Les tags permettent de retrouver un
son vite, en direct, en tapant un ou deux mots dans le sélecteur de sons.

## Principe

- **La recherche porte sur les tags, jamais sur les catégories.** Elle compare
  le texte saisi au nom du tag et à ses alias (accents et casse ignorés,
  tolérance aux fautes de frappe). Une catégorie n'est donc ni un critère de
  recherche ni une facette.
- **Une catégorie ne sert qu'à deux choses** : la couleur des chips d'un tag
  (sélecteur de sons, écran de pad, bibliothèque) et les puces de filtre du
  panneau de l'éditeur de tags. Son rôle est d'aider à *poser* des tags, pas à
  les retrouver.
- **Peu de catégories, volontairement.** Comme on ne cherche pas par catégorie,
  en ajouter coûte une couleur de plus à distinguer pour un gain faible. Ne pas
  scinder une catégorie large (voir AMBIANCE) : si sa liste devient longue,
  ajouter des alias plutôt que des catégories.
- **Un tag est une famille générique, pas un nom précis.** Ce que le titre du
  fichier porte déjà (« train », « cloche », « taverne ») n'a pas besoin d'un tag :
  c'est un **alias** de la famille (Véhicule, Sonnerie…). Avant d'ajouter un tag,
  se demander s'il sera dans le titre ([0040](decisions/0040-tags-generiques-et-dissolution-de-la-categorie-musique.md)).
- **Les alias portent la recherche.** Un synonyme courant (« bagnole » →
  Véhicule, « tir » → Impact) vaut mieux qu'un tag de plus. Un alias est unique
  sur toute la base (`tag_aliases.normalized_alias`).
- **Les tags qualifient le contenu, pas la voie audio.** Musique / ambiance /
  bruitage est déjà porté par `SoundType` (qui pilote les voies audio et le
  filtre du sélecteur) : ne pas le redoubler par un tag.

## Les cinq catégories

| Clé en base | Libellé affiché | Sert à décrire | Exemples |
|---|---|---|---|
| `ACTION` | Actions | Le geste joué sur scène, en familles pour la voix et le déplacement (le verbe précis est dans le titre) | Voix, Déplacement, Impact, Ouvrir/Fermer, Lancer |
| `OBJET` | Objets | La famille d'accessoire utilisée ou évoquée | Porte, Arme, Véhicule, Machine, Sonnerie |
| `MATIERE` | Matières | La texture sonore, quand l'objet précis manque | Bois, Métal, Feu, Glace, Végétal |
| `AMBIANCE` | Ambiances | Le décor sonore : lieu, météo, moment, époque, genre, foule | Pluie, Nature, Nuit, Souterrain, Sacré, Western |
| `EMOTION_STYLE` | Émotion / style | L'ambiance d'une scène ou d'une musique : émotion, énergie, style, voix, tempo, statut | Tension, Joyeux, Combat, Chant, Lent, Remix, Kitsch, Célèbre |

Les alias couvrent aussi l'anglais et les fautes courantes des titres
(`rain` → Pluie, `sonette` → Sonnerie, `dog` → Animal) : les banques de sons
sont souvent nommées en anglais.

### AMBIANCE est large par choix

Elle mélange lieu, météo, moment, époque et genre. C'est voulu : ces axes se
cherchent tous de la même façon (un mot) et les séparer multiplierait les
catégories sans rien apporter à la recherche.

### Il n'y a plus de catégorie « Musique »

Elle a été dissoute en v48 ([0040](decisions/0040-tags-generiques-et-dissolution-de-la-categorie-musique.md)) :
son nom se confondait avec le type de son, et voix / tempo se posent aussi bien
sur un bruitage. Chant, Instrumental, Lent et Rythmé sont dans `EMOTION_STYLE`,
avec ce qui qualifie une musique à l'usage : Remix, Kitsch, Célèbre.

On cherche une musique par l'ambiance qu'elle installe (« joyeux »,
« angoisse », « nostalgique »), jamais par son instrumentation : pas de tag
d'instrument (Piano, Cordes, Guitare… posés par la v41, retirés en v42 sauf
ceux déjà posés sur un son). Le vocabulaire d'ambiance musicale vient des mots
que l'on met déjà dans les noms de fichiers de musique (Nostalgie, Joie,
Triste, Angoisse, Tension…). Les animaux, eux, ont un seul tag générique
(`Animal`, dans OBJET) : chat, cochon, oiseaux… en sont des alias.

## Où ça vit dans le code

- Seed initial et migrations de données : `lib/core/database/database_tag_seed.dart`
  (`_seedDefaultTagsIfEmpty`, `_extraTagCatalog` et `_ensureExtraTags`). Il n'existe pas de création
  de tag ou de catégorie depuis l'interface : tout nouveau tag passe par une
  migration de données. Retirer un tag ou une catégorie se déclare **une fois**,
  dans `retiredTagCategories`, `mergedTags` ou `prunedTags` :
  `AppDatabase.reconcileTagCatalog` les applique à la migration et après chaque
  import de snapshot ([0043](decisions/0043-catalogue-de-tags-reconcilie-apres-chaque-import.md)).
  Sans cela, un appareil en retard recrée le tag retiré à chaque synchro.
- Libellés affichés : `TagCategoryUi.displayLabel`
  (`lib/features/sampler/presentation/utils/tag_category_ui.dart`). Une clé non
  listée retombe sur son nom en casse de phrase ; toute nouvelle catégorie doit
  y recevoir son libellé.
- Recherche : `LocalTagDataSource.findSoundIdsByTagQuery`
  (`lib/features/sampler/data/datasources/local_tag_datasource.dart`) et
  l'instantané mémoire `SoundSearchIndex` (voir
  [0017](decisions/0017-index-de-recherche-en-memoire.md)).

## Tags de l’IA

Sur un poste de bureau, une analyse du son (modèle embarqué, voir
[0029](decisions/0029-analyse-automatique-des-tags-sur-l-appareil.md) et
[0030](decisions/0030-tags-de-l-ia-en-couche-separee-et-masquables.md) et
[0031](decisions/0031-tags-de-l-ia-en-suggestions-avec-score.md)) **suggère** des
tags d’ambiance (`EMOTION_STYLE`) pour les **musiques**, d’après l’audio, dès
qu’elles sont indexées et que leur fichier est sur l’appareil. Elle exige le pack de
modèles (Paramètres → Analyse automatique, ~480 Mo).

Une suggestion **n’est pas un tag** :

- **les tags du son** (`sound_tags`) : ajoutés et retirés librement ; ce sont les seuls
  que lisent la recherche, les listes et le sélecteur ;
- **les suggestions de l’IA** (`sound_auto_tags`) : toujours affichées dans la fiche du
  son, de la plus à la moins sûre (le score ordonne les pastilles mais n’est pas affiché,
  [0042](decisions/0042-suggestions-de-l-ia-sans-pourcentage.md)). Toucher une
  pastille l’ajoute aux tags du son (enregistré avec le formulaire), la retoucher la
  retire. Le score est une confiance **relative**, pas une probabilité calibrée.

- **Quels tags** : Joyeux, Triste, Nostalgique, Épique, Angoisse, Tension, Mystérieux,
  Romantique, Calme, Magie, Sombre, Énergique, Léger, Drame. Au plus 3 par son, et
  seulement ceux qui ressortent nettement par rapport au reste de la bibliothèque
  analysée : mieux vaut aucune suggestion qu’une mauvaise. Rien n’est suggéré tant que 50
  musiques n’ont pas été analysées.
- **Passer un son en « traité » fige ses suggestions** : l’IA ne l’analyse plus. Elle ne touche
  jamais un bruitage ni une ambiance.
- Voix (Chant / Instrumental) et tempo (Lent / Rythmé) **ne sont pas** suggérés
  automatiquement (tempo : inutilisable ; voix : suite possible, cf. 0029). Il en
  va de même des tags ajoutés en v48 (Menaçant, Combat, Remix…) : manuels.
- **Ajouter une ambiance** : un tag nouveau passe par une migration de données comme
  d’habitude ; il faut en plus une ligne dans `kMoods` (`lib/core/autotag/mood_tagging.dart`)
  et le vecteur texte correspondant dans `assets/autotag/text_latents.f32`
  (`tool/autotag/gen_text_latents.py`, **même ordre**). Les empreintes déjà calculées
  servent telles quelles : pas de ré-analyse des fichiers.

## Tags déduits du titre

Pour **tous les types de sons** (musiques, bruitages, ambiances), le titre propose des tags
([0041](decisions/0041-tags-deduits-du-titre-calcules-a-la-volee.md)) : un mot entier du titre
qui est le nom d'un tag ou l'un de ses alias (« Sonette porte » → Sonnerie, Porte). Rien n'est
stocké ni synchronisé : le calcul se refait à l'ouverture de la fiche, d'après le catalogue du
moment. Ajouter un alias améliore donc aussitôt les suggestions.

- **Dans la fiche d'un son** : pastilles sans score (survol : le mot trouvé), à côté de
  celles de l'IA. Les ajouter suit l'enregistrement du formulaire.
- **En masse** : bouton « Tags des titres » de l'encart de la file « À traiter ». Aperçu par son,
  chaque tag se retire d'un toucher, puis seuls les tags conservés sont **ajoutés** aux sons non
  traités (jamais remplacés), qui restent à traiter.
- Mots entiers uniquement, accents/casse/pluriel simple ignorés, au plus 4 tags par son. Les mots
  trop ambigus (`pas`, `theme`, `mix`, `hit`) restent des alias de recherche mais ne déduisent
  rien d'un titre (`kAmbiguousTitlePhrases`, `lib/core/utils/title_tag_matcher.dart`).

## Pistes d'amélioration (non décidées)

- **Suggérer d'après les tags que l'utilisateur a déjà posés** (voisinage d'empreintes). Pour une
  musique non traitée, chercher ses *k* plus proches voisines (empreinte `sounds.auto_embedding`)
  parmi les musiques déjà taguées dans `sound_tags`, et suggérer les tags qu'elles portent ; le
  score devient « *n* voisines sur *k* », donc vérifiable, contrairement au softmax de
  [0031](decisions/0031-tags-de-l-ia-en-suggestions-avec-score.md). Apports : marche pour **tout**
  tag posé (Chant, Lent, BO…, pas seulement les ambiances de `kMoods`), et s'améliore à mesure
  que l'utilisateur tague. Les ambiances zero-shot resteraient le démarrage à froid.
  - **Prérequis** : environ 5 à 10 musiques taguées par tag, soit 50 à 100 au total (ordre de
    grandeur, non mesuré). L'action « Tags des titres » peut les produire.
  - **Limites** : musiques seulement (les bruitages n'ont pas d'empreinte) ; il faudrait un ADR
    qui amende 0031. L'utilisateur avait écarté « entraîner sur ses propres exemples » faute
    d'exemples : cette piste n'est à rouvrir que quand le volume y est.
- **Calibrer le score de l'IA** d'après l'usage : une ligne de `sound_auto_tags` plus la présence
  du tag dans `sound_tags` donnent le taux d'acceptation par tranche de score. Le pourcentage a
  été retiré de l'affichage ([0042](decisions/0042-suggestions-de-l-ia-sans-pourcentage.md)) ; à
  mesurer avant de décider s'il faut réafficher une valeur.
