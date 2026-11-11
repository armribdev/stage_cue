# 0037 — Mise à jour : l'app se ferme d'elle-même, l'installeur n'a plus d'`AppMutex`

**Statut :** acceptée
**Date :** 2026-11-11

## Contexte

La mise à jour v0.2.0 → v0.3.0 n'a rien installé, sans la moindre trace. L'app lançait l'installeur en `/VERYSILENT /SUPPRESSMSGBOXES` en tenant ouvert le mutex `StageCueAppMutex` (déclaré `AppMutex` dans `stage_cue.iss`) et affichait « Installation en cours… ». Reproduit avec l'installeur v0.3.0 publié et le mutex tenu : l'installeur se termine en 0,25 s, code de sortie 1, sans rien changer. Son journal (`/LOG`) dit « Defaulting to Cancel for suppressed message box (OK/Cancel) : … Stage Cue est actuellement en cours d'exécution » puis `Got EAbort exception`. Le contrôle `AppMutex` a lieu au démarrage du setup, avant `CloseApplications` : en silencieux, la boîte « fermez l'application » reçoit « Annuler » et l'installation est abandonnée.

## Décision

Plus d'`AppMutex` ni de mutex côté app. Après avoir lancé l'installeur, `runUpdateFlow` ferme l'app lui-même (`windowManager.close()`, 2 s plus tard) ; si elle tient encore des fichiers, le Restart Manager d'Inno la ferme (`CloseApplications=force`). La relance est une entrée `[Run]` explicite (`skipifnotsilent`), `RestartApplications=no`. L'installeur écrit son journal (`/LOG`) dans `%TEMP%\stagecue_update\install.log` ; au lancement suivant `reportPreviousInstall` en journalise l'issue dans `StageCue.Update` (cause comprise en cas d'échec) et efface le dossier. Téléchargement, installation et erreurs s'affichent dans un seul dialogue, jamais dans un toast.

## Alternatives écartées

- **Garder l'`AppMutex` et relâcher le mutex avant de lancer l'installeur** — l'app mettrait un temps indéterminé à disparaître, alors que le contrôle d'Inno a lieu dans les premières centaines de ms : course perdue d'avance, échec silencieux au moindre retard.
- **Retirer `/SUPPRESSMSGBOXES`** — l'utilisateur verrait une boîte Inno en plein flux, et un blocage invisible si elle passe derrière une fenêtre.
- **`RestartApplications` pour la relance** — il repose sur le Restart Manager, qui ne relance fiablement que les apps inscrites auprès de lui ; une app Flutter ne l'est pas. Une entrée `[Run]` est déterministe.

## Conséquences

- Le défaut est dans l'**installeur** : celui de v0.3.0 (et des versions antérieures) contient l'`AppMutex` et échouera toujours contre une app qui tourne. Une app ≤ 0.3.0 qui télécharge l'installeur de la première version portant ce correctif réussit en revanche (cet installeur ne teste plus le mutex ; le Restart Manager ferme l'ancienne app). Pour v0.3.0 elle-même, seule une installation manuelle (assistant visible, app fermée) fonctionne.
- Une ancienne app passe encore `/RESTARTAPPLICATIONS` (flux antérieur) : au pire une double relance lors de cette transition.
- Le dossier `stagecue_update` n'est effacé qu'après un journal d'installeur **clos** (`Log closed.`) : l'app relancée par `[Run]` démarre avant la fin de l'installeur et ne doit pas effacer son journal en cours d'écriture.
- Une installation qui aboutit à un échec laisse l'app fermée : la seule trace est la ligne `Installation précédente non aboutie` au prochain lancement (canal `StageCue.Update`, visible dans Paramètres → Diagnostic).
- Ne pas réintroduire `AppMutex` sans remplacer le mécanisme de fermeture : il abandonne l'installation en silence dès que l'app tourne.
