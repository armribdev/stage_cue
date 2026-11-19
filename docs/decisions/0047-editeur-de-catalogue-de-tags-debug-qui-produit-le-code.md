# 0047 — Éditeur de catalogue de tags réservé au développeur : il modifie la base locale et produit la déclaration du code

**Statut :** acceptée (précise 0046)
**Date :** 2026-11-19

## Contexte

Faire évoluer le catalogue de tags (créer, renommer, gérer les alias, fusionner, supprimer) demandait d'éditer `database_tag_seed.dart` à la main, sans voir combien de sons portent chaque tag ni l'effet d'une fusion. Mais la 0046 fait du catalogue **du code** la seule source de vérité : la base s'y réaligne à chaque ouverture et les utilisateurs ne reçoivent un tag que par une version de l'app. Un éditeur qui n'écrirait que dans la base n'aurait donc aucun effet livré (et un tag du catalogue supprimé à la main serait recréé au lancement suivant).

## Décision

Un éditeur **debug seulement** (`kDebugMode`, Réglages → Maintenance → « Catalogue de tags (développement) ») applique chaque modification à la base locale, pour en voir l'effet avec les vrais usages, **et** en déduit la déclaration Dart à coller dans le catalogue (`_extraTagCatalog`, `mergedTags`, `prunedTags`) : « Copier le code ». Le catalogue du code reste la seule source de vérité ; l'éditeur est un assistant d'écriture, pas un second catalogue.

## Alternatives écartées

- **Éditeur qui n'écrit que dans la base** — sans effet pour les utilisateurs, et défait par `reconcileTagCatalog` au lancement suivant pour tout tag encore déclaré.
- **Catalogue en données** (JSON ou table synchronisée), modifiable sans rebuild — renverse la 0046, impose un format, une synchro et des conflits entre appareils ; le besoin ne concerne que le développeur.
- **Éditeur disponible en release** — rien de ce qu'il fait n'est livré tant que le code n'est pas modifié ; exposer cela aux utilisateurs serait trompeur (et la 0046 leur interdit de créer ou supprimer des tags).

## Conséquences

- Rien n'est écrit dans le code par l'éditeur : il faut **coller** l'extrait (les modifications ne vivent qu'en mémoire et dans le journal, une ligne par événement ; fermer l'éditeur sans copier demande confirmation). Tant que ce n'est pas fait, la base locale diverge du catalogue ; un pull Drive d'un appareil en retard peut recréer un tag retiré, jusqu'à ce que le code livre sa déclaration.
- `renderTagCatalogSnippet` compacte la session : un tag créé puis renommé ou supprimé ne laisse que son état final, une chaîne de fusions A → B → C se réécrit A → C (sinon `mergedTags` viserait un accueil absent du catalogue), et supprimer l'accueil d'une fusion élague le tag fusionné. Un alias **retiré** ne se déclare nulle part (la réconciliation ajoute, ne retire jamais) : l'extrait le signale en commentaire, à retirer à la main du catalogue.
- Un renommage est une fusion vers le nouveau nom (l'ancien nom devient alias) : c'est la seule forme qui s'exprime avec les déclarations existantes, et celle qui conserve les usages chez les utilisateurs.
- Les tags visés par une ambiance de l'analyse automatique (`isMoodTag`, `kMoods`) ne se renomment, ne se fusionnent ailleurs et ne se suppriment pas : l'analyse les retrouve par nom ; seuls leurs alias se modifient.
- Les écritures vivent dans `LocalTagEditingDataSource` (et `AppDatabase.mergeTagInto`, qui expose le moteur de `mergedTags`) ; l'écran lit ce datasource directement, sans repository : l'outil n'existe qu'en debug.
- Les catégories ne sont pas éditables ici (couleur, ordre et affinité de type, `kTagCategorySoundTypes`, sont des choix de conception).
