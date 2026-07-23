# 0015 — Plein écran Windows (F11) : implémentation manuelle plutôt que `window_manager.setFullScreen`

**Statut :** acceptée
**Date :** 2026-07-23

## Contexte

F11 doit basculer la fenêtre Windows en plein écran (barre de titre native et barre des tâches masquées), comme les autres apps Windows. `window_manager` (0.5.2) expose `setFullScreen()` pour ça, mais son implémentation native (`windows/window_manager.cpp`) ne redimensionne pas toujours la vue Flutter enfant à la sortie du plein écran quand la fenêtre n'était **pas maximisée** avant le F11 : le rattrapage interne (`ForceChildRefresh`) n'est déclenché que sur la bascule `SIZE_MAXIMIZED`→`SIZE_RESTORED`, jamais sur une sortie depuis l'état fenêtré normal — voir [issue #521](https://github.com/leanflutter/window_manager/issues/521) et son [PR de correctif partiel #531](https://github.com/leanflutter/window_manager/pull/531). Résultat observé : contenu tronqué/zone noire après un aller-retour F11 en fenêtré normal.

## Décision

Implémenter le plein écran nous-mêmes dans `SoundboardApp` (`lib/core/app/app.dart`), sans passer par `windowManager.setFullScreen()` :

1. Si la fenêtre n'est pas déjà maximisée, la maximiser d'abord (`windowManager.maximize()`) avant tout le reste — une fenêtre en état restauré (non maximisée) garde l'ombre portée / bordure de redimensionnement invisible que DWM dessine autour des fenêtres `WS_THICKFRAME`, visible en plein écran comme un liseré sur les bords ; l'état maximisé natif n'a pas cette marge.
2. `windowManager.setTitleBarStyle(TitleBarStyle.hidden)` pour masquer la barre de titre native.
3. Retirer `WS_THICKFRAME`/`WS_MAXIMIZEBOX` du style Win32 (`GWL_STYLE`, via `win32`/FFI) avant de redimensionner — sans ça, Windows re-snap silencieusement la fenêtre sur la zone de travail (moniteur moins barre des tâches) dès qu'elle couvre exactement les bornes du moniteur, laissant un trou à la hauteur de la barre.
4. `windowManager.setBounds()` vers les bornes **brutes** du moniteur principal (`GetMonitorInfo().rcMonitor`, interrogé directement via `win32`), pas `rcWork` (zone de travail, qui exclut la barre des tâches).
5. Masquer/afficher la barre des tâches (`Shell_TrayWnd`) via `ShowWindow` (FFI) — `window_manager` n'a pas d'API pour ça (`setSkipTaskbar` ne retire que l'icône).
6. Relier ce masquage aux évènements focus/blur de la fenêtre (`WindowListener.onWindowFocus`/`onWindowBlur` de `window_manager`, pas seulement au toggle F11) : sans ça, la barre des tâches reste dans un état visuellement cassé (transparente) quand on Alt-Tab ou appuie sur la touche Windows pendant que l'app est en plein écran.
7. Restaurer bornes, style, état maximisé et barre des tâches à la sortie (dans l'ordre inverse), plus un filet de sécurité dans `dispose()` si l'app se ferme pendant le plein écran.
8. Persister le dernier état (plein écran ou non) dans `AppPreferences` et le réappliquer au lancement.

## Alternatives écartées

- **`windowManager.setFullScreen()` tel quel** — bug de resize à la sortie du plein écran documenté ci-dessus, non résolu dans la version installée (0.5.2).
- **`screen_retriever` pour les bornes du moniteur** — son calcul de `Display.size` soustrait la position de la zone de travail au lieu d'utiliser `rcMonitor` telle quelle, ce qui rognait la hauteur exactement à la hauteur de la barre des tâches. Retiré du projet, remplacé par un appel direct à `GetMonitorInfo` via `win32`.
- **`ITaskbarList2::MarkFullscreenWindow` (COM shell)** — approche "propre" recommandée par Microsoft pour l'intégration fullscreen/shell, mais l'interface n'est pas exposée par le package `win32` installé (bindings absents) ; l'aurait nécessité un vtable COM manuel. Le couplage focus/blur ci-dessus donne un résultat équivalent pour l'usage de l'app sans cette complexité.

## Conséquences

- Toute évolution touchant `_toggleFullScreen` dans `app.dart` doit conserver l'ordre des opérations (style Win32 avant `setBounds`, `_forceFrameRefresh` après tout changement de `GWL_STYLE`) — l'inverser réintroduit le trou à la place de la barre des tâches.
- Si `window_manager` corrige un jour son bug de resize natif (voir issue #521), cette implémentation manuelle pourra être simplifiée, mais vérifier d'abord que le correctif couvre le cas "fenêtre non maximisée avant F11".
- `_mainWindowHandle()` suppose une seule fenêtre `FLUTTER_RUNNER_WIN32_WINDOW` (une seule instance de l'app) — ne pas réutiliser tel quel si le projet devait un jour supporter plusieurs fenêtres.
