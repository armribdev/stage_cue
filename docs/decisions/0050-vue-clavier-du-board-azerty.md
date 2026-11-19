# 0050 — Vue clavier d'un board : une vue parmi d'autres, disposition AZERTY

**Statut :** acceptée
**Date :** 2026-11-19

## Contexte

Un board ne s'affichait que sous forme de grille de pads en rangées. Les pads
peuvent déjà être déclenchés par une touche (`AppPreferences.hotkeyForPad`),
mais rien ne montrait quelle touche déclenche quoi. On veut plusieurs vues d'un
**même** board, la première nouvelle étant un clavier où chaque pad est posé sur
sa touche.

## Décision

Une vue ne change que la présentation (`BoardView` : `grid`, `keyboard`), jamais
les données : le choix est une préférence locale d'`AppPreferences`, commune à
tous les boards, et la vue clavier est un widget pur (`KeyboardPadsView`) qui
réutilise le chemin de déclenchement de la grille (`_handlePadTap`). Sa
disposition est **AZERTY** (clavier français), sur les touches telles que l'OS
les livre sans modificateur — celles que la capture de raccourci enregistre.

## Alternatives écartées

- **Vue enregistrée par board (colonne en base)** — une migration et une
  synchro Drive pour un goût d'affichage ; même raisonnement que les raccourcis,
  qui restent locaux. À reprendre si une vue devient une donnée du board (ex. une
  disposition des pads propre à la vue).
- **Disposition QWERTY/AZERTY au choix ou détectée** — Flutter n'expose pas la
  disposition de l'OS. Une seule table couvre l'app (interface entièrement en
  français) ; un second clavier = un second jeu de rangées à ajouter à
  `keyboard_layout.dart`, le reste ne bouge pas.
- **Dessiner par position physique (`PhysicalKeyboardKey`)** — les raccourcis
  sont stockés en touche **logique** : un pad sur « A » se déclenche sur le A de
  la disposition de l'OS. Dessiner par position physique décorrélerait l'image
  du comportement.

## Conséquences

- Les raccourcis n'existent que sur poste desktop natif : ailleurs, le bouton de
  bascule est absent et la vue reste la grille, quoi que dise la préférence.
- Un pad dont la touche n'est pas dessinée (flèches, F1…), qui n'en a pas, ou
  qui partage la touche d'un autre pad **n'apparaît pas** dans la vue : elle ne
  montre que ce qui est sur une touche. Il reste dans la grille et dans le menu
  d'une touche vide, qui le propose. En cas de collision, le premier pad dans
  l'ordre du board garde la touche : c'est celui que `_handlePadHotkeyEvent`
  déclenche, les deux doivent parcourir les pads dans le même ordre.
- La vue clavier n'a ni réordonnancement ni slot « + » : réordonner et ajouter
  restent propres à la grille. En revanche on y assigne les touches : glisser
  un pad sur une touche vide l'y place, sur une touche occupée les deux
  **échangent** (`planPadDrop`), le lâcher **ailleurs que sur une touche**
  (n'importe où dans la vue) lui retire sa touche — il disparaît alors de la
  vue —, et un clic sur une touche vide propose les pads sans touche. Un
  échange modifie deux pads : il passe par `AppPreferences.setPadHotkeys`
  (une écriture), jamais par deux `setPadHotkey` qui laisseraient un état
  intermédiaire en collision. L'assignation est verrouillée en Mode Spectacle ;
  la capture dans les détails du pad (appui long ou clic droit sur une touche
  pour les ouvrir) reste possible hors Mode Spectacle.
- Hors Mode Spectacle, un panneau sous le clavier montre **tous** les pads du
  board, rangés comme dans la grille (mêmes rangées, ordre et cartes
  `PadCard`, même taille de cellule) : ceux déjà posés sur une touche y sont
  estompés mais restent glissables. C'est la réserve d'où l'on assigne, et il
  fait partie de la cible « lâcher hors d'une touche » (y reposer un pad lui
  retire sa touche). Il disparaît en Mode Spectacle avec l'assignation.
- Le sélecteur de vue se place à côté du nom de la scène dans la barre du haut :
  la vue est une façon de voir cette scène.
- Une nouvelle vue = une valeur de `BoardView`, un widget, une branche du
  `switch` de `_buildSamplerContent` ; le bouton de la barre, aujourd'hui une
  bascule à deux états, devra alors devenir un menu.
