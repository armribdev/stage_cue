# 0027 — Pré-écoute au casque stricte : jamais de repli sur la salle

**Statut :** acceptée
**Date :** 2026-11-02

## Contexte

Le but d'une pré-écoute est d'entendre un son sans que le public l'entende. Le cue (`CueAudioService`, Windows seulement) route la pré-écoute vers un second périphérique via media_kit, mais il se dégradait en silence vers flutter_soloud — donc la salle — dès que media_kit échouait. Pire : mpv accepte un nom de device introuvable et joue alors sur le défaut système, sans erreur. Un casque débranché en plein spectacle faisait donc sortir en salle un son que l'on croyait écouter seul. Par ailleurs la musique de la recherche-éclair passait par la régie live (salle) et les pads du plateau n'avaient aucune pré-écoute.

## Décision

Quand un casque est choisi, la pré-écoute est **stricte** : son absence (device introuvable dans l'énumération du lecteur, échec d'ouverture) lève `CueUnavailableException` et rien ne sort. `createPreviewPlayer(requireCue: true)` étend cette rigueur au cas « aucun casque choisi » pour les écoutes qui n'ont de sens qu'au casque (bouton casque d'un pad).

## Alternatives écartées

- **Conserver le repli sur flutter_soloud** — comportement historique, mais c'est précisément la fuite à supprimer : une pré-écoute « réussie » sur la mauvaise sortie est pire qu'un échec visible.
- **Demander confirmation avant de basculer en salle** — une modale en plein spectacle est inutilisable, et un clic réflexe réintroduit la fuite.
- **Router la pré-écoute avec soloud sur un second moteur** — impossible : flutter_soloud n'a qu'un moteur de sortie.

## Conséquences

- Tout nouvel appel de pré-écoute passe par `CueAudioService.createPreviewPlayer` et doit gérer `CueUnavailableException` (message lisible dans `.message`). Dans `SamplerNotifier` le refus est posé dans `_lastPreviewError` (`consumeLastPreviewError`) et affiché une seule fois par `SamplerScreen` ou le sélecteur — ne jamais l'avaler : un bouton casque muet passe pour une panne.
- Ne pas réintroduire de repli soloud quand `isCueActive` est vrai, ni retirer la vérification de présence du device dans `CuePreviewPlayer.create`.
- La sortie par défaut du système (`PlaybackDevice.isDefault` de flutter_soloud, celle de la salle) est exclue de la liste des casques (`excludeRoomDevice`) et refusée à la lecture si le casque choisi l'est devenu entre-temps. La correspondance se fait sur le libellé du périphérique entre soloud et media_kit ; si le défaut est indéterminable, rien n'est exclu.
- Sans casque choisi, la pré-écoute ordinaire (recherche-éclair, bibliothèque) garde son comportement historique hors spectacle : elle sort en salle. **En Mode Spectacle**, sur une plateforme capable d'une sortie séparée (`CueAudioService.isSupported`), elle est refusée (`_refuseRoomPreviewInLive`) — un clic de trop ne doit pas sortir en salle. Sur une plateforme sans sortie séparée, aucune alternative n'existe : rien n'est refusé. Le bouton casque d'un pad refuse dans tous les cas.
- Avec un casque actif, la musique de la recherche-éclair passe par le lecteur d'aperçu (play/pause), plus par la régie.
- Windows uniquement. Ailleurs, `requireCue` refuse toujours : pas de sortie séparée possible.
- Non vérifié sur matériel : le comportement réel d'un casque débranché à chaud (énumération mpv à jour ou non) reste à confirmer sur Windows.
