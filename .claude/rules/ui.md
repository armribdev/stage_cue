# UI — direction "Console Linear"

Tout nouveau widget ou écran suit la direction visuelle "Console Linear"
([décision 0023](../../docs/decisions/0023-direction-visuelle-console-linear.md)) :
surfaces quasi noires, un seul accent violet, hairline borders plutôt
qu'elevation, aucun ripple. Les tokens vivent dans
`lib/core/theme/app_tokens.dart` (`AppColors`, `AppFonts`, `AppRadius`,
`AppElevation`, `AppSpacing`, `AppTextStyles`, `AppTypography`) et la
`ThemeData` dans `lib/core/theme/app_theme.dart` — toujours partir de là,
jamais d'une valeur codée en dur qui existe déjà comme token.

## Ce qu'il ne faut jamais faire

- **Ne jamais envelopper une section d'écran/dialogue/formulaire dans un
  `Card`.** C'est le signal Material le plus reconnaissable ("Card-in-dialog") —
  recolorer un `Card` ne suffit pas à le faire disparaître, il faut le
  retirer. Une section = un libellé en petites capitales
  (`AppTextStyles.sectionLabel(context)`, texte en majuscules) suivi
  directement de son contenu, puis un `Divider(height: 1)` avant la section
  suivante. Un `Card`/conteneur bordé reste légitime uniquement pour un
  **item répété** à l'intérieur d'une liste (une ligne de son, un pad, une
  ligne de bibliothèque) — jamais pour grouper tout un formulaire.
- **Ne jamais utiliser les presets typographiques M3 génériques**
  (`textTheme.titleLarge`, `headlineSmall`, etc.) pour un titre de
  dialogue/modale/section : leur échelle est pensée tactile (22px+) et lit
  comme du Material par défaut même repeint. Utiliser une taille explicite
  cohérente avec le reste (16-18px pour un titre de modale, `AppTextStyles.sectionLabel`
  pour un libellé de section) — la réduction desktop (voir plus bas)
  s'applique dessus automatiquement.
- **Ne jamais coder en dur un rayon de coin** qui a un équivalent dans
  `AppRadius` (xs=2, sm=4, md=6, lg=8, `pad`=lg). Les pads utilisent
  spécifiquement `AppRadius.radiusPad`.
- **Ne jamais dessiner une bordure "à la main"** (`Colors.white.withValues(alpha: x)`,
  `scheme.outlineVariant` avec un alpha inventé) — passer par
  `AppElevation.border(scheme)` (hairline standard) ou
  `AppElevation.borderStrong(scheme)` (pointillés, séparateurs marqués,
  survol). `scheme.outlineVariant`/`scheme.outline` bruts (sans alpha) sont
  volontairement un gris neutre clair plutôt que blanc pur — ne pas les
  repasser en blanc sans relire [0023](../../docs/decisions/0023-direction-visuelle-console-linear.md).
- **Ne jamais utiliser `Icons.remove_circle`/une couleur `scheme.error` pour
  une simple action de suppression dans une liste** (retirer un son d'un
  pad, retirer un tag…). Réserver le rouge/`scheme.error` aux états
  réellement critiques (fichier manquant, stop-all). Une suppression banale
  est un `Icons.close` discret en `scheme.onSurfaceVariant`.
- **Ne jamais afficher un volume/curseur sur sa propre rangée pleine
  largeur** dans une ligne de liste compacte (son d'un pad, item de
  bibliothèque) — le contrôle doit rester inline, à droite du titre/tags,
  contraint en largeur (`SizedBox(width: ~56)` autour du `Slider` thémé,
  qui est déjà fin/discret globalement).

## Composants Material qui nécessitent une attention particulière

- **`SegmentedButton`** est thémé globalement (`segmentedButtonTheme`) mais
  sa coche de sélection (`showSelectedIcon`) est un paramètre du *widget*,
  pas du thème — toujours passer `showSelectedIcon: false` explicitement à
  chaque nouvel usage.
