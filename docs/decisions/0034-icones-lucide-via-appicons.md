# 0034 — Icônes Lucide à trait fin, centralisées dans `AppIcons`

**Statut :** acceptée
**Date :** 2026-11-07

## Contexte

Les ~200 usages de `Icons.*` (Material, variantes `_rounded` / `_outlined` mélangées) étaient le dernier gros signal Material de l'interface après le toast ([0033](0033-toast-global-au-dessus-du-navigator.md)) et les dialogues ([0023](0023-direction-visuelle-console-linear.md)). Les remplacer site par site laissait le choix du jeu éparpillé dans une quarantaine de fichiers.

## Décision

Le jeu **Lucide** (`lucide_icons_flutter`, MIT, police bundlée en local donc utilisable hors ligne) en **graisse 300** (≈ 1,5 px de trait sur la grille de 24). Tout passe par `lib/core/theme/app_icons.dart` (`AppIcons`), nommé par **concept** (`delete`, `cloudOff`, `volumeOn`…) : le jeu et la graisse ne se changent qu'à cet endroit.

## Alternatives écartées

- **Phosphor** (`phosphor_flutter`) — couverture complète, variantes pleines pratiques, mais dernière publication en mai 2024.
- **Material Symbols** (`material_symbols_icons`) — polices de 10 à 15 Mo chacune, et la silhouette reste celle de Material.
- **Hugeicons** — ~11 Mo de code Dart généré et pas de police ; coût de compilation sans bénéfice.
- **Importer `LucideIcons` directement dans chaque écran** — disperse le choix du jeu et de la graisse ; c'est ce que `AppIcons` évite.

## Conséquences

- Plus aucun `Icons.*` dans `lib/` ni `test/` : une nouvelle icône est un nouveau concept dans `AppIcons`. Les tests cherchent `AppIcons.x` (`find.byIcon`).
- Lucide n'a **pas de variante pleine** : un état actif (favori, case cochée) se distingue par la couleur ou un autre glyphe (`checkboxOn` / `checkboxOff`), jamais par le remplissage. Les étoiles de favori ne changent donc plus de forme, seulement de couleur.
- Plusieurs concepts Material voisins sont fusionnés (`_rounded` / `_outlined`, `cloud` / `cloud_queue`, les trois `check_circle*`) ; `folder_shared` devient `folderSymlink`, `download_done` devient `circleCheckBig` : à revoir à l'écran si le sens n'est pas évident.
- Restent en Material les icônes **implicites** de widgets qu'on n'a pas redessinés : bouton retour des `AppBar` (écrans plein écran mobile). La flèche du `DropdownButtonFormField` est passée explicitement.
- Le package déclare toutes ses graisses (100 à 600) dans son `pubspec.yaml` : le poids réel en release est à mesurer, la graisse inutilisée peut rester embarquée.
