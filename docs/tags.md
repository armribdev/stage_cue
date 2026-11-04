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
- **Les alias portent la recherche.** Un synonyme courant (« bagnole » →
  Voiture, « tir » → Exploser) vaut mieux qu'un tag de plus. Un alias est unique
  sur toute la base (`tag_aliases.normalized_alias`).
- **Les tags qualifient le contenu, pas la voie audio.** Musique / ambiance /
  bruitage est déjà porté par `SoundType` (qui pilote les voies audio et le
  filtre du sélecteur) : ne pas le redoubler par un tag.

## Les six catégories

| Clé en base | Libellé affiché | Sert à décrire | Exemples |
|---|---|---|---|
| `ACTION` | Actions | Le geste ou le verbe joué sur scène | Casser, Claquer, Marcher, Rire, Applaudir |
| `OBJET` | Objets | L'accessoire utilisé ou évoqué | Porte, Téléphone, Voiture, Clés |
| `MATIERE` | Matières | La texture sonore, quand l'objet précis manque | Bois, Métal, Eau, Gravier |
| `AMBIANCE` | Ambiances | Le décor sonore : lieu, météo, moment, époque, genre, foule | Pluie, Forêt, Nuit, Médiéval, Horreur, Foule |
| `EMOTION_STYLE` | Émotion / style | L'ambiance d'une scène ou d'une musique : émotion, énergie, style | Tension, Joyeux, Nostalgique, Angoisse, Calme, Épique |
| `MUSIQUE` | Musique | Ce qui distingue une musique à l'usage : voix et tempo | Chant, Instrumental, Lent, Rythmé |

Un même mot peut exister dans deux catégories quand il désigne deux choses
distinctes : « Verre » est à la fois un OBJET (le gobelet) et une MATIERE (le
bruit du verre).

### AMBIANCE est large par choix

Elle mélange lieu, météo, moment, époque et genre. C'est voulu : ces axes se
cherchent tous de la même façon (un mot) et les séparer multiplierait les
catégories sans rien apporter à la recherche.

### MUSIQUE : voix et tempo, pas l'ambiance ni les instruments

On cherche une musique par l'ambiance qu'elle installe (« joyeux »,
« angoisse », « nostalgique »), jamais par son instrumentation : l'ambiance se
pose donc avec `EMOTION_STYLE`, qui sert aussi aux bruitages, et `MUSIQUE` ne
garde que la voix (Chant / Instrumental) et le tempo (Lent / Rythmé). Les
instruments (Piano, Cordes, Guitare…) posés par la v41 ont été retirés en v42,
sauf ceux déjà posés sur un son.

Le vocabulaire d'ambiance musicale vient des mots que l'on met déjà dans les
noms de fichiers de musique (Nostalgie, Joie, Triste, Angoisse, Tension…). Pas
de tag d'animaux ni de « Feu » : volontairement écartés.

## Où ça vit dans le code

- Seed initial et migrations de données : `lib/core/database/database.dart`
  (`_seedDefaultTagsIfEmpty`, `_extraTagCatalog` et `_ensureExtraTags`). Il n'existe pas de création
  de tag ou de catégorie depuis l'interface : tout nouveau tag passe par une
  migration de données.
- Libellés affichés : `TagCategoryUi.displayLabel`
  (`lib/features/sampler/presentation/utils/tag_category_ui.dart`). Une clé non
  listée retombe sur son nom en casse de phrase ; toute nouvelle catégorie doit
  y recevoir son libellé.
- Recherche : `LocalTagDataSource.findSoundIdsByTagQuery`
  (`lib/features/sampler/data/datasources/local_tag_datasource.dart`) et
  l'instantané mémoire `SoundSearchIndex` (voir
  [0017](decisions/0017-index-de-recherche-en-memoire.md)).

## Tags posés automatiquement

Sur un poste de bureau, une analyse du son (modèle embarqué, voir
[0029](decisions/0029-analyse-automatique-des-tags-sur-l-appareil.md)) pose des tags
d'ambiance (`EMOTION_STYLE`) sur les **musiques non traitées et sans tag**, à partir de
l'audio. Elle exige le pack de modèles (Paramètres → Analyse automatique, ~480 Mo).

- **Quels tags** : Joyeux, Triste, Nostalgique, Épique, Angoisse, Tension, Mystérieux,
  Romantique, Calme, Magie, Sombre, Énergique, Léger, Drame. Au plus 3 par son, et
  seulement ceux qui ressortent nettement par rapport au reste de la bibliothèque
  analysée : mieux vaut aucun tag qu'un mauvais. Rien n'est posé tant que 50 musiques
  n'ont pas été analysées.
- **Jamais** sur un son déjà traité ou déjà tagué, ni sur un bruitage ou une ambiance.
  Voix (Chant / Instrumental) et tempo (Lent / Rythmé) **ne sont pas** posés
  automatiquement (tempo : inutilisable ; voix : suite possible, cf. 0029).
- **Le son reste « non traité »** : ouvert dans le formulaire d'édition, il affiche
  « Tags posés automatiquement d'après le son » ; on retire un tag par sa croix, puis
  on valide.
- **Ajouter une ambiance** : un tag nouveau passe par une migration de données comme
  d'habitude ; il faut en plus une ligne dans `kMoods` (`lib/core/autotag/mood_tagging.dart`)
  et le vecteur texte correspondant dans `assets/autotag/text_latents.f32`
  (`tool/autotag/gen_text_latents.py`, **même ordre**). Les empreintes déjà calculées
  servent telles quelles : pas de ré-analyse des fichiers.
