# 0014 — Mode live : priorité au son le moins joué de la session pour les multipads

**Statut :** acceptée
**Date :** 2026-07-22

## Contexte

En Mode Spectacle, un régisseur veut que les multipads évitent de sur-jouer
un même son pendant la représentation — l'algorithme habituel de chaque pad
(aléatoire sans répétition jusqu'à cycle épuisé, ou séquentiel round-robin)
est local au pad et ignore ce qui s'est joué ailleurs sur le plateau. Il faut
un signal global, valable pour toute la durée du live, qui prime sur ces deux
modes.

## Décision

Pendant qu'une session live est active (`SamplerNotifier.isLiveSessionActive`),
`_pickSoundIndex` ignore `playMode` et choisit parmi les sons du multipad au
compte de lecture de session le plus bas (égalité → tirage aléatoire parmi
les ex-æquo). Le compteur par son n'est incrémenté que par `_markPlayedAt`
(lecture réelle), jamais par `_markPlayed` seul (pré-écoute), et n'est remis
à zéro qu'à l'entrée d'une nouvelle session live — sortir du Mode Spectacle
gèle les compteurs sans les effacer.

## Alternatives écartées

- **Pondérer l'algorithme existant plutôt que le court-circuiter** — aurait
  mélangé deux notions de cycle (par-pad vs. global-session) sans bénéfice
  clair face à un remplacement total pendant le live.
- **Remettre à zéro les compteurs à la sortie du Mode Spectacle** — le
  régisseur veut pouvoir consulter après-coup ce qui a été joué (badges
  recherche) ; seule une nouvelle entrée en live repart propre.
- **Compter aussi les pré-écoutes** — une audition n'est pas une lecture
  réelle pendant le show ; la compter fausserait l'équilibrage voulu.

## Conséquences

- `_pickSoundIndex` a une branche globale qui prime sur `PadPlayMode` —
  un futur mode de lecture par pad doit composer avec cette branche (elle
  s'applique avant le switch), sous peine d'être silencieusement contournée.
- Le hook d'incrément vit uniquement dans `_markPlayedAt` — tout nouveau
  site de lecture réelle doit y passer (pas directement par `_markPlayed`) ;
  tout nouveau site de pré-écoute doit au contraire n'appeler que
  `_markPlayed`.
- `_playedSoundIndices`/`_nextSoundIndex` ne sont pas mutés pendant une
  session live, pour que l'algorithme habituel reprenne dans un état
  cohérent à la sortie du live — ne pas casser cette invariance.
