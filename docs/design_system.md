# Design system — Stage Cue

Référence des tokens et composants partagés pour une UI cohérente, dense et
"outil pro" (desktop-first, mais pleinement utilisable sur mobile/tablette).

## Tokens

Direction visuelle "Console Linear" ([0023](decisions/0023-direction-visuelle-console-linear.md)) ;
le détail actionnable (à faire / à ne pas faire) vit dans `.claude/rules/ui.md`.
Toujours piocher dans `lib/core/theme/app_tokens.dart` plutôt que d'écrire des
valeurs magiques (`BorderRadius.circular(14)`, `EdgeInsets.all(18)`, `Color(0x…)`…).

### Rayons — `AppRadius`

Échelle sobre à 4 paliers :

| Token | Valeur | Usage |
|---|---|---|
| `AppRadius.xs` | 2 | chips, badges, barres de progression |
| `AppRadius.sm` | 4 | boutons texte, tuiles de liste, segments, tooltips |
| `AppRadius.md` | 6 | champs de saisie, boutons pleins, menus, toasts |
| `AppRadius.lg` | 8 | dialogues, modales, panneaux, cartes |
| `AppRadius.pad` | 8 (= `lg`) | pads du sampler (`radiusPad`) |

Variantes prêtes à l'emploi pour `BorderRadius` : `radiusXs/Sm/Md/Lg/Pad`.

Pas de "pill shapes" : un bouton ou un champ reste rectangulaire à coins
légèrement adoucis, jamais en capsule. Les seules formes rondes sont des
pastilles de couleur / points d'état (`BoxShape.circle`) ; les `Chip` du
thème suivent `AppRadius.md`.

### Couleurs — `AppColors`

