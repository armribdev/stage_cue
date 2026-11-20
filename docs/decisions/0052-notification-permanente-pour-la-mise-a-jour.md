# 0052 — Notification permanente pour la mise à jour, toasts au-dessus de la régie, copie réservée au debug

**Statut :** acceptée (amende 0037 et 0033)
**Date :** 2026-11-20

## Contexte

Le téléchargement et l'installation d'une mise à jour passaient par un dialogue modal non fermable ([0037](0037-mise-a-jour-par-fermeture-de-l-app-sans-appmutex.md) : « jamais dans un toast »). Le toast global ([0033](0033-toast-global-au-dessus-du-navigator.md)) n'a qu'un seul emplacement, éphémère : un autre message l'aurait remplacé. Sur desktop il se posait en bas à droite, donc **sur** la régie musique, qui occupe le bas de l'écran. Et le clic « copier le message » n'a de sens que pour le développeur : en release, l'utilisateur récupère le journal depuis Paramètres → Assistance.

## Décision

- **Un second emplacement, permanent** (`AppToastController.persistent`, `AppPersistentToast`) : message, barre de progression optionnelle (`showsProgress`, `progress` null = indéterminée), croix seulement si `dismissible`. Il s'affiche sous le toast éphémère, qui ne l'efface pas. `runUpdateFlow` y publie téléchargement (avec sa barre), installation et échec ; le dialogue de confirmation reste, le dialogue de progression disparaît.
- **Les notifications enjambent la régie** : celle-ci publie sa hauteur dans `AppToastController.bottomInset` (desktop et tactile), l'hôte ajoute ce décalage au bas.
- **`AppToastHost.allowCopy`** vaut `!kReleaseMode` : en release un toast `copyable` s'affiche en texte simple.

## Alternatives écartées

- **Garder le dialogue modal et refléter la progression dans une notification** — deux affichages du même état, et l'app resterait bloquée pendant le téléchargement.
- **Rendre le toast éphémère « épinglable »** — un message ordinaire (« Message copié ») remplacerait la progression en cours : il faut deux emplacements.
- **Mesurer la régie depuis l'hôte (clé globale, `RenderBox`)** — l'hôte est au-dessus du `Navigator` et ne connaît pas l'écran ; c'est la régie qui sait sa hauteur, et elle la publie déjà pour la grille sur mobile.

## Conséquences

- **L'app reste utilisable pendant le téléchargement**, y compris en Mode Spectacle : l'installation se lance puis l'app se ferme 2 s plus tard sans nouvelle confirmation (celle du début reste la seule). Si ce n'est pas acceptable en scène, il faudra une seconde action explicite « Installer et redémarrer » une fois le fichier téléchargé.
- `runUpdateFlow` ignore un second appel tant qu'une mise à jour est en cours (le dialogue modal l'empêchait avant).
- `bottomInset` n'est pas lié à la route : tant que l'écran du plateau est monté, les notifications restent relevées, même au-dessus d'une page poussée (Réglages, bibliothèque).
- Le contrôleur est global : un test qui pose une notification permanente ou un `bottomInset` les remet à `null` / `0` en fin de test.
