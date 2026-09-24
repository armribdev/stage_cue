# 0024 — Voie ambiance exclusive, en boucle, dans la régie

**Statut :** acceptée
**Date :** 2026-09-24

## Contexte

Le type `SoundType.ambiance` existait en base et dans les filtres, mais à la
lecture une ambiance se comportait comme un bruitage : polyphonie, pas de
boucle, pas de volume de voie, rien dans la régie. En live, une ambiance est
un tapis sonore comme la musique. Il faut pouvoir en changer sans empiler les
couches, sans qu'elle s'arrête au bout du fichier, et la piloter sans ajouter
de hauteur à la régie.

## Décision

Trois voies à l'antenne : **1 musique max, 1 ambiance max, N bruitages**.
Un pad dont **tous** les sons sont de type ambiance (`Pad.isAmbiancePad`)
passe par `AmbianceController` :
- une seule ambiance joue à la fois, et un nouveau déclenchement remplace
  la précédente par un fondu enchaîné équi-puissance (4 s par défaut) ;
- une ambiance ne démarre ni ne s'arrête jamais sèche : montée de 3 s
  depuis le silence (courbe cubique), sortie de 3 s. Ces durées sont propres à
  la voie et ignorent le sélecteur de fondu de la régie, pensé pour la
  musique (options de 1 s et coupe sèche, trop brutales pour un tapis) ;
- la lecture boucle toujours, avec une reprise au point d'entrée
  (`startOffsetMs`) plutôt qu'au sample 0 (`looping` + `loopingStartAt` de
  SoLoud) ;
- son volume de voie (`ambianceVolume`, avec la même loi cubique que le
  fader musique) est indépendant du volume musique et du volume par son ;
- elle survit au changement de plateau (réserve hors-scène, comme la
  musique) ;
- elle n'est **pas** coupée par le bouton panique
  (`stopAllNonMusicSounds`), mais l'est par « Tout arrêter »
  (`stopAllSounds`).

Côté UI, la voie ambiance est une pastille glissée dans la rangée existante
du bandeau réduit : une icône seule sur écran étroit, avec les réglages dans
un menu. Dans le tiroir ouvert, c'est une section `AMBIANCE` sous la lecture
en cours.

## Alternatives écartées

- **Un second tiroir / bandeau pour l'ambiance** : double la hauteur
  occupée en bas de l'écran au détriment de la grille de pads. Or une
  ambiance n'a besoin que de trois contrôles : nom, volume et arrêt.
- **Garder l'ambiance en polyphonie comme un bruitage** : deux taps
  empilent deux ambiances, et la lecture s'arrête au bout du fichier.
  C'est le comportement qu'on voulait corriger.
- **Boucle réglable par pad** : demande une migration de schéma pour un
  besoin pas encore exprimé. Rien n'empêche de l'ajouter plus tard.
- **Pad mixte (ambiance + autre type) traité comme ambiance** : ambigu.
  On garde la même règle « tous du même type » que `isMusicPad`.

## Conséquences

- Toute branche qui distingue « pad musique » de « pad polyphonique » doit
  aussi traiter l'ambiance. Utiliser `Pad.isExclusiveVoicePad` pour la
  question « voie mono-voix ? », et `isMusicPad` / `isAmbiancePad` seulement
  pour savoir vers quel contrôleur router.
- `_attachPlayerListeners` : pour un pad ambiance, l'antenne
  (`currentAmbiancePad`) est posée explicitement par le contrôleur, et le
  listener ne la retire que sur une fin inattendue, hors verrou de transition.
  Ne pas y recopier la logique d'avance automatique de la musique.
- Les pads hors-scène (id = `-soundId`) sont créés par
  `SamplerNotifier._buildOffStagePad`, commun aux deux voies. Un son a un seul
  type, donc les réserves musique et ambiance ne peuvent pas entrer en
  collision.
- La recherche-éclair (Ctrl+F) continue de jouer une ambiance en
  **pré-écoute** éphémère : seuls un pad ambiance et le sélecteur de la régie
  mettent une ambiance à l'antenne.
