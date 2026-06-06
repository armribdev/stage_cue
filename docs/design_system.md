# Design system — Stage Cue

Référence des tokens et composants partagés pour une UI cohérente, dense et
"outil pro" (desktop-first, mais pleinement utilisable sur mobile/tablette).

## Tokens

Toujours piocher dans `lib/core/theme/app_tokens.dart` plutôt que d'écrire des
valeurs magiques (`BorderRadius.circular(14)`, `EdgeInsets.all(18)`…).

### Rayons — `AppRadius`

Échelle sobre à 4 paliers (remplace les 4/6/8/12/14/16/18/20 historiques) :

| Token | Valeur | Usage |
|---|---|---|
| `AppRadius.xs` | 4 | chips, badges, barres de progression |
| `AppRadius.sm` | 8 | champs de saisie, boutons, petites cartes |
| `AppRadius.md` | 10 | cartes standard, pads, tuiles de liste |
| `AppRadius.lg` | 12 | dialogues, modales, panneaux majeurs |

Variantes prêtes à l'emploi pour `BorderRadius` : `radiusXs/Sm/Md/Lg`.

Pas de "pill shapes" : aucun composant ne doit dépasser `AppRadius.lg` — un
bouton ou un champ reste rectangulaire à coins légèrement adoucis, jamais en
capsule.

### Espacements — `AppSpacing`

| Token | Valeur |
|---|---|
| `AppSpacing.xs` | 4 |
| `AppSpacing.sm` | 8 |
| `AppSpacing.md` | 12 |
| `AppSpacing.lg` | 16 |
| `AppSpacing.xl` | 24 |
| `AppSpacing.xxl` | 32 |

### Élévation / contours — `AppElevation`

L'app privilégie des **bordures fines** (`outlineVariant`) à des ombres
Material marquées — rendu plus plat, plus net, plus dense :

```dart
Card(
  shape: RoundedRectangleBorder(
    borderRadius: AppRadius.radiusMd,
    side: AppElevation.border(Theme.of(context).colorScheme),
  ),
)
```

`AppElevation.emphasizedBorder(scheme)` pour les états focus/sélection/survol.

## Palette

Thème sombre unique, défini dans `AppTheme.darkTheme` :
- **Accent** : indigo désaturé `#5B6EF5` (remplace le violet saturé `#7C4DFF`
  d'origine, jugé trop "app créative mobile").
- **Surfaces** : ardoise neutre (`#15171D` / `#1C1F27`) plutôt que bleu nuit
  saturé — rendu plus proche d'un outil SaaS (Linear, Vercel…) que d'une app
  Android.
- `visualDensity: VisualDensity.compact` pour une interface dense, pensée
  clavier/souris, sans pour autant gêner le tactile.

Tous les composants thémés (`cardTheme`, `dialogTheme`, `inputDecorationTheme`,
boutons, snackbars, drawer…) utilisent les tokens `AppRadius`/`AppElevation`
ci-dessus — ne pas redéfinir de rayons localement dans un widget si le thème
peut s'en charger.

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
    icon: Icons.text_fields_rounded,
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

### Modales adaptatives — `lib/features/sampler/presentation/widgets/app_modal.dart`

- **`openAdaptiveScreen`** : ouvre un écran en modale centrée (tablette/desktop)
  ou en page plein écran (téléphone), selon `preferModalPresentation`.
- **`AppModalShell`** : en-tête (titre + actions + bouton fermer) + corps, pour
  les modales pleines (paramètres, bibliothèque…).
- **`AppNavigationCard`** / **`AppChoiceOption`** : cartes cliquables
  icône + libellé pour la navigation interne ou les choix exclusifs.

## Quand introduire un nouveau pattern

Si vous ajoutez un composant réutilisable ou changez une convention (rayon,
espacement, structure de dialogue…), mettez à jour ce document **et**
`docs/responsive_guidelines.md` si l'impact est responsive — la documentation
doit rester la source de vérité pour les futures contributions.
