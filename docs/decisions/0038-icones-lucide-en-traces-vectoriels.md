# 0038 — Icônes Lucide dessinées en tracés vectoriels, plus en police

**Statut :** acceptée
**Date :** 2026-11-12

## Contexte

Les icônes de [0034](0034-icones-lucide-via-appicons.md) étaient des glyphes d'une police (`lucide_icons_flutter`). Sous Windows à 100 % (1920×1080, `devicePixelRatio` 1,0), elles sortaient crénelées : trait en escalier d'un pixel, presque sans niveaux de gris intermédiaires, alors que le texte, les coins de pad et l'avatar étaient bien lissés. Le défaut se reproduit dans un projet Flutter vide avec ces mêmes glyphes (16 à 20 px, graisses 300 et 400), et sous Skia — le moteur par défaut de `flutter run` sur desktop ; Impeller (`--enable-impeller`) n'affiche qu'une fenêtre noire sur ce poste. Skia rasterise lui-même les glyphes sur Windows, au pixel près, pour des polices pensées pour des traits plus épais ; un trait Lucide de ~1 px à 16 px n'y tient pas. Les glyphes Material outlined, essayés au même endroit, sont crénelés aussi, un peu plus épais.

Un `Path` dessiné avec un `Paint` passe, lui, par le rasteriseur de formes, qui calcule la couverture réelle de chaque pixel : le même tracé en SVG sortait lisse dans le banc d'essai.

## Décision

Les icônes de `AppIcons` sont des **tracés SVG Lucide** dessinés par `StrokeIcon` (`lib/core/theme/stroke_icon.dart`, un `CustomPainter`, grille de 24, extrémités et jointures arrondies), plus des glyphes de police. Les tracés sont générés dans `lib/core/theme/lucide_paths.dart` par `tool/gen_lucide_paths.mjs` (SVG de `lucide-static`, version épinglée dans le script) à partir des `LucidePaths.xxx` cités par `app_icons.dart`. L'épaisseur est portée par `StrokeIconData.strokeWidth`, **1,75** par défaut (~1,2 px à 16 px, ~1,5 px à 20 px) : à 1,5 le trait tombait à ~1 px et se lisait grisé ; à 2, les icônes détaillées (théâtre, bibliothèque) se bouchaient à 16 px. Le menu principal utilise `AppIconSize.md` (20 px) pour la même raison : ces icônes ont trop de détail pour 16 px. La dépendance `lucide_icons_flutter` est retirée ; `path_drawing` est ajoutée pour lire les tracés.

## Alternatives écartées

- **Garder les glyphes et grossir le trait** — masque l'escalier sans le supprimer ; s'éloigne du trait fin voulu par 0023.
- **Icônes Material** — crénelées aussi, et contraires à 0034.
- **`flutter_svg`** — un widget et un parseur de plus pour des icônes monochromes ; le `Path` natif suffit.
- **Impeller** — inutilisable sur ce poste (fenêtre noire) ; ne règle pas le choix de rasterisation d'un trait fin de toute façon.

## Conséquences

- `AppIcons.xxx` est un `StrokeIconData`, pas un `IconData` : on le pose avec `StrokeIcon(AppIcons.xxx)` (jamais `Icon(...)`), et les paramètres de widgets qui reçoivent une icône sont typés `StrokeIconData`. `StrokeIcon` prend taille, couleur et opacité de l'`IconTheme` comme `Icon`, donc `IconButton`, `ListTile`, etc. fonctionnent inchangés.
- Une nouvelle icône : ajouter le concept dans `AppIcons` avec `LucidePaths.nomLucideEnCamelCase`, relancer `node tool/gen_lucide_paths.mjs` (réseau requis pour télécharger les SVG), commiter le fichier généré.
- Les tests cherchent une icône avec `findStrokeIcon(AppIcons.x)` (`test/support/find_stroke_icon.dart`) à la place de `find.byIcon`.
- Un `Path` est lissé quelle que soit sa taille, mais une icône posée à un demi-pixel (centrage d'une taille impaire dans un conteneur pair) reste floue : aligner sur la grille de pixels pour les icônes sans fond (voir `_buildIconCluster` de `pad_button.dart`).
- Le reste de 0034 tient : Lucide, `AppIcons` nommé par concept, pas de variante pleine, glyphes de transport à part (`TransportIcon`).
