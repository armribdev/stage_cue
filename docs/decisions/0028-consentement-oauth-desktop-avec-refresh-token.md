# 0028 — Consentement OAuth desktop maison, pour toujours obtenir un refresh token

**Statut :** acceptée
**Date :** 2026-11-03

## Contexte

Sur Windows/Linux, `google_sign_in_all_platforms` 1.2.1 ouvre une URL d'autorisation sans `prompt=consent`. Dès que l'utilisateur a déjà accordé l'accès, Google saute l'écran de consentement et **ne renvoie pas de refresh token** : la session mourait au bout d'une heure, sans renouvellement possible, tout en s'affichant « Connecté » au lancement suivant. De plus `GoogleSignIn.signIn()` relit d'abord le jeton stocké sans ouvrir le navigateur, donc une « reconnexion » après un rejet rejouait le même jeton révoqué. Le paquet corrigé (desktop 0.2.0, `prompt=consent`) n'est atteignable qu'avec `google_sign_in_all_platforms` 2.x, qui impose `google_sign_in` 7 (réécriture du chemin mobile).

## Décision

`GoogleDriveDesktopAuthenticator.connect()` conduit lui-même le consentement via `obtainAccessCredentialsViaUserConsent` (googleapis_auth), en ajoutant `access_type=offline` et `prompt=consent` à l'URL, redirection sur `http://localhost:8000`. Le paquet `google_sign_in_all_platforms` ne sert plus qu'au stockage (`retrieve`/`save`/`delete`) et à `signInOffline`.

## Alternatives écartées

- **Passer à `google_sign_in_all_platforms` 2.x** — tire `google_sign_in` 7 et casse le chemin mobile, hors de proportion pour un paramètre d'URL.
- **Révoquer la permission avant de se reconnecter** — le jeton à révoquer est justement celui qui est périmé ; reste le cas échéant une action manuelle de l'utilisateur sur son compte Google.
- **Forker le paquet desktop** — une dépendance de plus à maintenir pour quelques lignes.

## Conséquences

- Ne pas rappeler `GoogleSignIn.signIn()` / `signInOnline()` pour un consentement : on perdrait le refresh token (et `signIn()` ne rouvre pas le navigateur).
- Le port `8000` doit rester déclaré comme URI de redirection dans la console Google Cloud.
- `connectSilently` renvoie `null` quand le jeton d'accès est périmé et qu'il n'y a pas de refresh token : un client renvoyé ferait afficher « Connecté » pour une session condamnée. Les sessions existantes sans refresh token passent donc en « Session à renouveler » jusqu'à une reconnexion.
- À l'abandon (délai de 2 min), le serveur de redirection de googleapis_auth reste lié jusqu'à la fin du processus ; un nouvel essai échoue alors si le port est occupé (erreur journalisée par `driveSignInFailed`).
- Non vérifié sur un vrai compte au moment de l'écriture.
