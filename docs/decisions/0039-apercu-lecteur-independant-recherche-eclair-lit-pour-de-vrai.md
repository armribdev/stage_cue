# 0039 — Aperçu : lecteur indépendant du STOP ; la recherche-éclair joue pour de vrai

**Statut :** acceptée
**Date :** 2026-11-12

## Contexte

Le clic (ou Entrée) sur un son de la recherche-éclair lançait une pré-écoute, pas le son. Les bruitages et ambiances partaient dans un jeu de lecteurs d'aperçu « éphémères » (plusieurs en parallèle), distinct du lecteur d'aperçu unique du bouton de ligne, et ces lecteurs étaient comptés avec les bruitages : ils faisaient apparaître le bouton « Tout arrêter » et étaient coupés par lui (et par Échap). L'aperçu se comportait donc comme un son normal alors que c'est une écoute à part.

## Décision

Il n'existe qu'**un seul** lecteur d'aperçu (`toggleLibraryPreview`, play/pause), totalement étranger au bouton « Tout arrêter » : il ne compte ni dans `hasNonMusicSoundsPlaying` ni dans `stopAllNonMusicSounds`, et ne se pilote que par ses propres boutons (ligne du sélecteur, bouton casque d'un pad) ou par la fermeture du sélecteur. Le clic / Entrée de la recherche-éclair appelle `playSoundFromQuickSearch`, qui joue le son par la voie de son type : musique sur la régie, ambiance à l'antenne, bruitage en salle via un pad hors-scène.

## Alternatives écartées

- **Garder les lecteurs éphémères mais les exclure du STOP** — deux chemins d'aperçu à maintenir, et « plusieurs aperçus en même temps » n'a pas de sens pour une écoute de contrôle.
- **Clic = préparer sur le plateau** — modifie le plateau à chaque essai, et ne joue rien.
- **Créer un vrai pad au plateau pour chaque bruitage joué** — même défaut : un clic de recherche ne doit pas laisser de trace sur la scène (le bouton de droite reste là pour ça).

## Conséquences

- Toute nouvelle pré-écoute passe par `toggleLibraryPreview` (cf. [0027](0027-preecoute-casque-stricte.md) pour le routage casque) ; ne pas réintroduire de lecteur d'aperçu parallèle ni de lien entre l'aperçu et `hasNonMusicSoundsPlaying` / `panicStop`.
- Les bruitages lancés depuis la recherche-éclair vivent dans `_offStageSfxPads` : ce sont de vraies lectures (coupées par « Tout arrêter », comptées par la session live, `_markPlayedAt`). Un pad hors-scène inactif est libéré à la lecture suivante, au STOP, au changement de plateau et à `dispose`.
- Une ambiance lancée depuis la recherche-éclair est désormais mise à l'antenne (elle ne l'était pas avant : voir l'amendement de [0024](0024-voie-ambiance-exclusive-en-boucle.md)).
- Jouer pour de vrai n'est pas une pré-écoute : le refus « Aucun casque configuré » du Mode Spectacle ne s'y applique pas, seuls les boutons d'aperçu restent masqués dans ce cas.
- Garde-fou du Mode Spectacle : le clic souris sur une ligne de la recherche-éclair ne fait que sélectionner (`isLiveSessionActive`), seule Entrée joue — un clic de trop ne doit pas sortir en salle (esprit de [0027](0027-preecoute-casque-stricte.md)). Hors spectacle, clic et Entrée jouent.
- À la fermeture du sélecteur, l'aperçu en cours est coupé (plus d'exception pour la recherche-éclair).
