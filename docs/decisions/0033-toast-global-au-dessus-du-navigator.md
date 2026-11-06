# 0033 — Notifications en toast global au-dessus du Navigator

**Statut :** acceptée
**Date :** 2026-11-06

## Contexte

Le `SnackBar` flottant était le dernier gros signal Material visible (voir [0023](0023-direction-visuelle-console-linear.md)). Il imposait aussi un contournement : le `ScaffoldMessenger` racine dessine derrière la barrière d'une modale, donc la recherche-éclair embarquait son propre `ScaffoldMessenger` local et un `Scaffold` transparent (qui recouvrait la barrière et obligeait à refaire « tap en dehors = fermer »). L'auto-dismiss natif ne s'arme pas dans certains cas (navigation accessible, `Scaffold` recouvert), d'où un `Future.delayed` de secours.

## Décision

Un hôte unique `AppToastHost`, inséré dans `MaterialApp.builder` au-dessus du `Navigator`, dessine le toast courant d'un `AppToastController` (`ChangeNotifier` global, `AppSnackBar.controller`). L'API `AppSnackBar.show` / `showCopyableSnackBar` est conservée ; `SnackBarAction` devient `AppToastAction`, la gravité (`info` / `success` / `error`) est passée explicitement.

## Alternatives écartées

- **Garder `ScaffoldMessenger` en le re-stylant** — ne résout pas le contournement : le messenger local de l'overlay de recherche reste indispensable pour être visible au-dessus d'une modale, et le look reste lié aux contraintes du `SnackBar`.
- **Un `OverlayEntry` par appel** — il passerait sous les routes poussées après lui, soit exactement le problème de la barrière modale.
- **Paquet de toasts, Riverpod/Bloc** — dépendance inutile ; le projet utilise déjà des `ChangeNotifier`.
- **Déduire la gravité du texte du message** — fragile ; `showCopyableSnackBar` (utilisé pour les erreurs) passe `error`, le reste est `info` par défaut.

## Conséquences

- Plus aucun `ScaffoldMessenger` ni `SnackBar` dans `lib/` : un nouvel appel passe par `AppSnackBar`. Le paramètre `context` de `show` n'est plus lu (conservé pour ne pas toucher ~28 appelants).
- Le contrôleur est un **état global** : les tests qui affichent un toast doivent poser un `AppToastHost` (via `MaterialApp.builder`) et refermer le toast en fin de test (`AppSnackBar.controller.dismissCurrent()`), sinon son `Timer` fuit.
- Le toast n'est plus relevé par un `Scaffold` (`bottomNavigationBar`, bouton flottant) : il peut recouvrir un pied de page en bas de l'écran pendant sa durée.
- Le toast est enveloppé dans un `TextFieldTapRegion` pour ne pas défocaliser le champ de recherche de l'overlay quand on clique dessus.
- La fermeture garantie reste un `Timer` Dart, indépendant des tickers. Le survol la suspend (desktop) et la relance, à la sortie, sur la durée complète.
