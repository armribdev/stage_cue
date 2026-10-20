# 0025 — Journal fichier persistant, borné et masqué, exportable depuis les réglages

**Statut :** acceptée
**Date :** 2026-10-20

## Contexte

Stage Cue tourne en live (théâtre, stream, JDR). `SyncLog`, `AudioLoadLog` et `UpdateLog` n'émettaient que via `developer.log`, visible uniquement dans DevTools : **rien en build release** ni sur une machine sans outils de dev. Les `debugPrint` bruts (lecture, cue, watcher) étaient invisibles en release, et une exception non audio ne laissait aucune trace (`FlutterError.onError` retombait sur la console). Quand quelque chose rate en représentation, on ne pouvait rien relire après coup — et la question post-incident est toujours « pourquoi ce pad n'a-t-il rien joué ? ».

## Décision

Un **journal fichier persistant** (`lib/core/logging/log_sink.dart`, classe à méthodes statiques comme `SyncLog`), alimenté par `SyncLog`, `AudioLoadLog`, `UpdateLog` et un nouveau `AppLog` (canal `StageCue.App` : cycle de vie, Mode Spectacle, migrations, erreurs non gérées). Les quatre classes gardent leur API et leur `developer.log` ; leur `_emit` transmet en plus au sink. Les `trace` n'y vont que si leur `--dart-define` est actif.

- **Jamais de ralentissement ni de plantage.** `LogSink.log` est synchrone, sans E/S : il formate, masque et pousse dans un buffer mémoire. L'écriture est asynchrone (flush ~1 s, immédiat sur `severe` et à la mise en arrière-plan, vidange à la fermeture), sur une chaîne sérialisée. Toute erreur d'E/S est avalée et comptée (`lostLines`), signalée par une ligne à la prochaine écriture réussie.
- **Rotation bornée** : `stage-cue.log` + 2 archives de ~1 Mo, tournées au démarrage de session et au dépassement (≈ 3 Mo max). Dossier `<support de l'app>/logs/`, à côté de `db.sqlite`.
- **Confidentialité** : `LogRedactor` masque jetons OAuth (`ya29.…`, refresh `1//…`, JWT, `Bearer …`, `refresh_token`/`client_secret`/…) et adresses e-mail dans le message, l'erreur et la stack. C'est un filet de sécurité : les appelants ne logguent pas d'identité (auth Drive : l'événement, jamais le compte).
- **En-tête de session** posé une fois `AppServices` prêt (version, OS, schéma, locale, cue configuré oui/non, espace libre sur le volume du cache). Il reste la première chose du fichier : le sink n'écrit rien avant, sauf sur un `severe` précoce.
- **Erreurs non gérées de tout type** (`FlutterError.onError`, `PlatformDispatcher.onError`, zone) → `AppLog.uncaughtError` ; filtrage des faux positifs SoLoud et chaînage vers le handler précédent conservés ; une même exception remontée par deux handlers n'est écrite qu'une fois.
- **Marqueur d'arrêt propre** (`session.lock`) : posé au démarrage, supprimé par `didRequestAppExit`. Vérifié sous Windows (voir Conséquences). Désactivé en debug (un hot restart relance `main` sans fermeture).
- **Export** : section « Diagnostic » des réglages (`settings/settings_diagnostic.dart`) — export en `.txt` daté via `file_picker`, copie des ~500 dernières lignes, ouverture du dossier (desktop). Aucune dépendance ajoutée.

## Alternatives écartées

- **Package de logging tiers (`logging`, `logger`, Sentry…)** — nouvelle dépendance pour un besoin étroit, et un service distant enverrait des données hors de l'appareil ; l'app doit rester utilisable hors-ligne et sans compte.
- **Écriture synchrone (`writeAsStringSync`) à chaque ligne** — plus simple et sans perte au crash, mais une E/S sur le thread UI sur le chemin d'un déclenchement de pad est exactement ce qu'on ne tolère pas ; le flush immédiat sur `severe` couvre le cas du crash.
- **Un fichier par session sans plafond global** — croissance non bornée sur un appareil de régie rarement nettoyé.
- **Journaliser chaque lecture / chaque pad / la progression de waveform** — bruit qui noie le signal ; ce détail reste en `trace`.
- **`setPreventClose(true)` + `onWindowClose`** pour le marqueur d'arrêt — change le comportement de fermeture (risque de fenêtre qui ne se ferme plus si le flush bloque) alors que `didRequestAppExit` suffit.

## Conséquences

- **Nouveau code = une ligne par événement, jamais par fichier/frame/pad en boucle.** Une cause répétée passe par `AudioLoadLog.warnOnce`/`_once` ou une fenêtre de déduplication (`padTriggerFailed`, `driveAuthRejected`). Voir `.claude/rules/logging.md`.
- Un déclenchement de pad qui ne joue rien doit appeler `reportPadTriggerFailure` avec une raison explicite — pas de `return` silencieux.
- `AudioPlayerService.playOverlapping` retourne désormais `Future<bool>` et expose `lastStartFailure` ; les fakes de test (`implements AudioPlayerService`) doivent les déclarer.
- **Arrêt propre sous Windows** : `didRequestAppExit` se déclenche sur `WM_CLOSE` — vérifié en release avec `Process.CloseMainWindow()` (le même message que la croix de fenêtre et Alt+F4, mais ces deux gestes n'ont pas été testés à la main) : marqueur supprimé, ligne « Fermeture » écrite, et « session précédente sans arrêt propre » correctement signalée après un `Stop-Process -Force`, absente après une fermeture normale. **Non vérifié** : `_quitApp` (`windowManager.close()`), arrêt/déconnexion de session Windows (`WM_QUERYENDSESSION`) et fermeture par l'installeur Inno Setup ; un faux « sans arrêt propre » reste possible dans ces cas.
- Le journal contient des noms de pads, de sons et de bibliothèques : il est local et exporté par l'utilisateur, mais ne pas y ajouter de chemins absolus (le dossier utilisateur contient un nom de compte) — les dossiers surveillés sont journalisés par leur nom de base.
- Le sink est un singleton statique : les tests passent par `LogSink.resetForTest()` et un dossier temporaire (voir `test/core/logging/`).
