# 0023 — Direction visuelle "Console Linear", en rupture avec Material 3 par défaut

**Statut :** acceptée
**Date :** 2026-09-09

## Contexte

L'app avait un look Material 3 par défaut (AppBar standard, `Card` à elevation,
ripple sur chaque tap, `SegmentedButton` en pilule pleine, échelle
typographique M3 pensée tactile) jugé générique et daté face aux références
visées (Linear, Notion, Vercel). Une passe complète a migré toute la couche
présentation vers une direction nommée "Console Linear" : surfaces quasi
noires, un seul accent violet, hiérarchie portée par bordures fines et poids
typographique plutôt que par elevation/couleur saturée.

Deux allers-retours avec l'utilisateur après la première passe ont révélé que
"recolorer" les widgets Material par défaut ne suffit pas — la structure même
(sections encartées dans des `Card`, tailles de police M3, boutons Material
non reskinnés) continue de lire comme du Material tant qu'elle n'est pas
corrigée. Les règles ci-dessous consignent ce qui s'est révélé nécessaire,
au-delà de la simple palette de couleurs, pour que l'impression change
réellement.

## Décision

Toute nouvelle UI suit la direction "Console Linear" telle que définie par
`AppColors` / `AppFonts` / `AppRadius` / `AppElevation` / `AppSpacing` /
`AppTextStyles` / `AppTypography` (`lib/core/theme/app_tokens.dart`) et la `ThemeData` de
`lib/core/theme/app_theme.dart`. Le détail actionnable (ce qu'il faut faire /
ne pas faire pour chaque nouveau widget ou écran) vit dans
`.claude/rules/ui.md` plutôt que dans cette entrée, pour rester consulté à
chaque tâche plutôt que lu une fois.

## Alternatives écartées

- **Ne changer que la palette de couleurs (`ColorScheme.fromSeed` avec un
  nouveau seed)** — testé en premier ; insuffisant. Une fois les bonnes
  couleurs en place, l'app "lisait" encore Material 3 par les patterns
  structurels : `Card` encapsulant chaque section d'un formulaire/dialogue,
  `SegmentedButton` en pilule avec coche, échelle de police M3 (titleLarge à
  22px). Retenu comme leçon plutôt qu'écarté d'emblée : voir `.claude/rules/ui.md`.
- **`MediaQuery.textScaler` réglé en dur sur desktop, sans composer avec la
  préférence système** — écarté : aurait écrasé le réglage d'accessibilité
  de l'utilisateur au lieu de le multiplier. La réduction desktop
  (`AppTypography.desktopFontScale`) s'applique via `theme.textTheme.apply(
  fontSizeFactor: ...)`, qui ne touche que les styles dérivés du thème — pas
  le texte à taille codée en dur, et pas la préférence d'accessibilité de
  l'OS.
- **Remplacer les widgets Material par des implémentations 100% custom**
  (boutons, champs, dialogues) — écarté par défaut : `ThemeData` couvre la
  quasi-totalité des cas (voir l'audit initial, très peu de couleurs/rayons
  codés en dur restaient une fois le thème réécrit). Deux catégories
  d'exception, distinctes l'une de l'autre : un **thème dédié** quand un
  paramètre du widget résiste à `ThemeData` (`SegmentedButton` et son
  `showSelectedIcon`, qui reste un paramètre par instance) ; un **petit
  widget composé** quand la *forme* elle-même n'existe pas côté Material
  (l'icône de barre encadrée `BoxedIconButton`, le sélecteur d'identité
  colorée `_BoardTitleLabel` — voir `.claude/rules/ui.md`). Dans les deux
  cas, la correction reste locale et petite ; aucun bouton/champ/dialogue
  Material n'a été réécrit de zéro.

## Conséquences

- Toute section d'un formulaire, dialogue ou écran de paramètres qui
  regrouperait plusieurs champs **ne doit pas** être enveloppée dans un
  `Card` — c'est le signal Material le plus reconnaissable. Voir
  `.claude/rules/ui.md` pour le pattern de remplacement (label capitales +
  `Divider`).
- `outlineVariant`/`outline` du `ColorScheme` ont été recalibrés vers un gris
  neutre clair plutôt que blanc pur, spécifiquement pour ne pas casser les
  ~25 endroits du code qui appliquent leur propre alpha sur `outlineVariant`
  sans passer par `AppElevation.border()`. Un futur changement de ces deux
  couleurs doit re-vérifier ces sites (`grep -rn "outlineVariant" lib/`).
- `minimumSize: Size.fromHeight(...)` dans les thèmes de bouton globaux
  donne une largeur minimale **infinie** — correct pour un bouton seul en
  pleine largeur, mais rend invisible (sans erreur visible en release) tout
  bouton placé à côté d'un autre dans un `Row` brut. Toujours surcharger
  `minimumSize` localement pour une rangée de plusieurs boutons.
- La réduction typographique desktop (`AppTypography.desktopFontScale`) est
  appliquée une seule fois, dans `MaterialApp.builder` (`core/app/app.dart`),
  jamais par écran — un écran qui coderait sa propre réduction dupliquerait
  le réglage et le désynchroniserait du reste de l'app à la prochaine
  retouche.