- **Boutons (`ElevatedButton`/`OutlinedButton`/`FilledButton`) côte à côte
  dans un `Row`** (barre d'actions Annuler/Enregistrer, etc.) : le thème
  global leur donne `minimumSize: Size.fromHeight(42)`, qui fixe la largeur
  minimale à `double.infinity` (pensé pour un bouton seul en pleine
  largeur). Dans un `Row` de plusieurs boutons, ça les rend **invisibles
  sans erreur visible en release**. Toujours surcharger localement
  `style: ElevatedButton.styleFrom(minimumSize: const Size(64, 42))` (ou
  équivalent) pour chaque bouton d'une rangée à plusieurs boutons.
- **Icônes flottantes sur un pad ou une barre d'outils** (edit/fermer/sons
  d'un pad, recherche de la barre du haut) : un `IconButton` nu lit comme du
  Material par défaut. Donner un petit cadre (fond neutre semi-transparent +
  bordure fine, ~28-32px). Pour une action de barre d'outils statique
  (recherche, actualiser, menu…), réutiliser le widget partagé
  `BoxedIconButton` (`widgets/boxed_icon_button.dart`) — ne pas le
  redupliquer localement dans un écran. Pour une icône flottante sur un pad
  (contraste dynamique selon la couleur du pad, donc pas partageable telle
  quelle), voir le `style: IconButton.styleFrom(...)` de `pad_item.dart`
  comme exemple à réutiliser plutôt que ré-inventer. `PopupMenuButton` n'a
  pas de paramètre `icon` qui accepte ce cadre — passer par `child:` avec le
  même décor (voir `_SamplerDesktopMenuButton` dans `sampler_screen.dart`).
- **Sélecteur d'identité colorée** (scène/board, catégorie…) : pas de texte
  brut + chevron. Le pattern est une pastille bordée (fond `surfaceContainer`,
  bordure `AppElevation.border`, radius `AppRadius.md`) contenant un point
  de couleur (la couleur de l'entité, ou `onSurfaceVariant` à 50% si aucune
  couleur définie) + le nom — voir `_BoardTitleLabel`.

## Typographie

- **Manrope** est la police par défaut de tout le thème (`fontFamily:
  AppFonts.ui`) — ne jamais la surcharger sans raison.
- **JetBrains Mono** (`AppFonts.monoStyle(baseStyle)`) est réservé aux
  affichages **techniques isolés** : durée/minuteur, compteur, décalage,
  chemin de fichier. Ne jamais l'appliquer à une phrase française qui
  contient juste un nombre ou une heure ("aujourd'hui à 14:32") — seul le
  nombre isolé bénéficie du mono, une phrase complète non.
- **Échelle desktop** : `AppTypography.desktopFontScale` (actuellement
  0.88) est appliqué une seule fois, dans `MaterialApp.builder`
  (`core/app/app.dart`), via `context.prefersDesktopUi` — jamais par écran.
  Un écran qui a l'impression que son texte est trop gros sur PC doit
  ajuster sa taille de base (ou ce facteur central), jamais ajouter sa
  propre logique de plateforme.
- Les champs de saisie sont **denses** (`isDense: true`, padding resserré,
  radius `AppRadius.md`) globalement — ne pas ajouter de `border:`/`contentPadding`
  local sur un `TextField` sauf besoin réel : ça écrase silencieusement le
  thème (et a déjà produit un champ sans distinction focus/repos, cf.
  incident corrigé dans `pad_details_screen.dart`).

## Polices et assets

- Manrope et JetBrains Mono sont bundlées en local (`assets/fonts/`,
  licence OFL) et déclarées dans `pubspec.yaml` — jamais via le package
  `google_fonts` (qui va chercher les polices en réseau au premier lancement) :
  l'app doit rester utilisable backstage hors ligne.

## Avant de considérer un nouvel écran "conforme"

Lancer l'app réellement (pas seulement `dart analyze`) et comparer à l'œil :
fond quasi noir, pas d'ombre/elevation visible, pas de ripple au clic, pas de
carte imbriquée dans un dialogue/formulaire, texte dense sur desktop. Un
screenshot de l'écran réel vaut mieux qu'une relecture du code — plusieurs
régressions de cette direction (case à cocher fantôme, boutons invisibles,
carte encore visible) n'étaient détectables qu'à l'écran.