Valeurs exactes (pas dérivées d'un seed), thème sombre unique :

| Token | Valeur | Usage |
|---|---|---|
| `bg` | `#0B0B0E` | fond d'écran |
| `surface` | `#14151B` | panneaux, barre basse, drawer |
| `surface2` | `#1B1C24` | cartes, dialogues, champs, menus, toasts |
| `border` / `borderStrong` | blanc 9 % / 18 % | hairlines / séparateurs marqués |
| `text` / `textDim` / `textFaint` | `#EDEDF1` / `#8B8D98` / `#54565F` | texte principal / secondaire / désactivé |
| `accent` | `#6E56CF` | **seul** accent (violet) ; `accentSoft` = 16 %, `accentLine` = 50 % |
| `success` / `danger` / `warn` | `#4CC38A` / `#E5484D` / `#E8A23B` | états uniquement |

`ColorScheme` (voir `AppTheme`) est construit à partir de ces valeurs :
`outline` / `outlineVariant` sont un gris neutre clair opaque (`#A8AAB5`) sur
lequel `AppElevation` applique l'alpha du hairline.

### Typographie — `AppFonts`, `AppTextStyles`, `AppTypography`

- **Manrope** (`AppFonts.ui`) : police par défaut de tout le thème.
- **JetBrains Mono** (`AppFonts.monoStyle(base)`) : affichages techniques
  isolés (durées, compteurs, chemins) — jamais une phrase entière.
- `AppTextStyles.sectionLabel(context)` : libellé de section en petites
  capitales (texte passé en majuscules par l'appelant).
- `AppTypography.titleLetterSpacing` (−0,2 px) : approche des titres de 15 à 18 px
  (modales, dialogues, barres) ; pas du corps de texte ni des libellés de section.
- `AppTypography.desktopFontScale` (0,88) : appliqué une seule fois dans
  `MaterialApp.builder` quand `context.prefersDesktopUi`.

Polices bundlées en local (`assets/fonts/`, OFL), jamais via `google_fonts`.

### Icônes — `AppIcons`

Jeu Lucide à trait fin (graisse 300), police bundlée en local, nommé par
concept dans `lib/core/theme/app_icons.dart` ([0034](decisions/0034-icones-lucide-via-appicons.md)).
Jamais `Icons.*` : ajouter un concept à `AppIcons`. Pas de variante pleine — un
état actif se marque par la couleur ou un autre glyphe.

### Espacements — `AppSpacing`

| Token | Valeur |
|---|---|
| `AppSpacing.xs` | 4 |
| `AppSpacing.sm` | 8 |
| `AppSpacing.md` | 12 |
| `AppSpacing.lg` | 16 |
| `AppSpacing.xl` | 24 |

### Menus — `AppMenu`

`itemHeight` (32) et `itemPadding` pour les `PopupMenuItem` — à passer
explicitement sur chaque item, ainsi que
`popUpAnimationStyle: AnimationStyle.noAnimation` sur chaque menu.

### Élévation / contours — `AppElevation`

Aucune élévation Material (`elevation: 0` partout, pas de ripple) : les
surfaces se distinguent par des **bordures fines** et non par des ombres.

| Helper | Usage |
|---|---|
| `AppElevation.border(scheme)` | hairline standard (blanc 9 %) : cartes, panneaux, champs au repos |
| `AppElevation.borderStrong(scheme)` | pointillés, séparateurs marqués, survol (18 %) |
| `AppElevation.emphasizedBorder(scheme)` | focus, sélection (accent, 1,4 px) |

```dart
DecoratedBox(
  decoration: BoxDecoration(
    color: scheme.surfaceContainer,
    borderRadius: AppRadius.radiusMd,
    border: Border.fromBorderSide(AppElevation.border(scheme)),
  ),
)
```

**`AppPanelBorder`** (`app_tokens.dart`) : contour des panneaux surélevés
(dialogue, menu, carte d'item, sélecteur de sons) = hairline + liseré lumineux
d'1 px sur l'arête haute (`AppElevation.topHighlightOpacity`), qui s'estompe vers
les coins. Il est posé dans `dialogTheme` / `cardTheme` / `popupMenuTheme` :
**ne pas redéfinir `shape:` sur un `Dialog`/`AlertDialog`** — une forme locale
sans `side` supprime la bordure du thème. Pour un panneau hors thème : `AppPanelBorder.standard(scheme, radius)`.

Les champs de saisie sont en **retrait** (`fillColor: AppColors.bg`) : posés sur
un dialogue en `surface2`, ils se creusent au lieu de se confondre avec lui.

Un `Card` ne sert qu'à un **item répété** d'une liste (ligne de son, pad,
bibliothèque), jamais à encadrer une section d'écran ou de formulaire.

## Thème

`visualDensity: VisualDensity.compact`, `NoSplash`, `useMaterial3: true`.
Tous les composants thémés (`cardTheme`, `dialogTheme`, `inputDecorationTheme`,
boutons, menus, drawer…) utilisent les tokens ci-dessus — ne pas redéfinir de
rayons ou de couleurs localement dans un widget si le thème peut s'en charger.

## Composants partagés

### Dialogues — `lib/features/sampler/presentation/widgets/app_form_dialog.dart`

- **`AppFormDialog`** : dialogue générique avec titre + bouton fermer + contenu
  + actions, pour les formulaires plus riches qu'un simple champ texte.
- **`AppTextInputDialog`** : saisie d'un nom court (créer/renommer/dupliquer…).
  Gère focus auto, validation sur Entrée, dispose des controllers.
  ```dart
  final name = await AppTextInputDialog.show(
    context,
    title: 'Renommer la scène',
    confirmLabel: 'Renommer',
    initialValue: board.name,
    icon: AppIcons.text,
  );
  ```
- **`AppConfirmDialog`** : confirmation d'action (suppression, action
  irréversible…), avec option `isDestructive` pour teinter le bouton de
  confirmation en `colorScheme.error`.
  ```dart
  final confirmed = await AppConfirmDialog.show(
    context,
    title: 'Supprimer la scène',
    message: 'Supprimer "${board.name}" ? Cette action est irréversible.',
    confirmLabel: 'Supprimer',
    isDestructive: true,
  );
  ```

Ne jamais reconstruire un `showDialog`/`AlertDialog` ad-hoc pour ces deux
patterns (saisie de nom court / confirmation) — utiliser ces widgets pour
garantir un rendu et un comportement uniformes.

Tout dialogue s'ouvre via **`showAppDialog`** (`lib/core/theme/app_dialog.dart`),
jamais `showDialog` direct : il porte la transition d'entrée commune (fondu +
remontée de 8 px, sans `scale`, `appDialogTransition`), partagée avec le
sélecteur de sons.

### Modales adaptatives — `lib/features/sampler/presentation/widgets/app_modal.dart`

- **`openAdaptiveScreen`** : ouvre un écran en modale centrée (tablette/desktop)
  ou en page plein écran (téléphone), selon `preferModalPresentation`.
- **`AppModalShell`** : en-tête (titre + actions + bouton fermer) + corps, pour
  les modales pleines (paramètres, bibliothèque…).
- **`AppNavigationCard`** / **`AppChoiceOption`** : cartes cliquables
  icône + libellé pour la navigation interne ou les choix exclusifs.

### Notifications (toasts) — `lib/core/utils/app_snackbar.dart`, `app_toast_host.dart`

- **`AppSnackBar.show(context, message, {action, copyable, severity, duration})`**
  et **`showCopyableSnackBar`** (messages d'erreur, gravité `error`) sont le
  **seul** moyen de notifier l'utilisateur. Ne jamais appeler
  `ScaffoldMessenger.showSnackBar` : l'app n'a plus de `SnackBar` natif
  ([0033](decisions/0033-toast-global-au-dessus-du-navigator.md)).
- Rendu par **`AppToastHost`**, posé dans `MaterialApp.builder` au-dessus du
  `Navigator` : visible au-dessus de toutes les routes, modales comprises, sans
  `ScaffoldMessenger` local. Un seul toast à la fois (le nouveau remplace
  l'ancien), fermeture garantie après `duration` par un `Timer` Dart, survol =
  pause du compte à rebours.
- Gravité (`AppToastSeverity`: `info` par défaut, `success`, `error`) : passée
  explicitement par l'appelant, elle ne pilote que l'icône d'état.
- Action : `AppToastAction(label:, onPressed:)` (remplace `SnackBarAction`) ;
  elle ferme le toast avant d'exécuter son callback.
- Look : fond `surface2`, hairline `AppElevation.border`, rayon `AppRadius.md`,
  sans ombre ni ripple ; bas à droite sur desktop, bas centré sur mobile,
  largeur max 420.

## Quand introduire un nouveau pattern

Si vous ajoutez un composant réutilisable ou changez une convention (rayon,
espacement, structure de dialogue…), mettez à jour ce document **et**
`docs/responsive_guidelines.md` si l'impact est responsive — la documentation
doit rester la source de vérité pour les futures contributions.
